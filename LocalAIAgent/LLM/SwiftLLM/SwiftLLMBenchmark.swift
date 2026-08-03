import Foundation

// MARK: - SwiftLLM Benchmark
// Quick benchmark to test and compare SwiftLLM vs llama.cpp

@MainActor
final class SwiftLLMBenchmark {

    /// Run a quick benchmark comparing SwiftLLM output with expected behavior
    static func runBenchmark(modelPath: URL) async {
        print("=" * 60)
        print("[SwiftLLM Benchmark] Starting...")
        print("=" * 60)

        let swiftLLM = SwiftInference()

        // 1. Load model
        let loadStart = CFAbsoluteTimeGetCurrent()
        do {
            try await swiftLLM.loadModel(from: modelPath)
        } catch {
            print("[Benchmark] FAILED to load model: \(error)")
            return
        }
        let loadTime = CFAbsoluteTimeGetCurrent() - loadStart
        print("[Benchmark] Model loaded in \(String(format: "%.2f", loadTime))s")

        // 2. Test tokenizer
        let testText = "Hello, world! こんにちは世界"
        if let tokenizer = getTokenizer(swiftLLM) {
            let tokens = tokenizer.encode(testText)
            let decoded = tokenizer.decode(tokens)
            print("[Benchmark] Tokenizer test:")
            print("  Input:   '\(testText)'")
            print("  Tokens:  \(tokens.count) ids: \(tokens.prefix(20))")
            print("  Decoded: '\(decoded)'")
            let match = decoded == testText
            print("  Round-trip: \(match ? "✅ PASS" : "❌ FAIL")")
        }

        // 3. Generate text (greedy, temperature=0)
        print("\n[Benchmark] Generation test (greedy, max 50 tokens):")
        let prompt = "<|im_start|>system\nYou are a helpful assistant.<|im_end|>\n<|im_start|>user\nWhat is 2+2?<|im_end|>\n<|im_start|>assistant\n"

        var output = ""
        let genStart = CFAbsoluteTimeGetCurrent()
        do {
            output = try await swiftLLM.generate(
                prompt: prompt,
                maxTokens: 50,
                temperature: 0.0,  // Greedy for reproducibility
                topP: 1.0,
                topK: 1,
                repeatPenalty: 1.0,
                stopSequences: ["<|im_end|>"],
                onToken: { token in
                    // No-op for benchmark
                }
            )
        } catch {
            print("[Benchmark] Generation FAILED: \(error)")
        }
        let genTime = CFAbsoluteTimeGetCurrent() - genStart

        print("  Prompt tokens: ~\(prompt.count / 4)")
        print("  Output: '\(output.prefix(200))'")
        print("  Time: \(String(format: "%.2f", genTime))s")
        print("  Contains '4': \(output.contains("4") ? "✅" : "⚠️")")

        // 4. Throughput test
        print("\n[Benchmark] Throughput test (100 tokens):")
        let throughputStart = CFAbsoluteTimeGetCurrent()
        var tokenCount = 0
        do {
            _ = try await swiftLLM.generate(
                prompt: "<|im_start|>user\nTell me a story<|im_end|>\n<|im_start|>assistant\n",
                maxTokens: 100,
                temperature: 0.7,
                onToken: { _ in tokenCount += 1 }
            )
        } catch {
            print("[Benchmark] Throughput test failed: \(error)")
        }
        let throughputTime = CFAbsoluteTimeGetCurrent() - throughputStart
        let tokensPerSec = Double(tokenCount) / throughputTime
        print("  Generated: \(tokenCount) tokens")
        print("  Time: \(String(format: "%.2f", throughputTime))s")
        print("  Speed: \(String(format: "%.1f", tokensPerSec)) tokens/sec")

        // 5. Summary
        print("\n" + "=" * 60)
        print("[SwiftLLM Benchmark] Summary")
        print("  Load time:    \(String(format: "%.2f", loadTime))s")
        print("  Decode speed: \(String(format: "%.1f", tokensPerSec)) t/s")
        print("  Memory:       Pure Swift + Accelerate (no llama.cpp)")
        print("=" * 60)

        swiftLLM.unload()
    }

    /// Access tokenizer via reflection (for testing only)
    private static func getTokenizer(_ inference: SwiftInference) -> BPETokenizer? {
        let mirror = Mirror(reflecting: inference)
        for child in mirror.children {
            if child.label == "tokenizer", let tok = child.value as? BPETokenizer {
                return tok
            }
        }
        return nil
    }
}

// Helper
private func * (lhs: String, rhs: Int) -> String {
    String(repeating: lhs, count: rhs)
}
