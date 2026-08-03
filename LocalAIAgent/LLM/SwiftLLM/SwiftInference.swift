import Foundation
import Accelerate

// MARK: - SwiftInference
// Pure Swift LLM inference engine — drop-in replacement for LlamaInference

@MainActor
final class SwiftInference: ObservableObject {
    @Published private(set) var isLoaded = false
    @Published private(set) var isGenerating = false
    @Published private(set) var loadingProgress: Double = 0
    @Published private(set) var modelName: String = ""

    private var model: TransformerModel?
    private var tokenizer: BPETokenizer?
    private var gguf: GGUFFile?

    nonisolated(unsafe) static var abortFlag = false

    // Background queue for inference
    private static let inferenceQueue = DispatchQueue(label: "love.elio.swiftllm.inference", qos: .userInitiated)

    enum SwiftLLMError: Error, LocalizedError {
        case modelNotLoaded
        case generationFailed(String)
        case loadFailed(String)

        var errorDescription: String? {
            switch self {
            case .modelNotLoaded: return "SwiftLLM model not loaded"
            case .generationFailed(let msg): return "Generation failed: \(msg)"
            case .loadFailed(let msg): return "Load failed: \(msg)"
            }
        }
    }

    // MARK: - Load Model

    func loadModel(from url: URL) async throws {
        let startTime = CFAbsoluteTimeGetCurrent()
        modelName = url.lastPathComponent
        loadingProgress = 0.1
        print("[SwiftLLM] Loading model: \(url.lastPathComponent)")

        // Parse GGUF on background thread
        let ggufFile = try await Task.detached(priority: .userInitiated) {
            try GGUFParser.parse(url: url)
        }.value

        self.gguf = ggufFile
        loadingProgress = 0.3
        print("[SwiftLLM] GGUF parsed: arch=\(ggufFile.architecture), layers=\(ggufFile.blockCount), embd=\(ggufFile.embeddingLength)")

        // Build tokenizer
        let tok = BPETokenizer(gguf: ggufFile)
        self.tokenizer = tok
        loadingProgress = 0.4
        print("[SwiftLLM] Tokenizer built: vocab=\(tok.vocab.count)")

        // Load weights on background thread
        let (config, weights) = try await Task.detached(priority: .userInitiated) {
            try Self.loadWeights(from: ggufFile)
        }.value

        loadingProgress = 0.9
        print("[SwiftLLM] Weights loaded: \(config.nLayers) layers")

        self.model = TransformerModel(config: config, weights: weights)
        isLoaded = true
        loadingProgress = 1.0

        let elapsed = CFAbsoluteTimeGetCurrent() - startTime
        print("[SwiftLLM] Model loaded in \(String(format: "%.2f", elapsed))s")
    }

    func unload() {
        model = nil
        tokenizer = nil
        gguf = nil
        isLoaded = false
        modelName = ""
        loadingProgress = 0
    }

    // MARK: - Generate

    func generate(
        prompt: String,
        maxTokens: Int = 512,
        temperature: Float = 0.7,
        topP: Float = 0.9,
        topK: Int = 40,
        repeatPenalty: Float = 1.1,
        stopSequences: [String] = [],
        onToken: @escaping @MainActor (String) -> Void
    ) async throws -> String {
        guard isLoaded, let model = model, let tokenizer = tokenizer else {
            throw SwiftLLMError.modelNotLoaded
        }

        Self.abortFlag = false
        isGenerating = true
        defer { isGenerating = false }

        let inputTokens = tokenizer.encode(prompt)
        print("[SwiftLLM] Input tokens: \(inputTokens.count)")

        let samplerConfig = SamplerConfig(
            temperature: temperature,
            topP: topP,
            topK: topK,
            repeatPenalty: repeatPenalty
        )

        // Run inference on background queue
        let result: String = try await withCheckedThrowingContinuation { continuation in
            Self.inferenceQueue.async {
                do {
                    let text = try self.inferenceLoop(
                        model: model,
                        tokenizer: tokenizer,
                        inputTokens: inputTokens,
                        maxTokens: maxTokens,
                        samplerConfig: samplerConfig,
                        stopSequences: stopSequences,
                        onToken: onToken
                    )
                    continuation.resume(returning: text)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }

        return result
    }

    // MARK: - Inference Loop (runs on background queue)

    private nonisolated func inferenceLoop(
        model: TransformerModel,
        tokenizer: BPETokenizer,
        inputTokens: [Int],
        maxTokens: Int,
        samplerConfig: SamplerConfig,
        stopSequences: [String],
        onToken: @escaping @MainActor (String) -> Void
    ) throws -> String {
        let sampler = Sampler(config: samplerConfig)

        model.clearCache()
        var generatedText = ""
        var allTokens = inputTokens
        var pendingUIText = ""
        var tokensSinceDispatch = 0
        let dispatchInterval = 4

        let prefillStart = CFAbsoluteTimeGetCurrent()

        // Prefill: process all input tokens
        for (i, tokenId) in inputTokens.enumerated() {
            if SwiftInference.abortFlag { break }
            _ = model.forward(tokenId: tokenId, position: i)
        }

        let prefillTime = CFAbsoluteTimeGetCurrent() - prefillStart
        let prefillTPS = Double(inputTokens.count) / prefillTime
        print("[SwiftLLM] Prefill: \(inputTokens.count) tokens in \(String(format: "%.2f", prefillTime))s (\(String(format: "%.1f", prefillTPS)) t/s)")

        let decodeStart = CFAbsoluteTimeGetCurrent()
        var generatedCount = 0

        // Decode: generate tokens one by one
        var position = inputTokens.count
        var lastLogits = model.forward(tokenId: inputTokens.last!, position: inputTokens.count - 1)

        // Re-run the last token to get proper logits (since prefill discards intermediate logits)
        // Actually, the last forward() call already gives us the logits we need

        for _ in 0..<maxTokens {
            if SwiftInference.abortFlag { break }

            // Sample next token
            let nextToken = sampler.sample(logits: &lastLogits, previousTokens: allTokens)

            // Check EOS
            if nextToken == tokenizer.eosTokenId { break }

            allTokens.append(nextToken)
            generatedCount += 1

            // Decode token to text
            let tokenText = tokenizer.decode(tokenId: nextToken)
            generatedText += tokenText
            pendingUIText += tokenText
            tokensSinceDispatch += 1

            // Batch UI updates
            if tokensSinceDispatch >= dispatchInterval || tokenText.contains("\n") {
                let textToSend = pendingUIText
                pendingUIText = ""
                tokensSinceDispatch = 0
                Task { @MainActor in
                    onToken(textToSend)
                }
            }

            // Check stop sequences
            for stop in stopSequences {
                if generatedText.hasSuffix(stop) {
                    // Flush remaining
                    if !pendingUIText.isEmpty {
                        let text = pendingUIText
                        Task { @MainActor in onToken(text) }
                    }
                    let decodeTime = CFAbsoluteTimeGetCurrent() - decodeStart
                    let decodeTPS = Double(generatedCount) / decodeTime
                    print("[SwiftLLM] Decode: \(generatedCount) tokens in \(String(format: "%.2f", decodeTime))s (\(String(format: "%.1f", decodeTPS)) t/s)")
                    return generatedText
                }
            }

            // Forward pass for next token
            lastLogits = model.forward(tokenId: nextToken, position: position)
            position += 1
        }

        // Flush remaining UI text
        if !pendingUIText.isEmpty {
            let text = pendingUIText
            Task { @MainActor in onToken(text) }
        }

        let decodeTime = CFAbsoluteTimeGetCurrent() - decodeStart
        let decodeTPS = generatedCount > 0 ? Double(generatedCount) / decodeTime : 0
        print("[SwiftLLM] Decode: \(generatedCount) tokens in \(String(format: "%.2f", decodeTime))s (\(String(format: "%.1f", decodeTPS)) t/s)")

        return generatedText
    }

    // MARK: - Weight Loading

    private nonisolated static func loadWeights(from gguf: GGUFFile) throws -> (TransformerModel.Config, TransformerModel.Weights) {
        let arch = gguf.architecture
        let nLayers = gguf.blockCount
        let nHeads = gguf.headCount
        let nKVHeads = gguf.headCountKV
        let embDim = gguf.embeddingLength
        let headDim = embDim / nHeads
        let ffnDim = gguf.feedForwardLength
        let vocabSize = gguf.vocabSize

        let config = TransformerModel.Config(
            nLayers: nLayers,
            nHeads: nHeads,
            nKVHeads: nKVHeads,
            embDim: embDim,
            headDim: headDim,
            ffnDim: ffnDim,
            vocabSize: vocabSize,
            rmsNormEps: gguf.rmsNormEps,
            ropeFreqBase: gguf.ropeFreqBase,
            maxSeqLen: min(gguf.contextLength, 8192)
        )

        print("[SwiftLLM] Config: layers=\(nLayers) heads=\(nHeads) kv_heads=\(nKVHeads) embd=\(embDim) head_dim=\(headDim) ffn=\(ffnDim) vocab=\(vocabSize)")

        func loadTensor(_ name: String) throws -> [Float] {
            guard let info = gguf.tensors[name] else {
                throw GGUFError.tensorNotFound(name)
            }
            let raw = gguf.tensorData(for: info)
            return Dequantize.dequantize(raw, type: info.type, count: info.elementCount)
        }

        // Token embedding
        let tokenEmb = try loadTensor("token_embd.weight")
        let outputNorm = try loadTensor("output_norm.weight")

        // Output weight (may be tied with token embedding)
        var outputWeight: [Float]? = nil
        if gguf.tensors["output.weight"] != nil {
            outputWeight = try loadTensor("output.weight")
        }

        // Load layers
        var layers: [TransformerModel.LayerWeights] = []
        for i in 0..<nLayers {
            let prefix = "blk.\(i)"

            let attnNorm = try loadTensor("\(prefix).attn_norm.weight")
            let ffnNorm = try loadTensor("\(prefix).ffn_norm.weight")
            let wq = try loadTensor("\(prefix).attn_q.weight")
            let wk = try loadTensor("\(prefix).attn_k.weight")
            let wv = try loadTensor("\(prefix).attn_v.weight")
            let wo = try loadTensor("\(prefix).attn_output.weight")
            let wGate = try loadTensor("\(prefix).ffn_gate.weight")
            let wUp = try loadTensor("\(prefix).ffn_up.weight")
            let wDown = try loadTensor("\(prefix).ffn_down.weight")

            // Optional QK norm (Qwen3)
            var qNorm: [Float]? = nil
            var kNorm: [Float]? = nil
            if gguf.tensors["\(prefix).attn_q_norm.weight"] != nil {
                qNorm = try loadTensor("\(prefix).attn_q_norm.weight")
                kNorm = try loadTensor("\(prefix).attn_k_norm.weight")
            }

            layers.append(TransformerModel.LayerWeights(
                attnNorm: attnNorm,
                ffnNorm: ffnNorm,
                wq: wq,
                wk: wk,
                wv: wv,
                wo: wo,
                wGate: wGate,
                wUp: wUp,
                wDown: wDown,
                qNorm: qNorm,
                kNorm: kNorm
            ))

            if (i + 1) % 7 == 0 {
                print("[SwiftLLM] Loaded layer \(i+1)/\(nLayers)")
            }
        }

        let weights = TransformerModel.Weights(
            tokenEmbedding: tokenEmb,
            outputNorm: outputNorm,
            outputWeight: outputWeight,
            layers: layers
        )

        return (config, weights)
    }

    // MARK: - Chat Prompt Formatting

    func formatChatPrompt(messages: [(role: String, content: String)], systemPrompt: String) -> String {
        var prompt = "<|im_start|>system\n\(systemPrompt)<|im_end|>\n"
        for msg in messages {
            prompt += "<|im_start|>\(msg.role)\n\(msg.content)<|im_end|>\n"
        }
        prompt += "<|im_start|>assistant\n"
        return prompt
    }
}
