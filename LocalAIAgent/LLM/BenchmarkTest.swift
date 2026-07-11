import Foundation
import LlamaSwift

// MARK: - Test Data Structures

struct BenchmarkTestCase {
    let query: String
    let expectedTool: String
    let category: String
}

struct BenchmarkTestResult {
    let query: String
    let expected: String
    let got: String
    let passed: Bool
    let category: String
    let rawOutput: String
}

struct BenchmarkMultiTurnResult {
    let testName: String
    let turns: [(query: String, response: String)]
    let passed: Bool
    let reason: String
}

// MARK: - Auto Test Runner (Tool Selection)
// Ported from NOU app's AutoTest.swift

func runBenchmarkAutoTests(
    modelPath: String,
    log: @escaping (String) -> Void,
    onResult: ((BenchmarkTestResult) -> Void)? = nil
) -> [BenchmarkTestResult] {
    let testCases: [BenchmarkTestCase] = [
        // General Knowledge (none)
        BenchmarkTestCase(query: "What is quantum computing?", expectedTool: "none", category: "Knowledge"),
        BenchmarkTestCase(query: "\u{3053}\u{3093}\u{306B}\u{3061}\u{306F}", expectedTool: "none", category: "Greeting"),
        BenchmarkTestCase(query: "Explain photosynthesis briefly", expectedTool: "none", category: "Knowledge"),
        BenchmarkTestCase(query: "Swift\u{3067}\u{30BD}\u{30FC}\u{30C8}\u{95A2}\u{6570}\u{3092}\u{66F8}\u{3044}\u{3066}", expectedTool: "none", category: "Coding"),
        BenchmarkTestCase(query: "\u{5BCC}\u{58EB}\u{5C71}\u{306E}\u{9AD8}\u{3055}\u{306F}\u{FF1F}", expectedTool: "none", category: "Knowledge"),
        BenchmarkTestCase(query: "Write a haiku about the ocean", expectedTool: "none", category: "Creative"),
        BenchmarkTestCase(query: "What is the capital of France?", expectedTool: "none", category: "Knowledge"),
        BenchmarkTestCase(query: "Explain the difference between TCP and UDP", expectedTool: "none", category: "Knowledge"),
        BenchmarkTestCase(query: "How do I make scrambled eggs?", expectedTool: "none", category: "HowTo"),
        BenchmarkTestCase(query: "What are the benefits of meditation?", expectedTool: "none", category: "Knowledge"),

        // Web Search (search)
        BenchmarkTestCase(query: "\u{4ECA}\u{65E5}\u{306E}\u{30D3}\u{30C3}\u{30C8}\u{30B3}\u{30A4}\u{30F3}\u{306E}\u{4FA1}\u{683C}\u{306F}\u{FF1F}", expectedTool: "search", category: "Price"),
        BenchmarkTestCase(query: "Latest news about Apple", expectedTool: "search", category: "News"),
        BenchmarkTestCase(query: "Tesla stock price today", expectedTool: "search", category: "Price"),
        BenchmarkTestCase(query: "\u{660E}\u{65E5}\u{306E}\u{6771}\u{4EAC}\u{306E}\u{5929}\u{6C17}\u{306F}\u{FF1F}", expectedTool: "search", category: "Weather"),
        BenchmarkTestCase(query: "Who won the Super Bowl 2026?", expectedTool: "search", category: "Event"),
        BenchmarkTestCase(query: "\u{4ECA}\u{65E5}\u{306E}\u{30CB}\u{30E5}\u{30FC}\u{30B9}\u{3092}\u{6559}\u{3048}\u{3066}", expectedTool: "search", category: "News"),
        BenchmarkTestCase(query: "What is trending on Twitter right now?", expectedTool: "search", category: "News"),

        // Calculator (calc)
        BenchmarkTestCase(query: "123 * 456 \u{306F}\u{FF1F}", expectedTool: "calc", category: "Math"),
        BenchmarkTestCase(query: "What is 15% of 3200?", expectedTool: "calc", category: "Math"),
        BenchmarkTestCase(query: "3.14 * 100", expectedTool: "calc", category: "Math"),
        BenchmarkTestCase(query: "1000 / 7 \u{3092}\u{8A08}\u{7B97}\u{3057}\u{3066}", expectedTool: "calc", category: "Math"),
        BenchmarkTestCase(query: "How much is 25 * 48?", expectedTool: "calc", category: "Math"),
        BenchmarkTestCase(query: "500 + 300 - 150", expectedTool: "calc", category: "Math"),

        // Time (time)
        BenchmarkTestCase(query: "\u{4ECA}\u{4F55}\u{6642}\u{FF1F}", expectedTool: "time", category: "Time"),
        BenchmarkTestCase(query: "What day is it today?", expectedTool: "time", category: "Time"),
        BenchmarkTestCase(query: "\u{4ECA}\u{65E5}\u{306F}\u{4F55}\u{66DC}\u{65E5}\u{FF1F}", expectedTool: "time", category: "Time"),
        BenchmarkTestCase(query: "What is today's date?", expectedTool: "time", category: "Time"),

        // Edge Cases
        BenchmarkTestCase(query: "Tell me a joke", expectedTool: "none", category: "Creative"),
        BenchmarkTestCase(query: "Translate 'hello' to Japanese", expectedTool: "none", category: "Translation"),
        BenchmarkTestCase(query: "How tall is the Eiffel Tower?", expectedTool: "none", category: "Knowledge"),

        // Unit Conversion (convert)
        BenchmarkTestCase(query: "Convert 10 km to miles", expectedTool: "convert", category: "Convert"),
        BenchmarkTestCase(query: "30\u{00B0}C \u{306F}\u{83EF}\u{6C0F}\u{4F55}\u{5EA6}\u{FF1F}", expectedTool: "convert", category: "Convert"),
        BenchmarkTestCase(query: "How many pounds is 70 kg?", expectedTool: "convert", category: "Convert"),
        BenchmarkTestCase(query: "100 cm to inches", expectedTool: "convert", category: "Convert"),

        // Random (random)
        BenchmarkTestCase(query: "Generate a random password", expectedTool: "random", category: "Random"),
        BenchmarkTestCase(query: "\u{30B5}\u{30A4}\u{30B3}\u{30ED}\u{3092}\u{632F}\u{3063}\u{3066}", expectedTool: "random", category: "Random"),
        BenchmarkTestCase(query: "Flip a coin", expectedTool: "random", category: "Random"),
        BenchmarkTestCase(query: "Random number between 1 and 100", expectedTool: "random", category: "Random"),
    ]

    log("=== AUTO TEST START (\(testCases.count) cases) ===")

    var mp = llama_model_default_params()
    mp.n_gpu_layers = 99; mp.use_mmap = true
    guard let model = llama_model_load_from_file(modelPath, mp) else {
        log("AUTOTEST: model load FAILED"); return []
    }
    let vocab = llama_model_get_vocab(model)!

    var cp = llama_context_default_params()
    cp.n_ctx = 512; cp.n_threads = 4; cp.n_threads_batch = 4
    guard let ctx = llama_init_from_model(model, cp) else {
        log("AUTOTEST: ctx FAILED"); llama_model_free(model); return []
    }

    let smpl = llama_sampler_chain_init(llama_sampler_chain_default_params())!
    llama_sampler_chain_add(smpl, llama_sampler_init_penalties(64, 1.15, 0, 0))
    llama_sampler_chain_add(smpl, llama_sampler_init_temp(0.1))
    llama_sampler_chain_add(smpl, llama_sampler_init_top_k(10))
    llama_sampler_chain_add(smpl, llama_sampler_init_top_p(0.9, 1))
    llama_sampler_chain_add(smpl, llama_sampler_init_dist(UInt32.max))

    var results: [BenchmarkTestResult] = []
    var correct = 0

    for (idx, tc) in testCases.enumerated() {
        let prompt = "<|im_start|>system\nClassify into: search, calc, time, convert, random, none. ONE word.<|im_end|>\n<|im_start|>user\ncalc=math(+\u{2212}*/%). time=now. search=live web(news,weather,prices,events). convert=units(km,\u{00B0}C,kg). random=dice/password. none=knowledge/coding/chat.\n\nHello\u{2192}none\n\u{5929}\u{6C17}\u{2192}search\n2+2\u{2192}calc\n\u{4ECA}\u{4F55}\u{6642}\u{2192}time\nDNA?\u{2192}none\n\u{682A}\u{4FA1}\u{2192}search\n\u{30B3}\u{30FC}\u{30C9}\u{2192}none\n\u{5BCC}\u{58EB}\u{5C71}\u{2192}none\n\u{5929}\u{6C17}\u{4E88}\u{5831}\u{2192}search\nWho won?\u{2192}search\n\u{4F55}\u{66DC}\u{65E5}\u{2192}time\n\u{304A}\u{3059}\u{3059}\u{3081}\u{2192}none\n10km to miles\u{2192}convert\npassword\u{2192}random\n\u{30B5}\u{30A4}\u{30B3}\u{30ED}\u{2192}random\njoke\u{2192}none\ncoin flip\u{2192}random\n\nQ: \(tc.query)\nA:<|im_end|>\n<|im_start|>assistant\n<think>\n</think>\n"

        if let mem = llama_get_memory(ctx) { llama_memory_clear(mem, true) }

        let maxTok: Int32 = 256
        let buf = UnsafeMutablePointer<llama_token>.allocate(capacity: Int(maxTok))
        let nTok = llama_tokenize(vocab, prompt, Int32(prompt.utf8.count), buf, maxTok, true, true)
        guard nTok > 0 else { buf.deallocate(); continue }

        var batch = llama_batch_init(nTok, 0, 1)
        for i in 0..<Int(nTok) {
            batch.token[i] = buf[i]; batch.pos[i] = Int32(i)
            batch.n_seq_id[i] = 1; batch.seq_id[i]![0] = 0; batch.logits[i] = 0
        }
        batch.logits[Int(nTok)-1] = 1; batch.n_tokens = nTok
        guard llama_decode(ctx, batch) == 0 else { buf.deallocate(); llama_batch_free(batch); continue }

        var output = ""
        var pos = nTok
        let pBuf = UnsafeMutablePointer<CChar>.allocate(capacity: 64)
        for _ in 0..<10 {
            let tok = llama_sampler_sample(smpl, ctx, -1)
            if llama_vocab_is_eog(vocab, tok) { break }
            memset(pBuf, 0, 64)
            let pLen = llama_token_to_piece(vocab, tok, pBuf, 64, 0, true)
            if pLen > 0 { output += String(cString: pBuf) }
            batch.n_tokens = 0
            batch.token[0] = tok; batch.pos[0] = pos
            batch.n_seq_id[0] = 1; batch.seq_id[0]![0] = 0; batch.logits[0] = 1
            batch.n_tokens = 1; pos += 1
            if llama_decode(ctx, batch) != 0 { break }
        }
        pBuf.deallocate(); buf.deallocate(); llama_batch_free(batch)

        let choice = output.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let chosen = ["memo_save", "memo_find", "search", "calc", "time", "fetch", "convert", "random"].first(where: { choice.contains($0) }) ?? "none"
        let pass = chosen == tc.expectedTool
        if pass { correct += 1 }

        let result = BenchmarkTestResult(
            query: tc.query, expected: tc.expectedTool, got: chosen,
            passed: pass, category: tc.category, rawOutput: String(choice.prefix(20))
        )
        results.append(result)
        onResult?(result)

        log("TEST[\(idx+1)/\(testCases.count)]: \(pass ? "PASS" : "FAIL") | \(tc.expectedTool)->\(chosen) | \(tc.category): \(tc.query.prefix(30))")
    }

    llama_sampler_free(smpl); llama_free(ctx); llama_model_free(model)
    log("=== AUTO TEST DONE: \(correct)/\(testCases.count) (\(Int(Float(correct)/Float(testCases.count)*100))%) ===")
    return results
}

// MARK: - Multi-turn Conversation Test

func runBenchmarkMultiTurnTests(
    modelPath: String,
    log: @escaping (String) -> Void,
    onResult: ((BenchmarkMultiTurnResult) -> Void)? = nil
) -> [BenchmarkMultiTurnResult] {
    log("=== MULTI-TURN TEST START ===")

    var mp = llama_model_default_params()
    mp.n_gpu_layers = 99; mp.use_mmap = true
    guard let model = llama_model_load_from_file(modelPath, mp) else {
        log("MT: model load FAILED"); return []
    }
    let vocab = llama_model_get_vocab(model)!

    var cp = llama_context_default_params()
    cp.n_ctx = 1024; cp.n_threads = 4; cp.n_threads_batch = 4
    guard let ctx = llama_init_from_model(model, cp) else {
        log("MT: ctx FAILED"); llama_model_free(model); return []
    }

    let smpl = llama_sampler_chain_init(llama_sampler_chain_default_params())!
    llama_sampler_chain_add(smpl, llama_sampler_init_penalties(64, 1.15, 0, 0))
    llama_sampler_chain_add(smpl, llama_sampler_init_temp(0.3))
    llama_sampler_chain_add(smpl, llama_sampler_init_top_k(20))
    llama_sampler_chain_add(smpl, llama_sampler_init_top_p(0.9, 1))
    llama_sampler_chain_add(smpl, llama_sampler_init_min_p(0.05, 1))
    llama_sampler_chain_add(smpl, llama_sampler_init_dist(UInt32.max))

    var results: [BenchmarkMultiTurnResult] = []

    // Test 1: Name recall
    results.append(runBenchmarkConversation(name: "Name Recall", turns: [
        (q: "My name is Alice. Nice to meet you!", check: nil),
        (q: "What is my name?", check: { $0.lowercased().contains("alice") }),
    ], ctx: ctx, model: model, vocab: vocab, smpl: smpl, log: log))
    onResult?(results.last!)

    // Test 2: Topic continuity
    results.append(runBenchmarkConversation(name: "Topic Continuity", turns: [
        (q: "Let's talk about cats. What makes them good pets?", check: nil),
        (q: "And what about their downsides?", check: { r in
            let l = r.lowercased()
            return l.contains("cat") || l.contains("pet") || l.contains("fur") || l.contains("litter") || l.contains("scratch")
        }),
    ], ctx: ctx, model: model, vocab: vocab, smpl: smpl, log: log))
    onResult?(results.last!)

    // Test 3: Number recall
    results.append(runBenchmarkConversation(name: "Number Recall", turns: [
        (q: "Remember this number: 42. I'll ask about it later.", check: nil),
        (q: "What was the number I told you to remember?", check: { $0.contains("42") }),
    ], ctx: ctx, model: model, vocab: vocab, smpl: smpl, log: log))
    onResult?(results.last!)

    // Test 4: Language switching
    results.append(runBenchmarkConversation(name: "Language Switch", turns: [
        (q: "\u{3053}\u{3093}\u{306B}\u{3061}\u{306F}\u{FF01}\u{65E5}\u{672C}\u{8A9E}\u{3067}\u{8A71}\u{3057}\u{307E}\u{3057}\u{3087}\u{3046}\u{3002}", check: nil),
        (q: "What is the capital of Japan? Answer in English.", check: { $0.lowercased().contains("tokyo") }),
    ], ctx: ctx, model: model, vocab: vocab, smpl: smpl, log: log))
    onResult?(results.last!)

    // Test 5: 3-turn chain
    results.append(runBenchmarkConversation(name: "3-Turn Chain", turns: [
        (q: "I have 3 apples.", check: nil),
        (q: "I buy 5 more apples.", check: nil),
        (q: "How many apples do I have now?", check: { $0.contains("8") }),
    ], ctx: ctx, model: model, vocab: vocab, smpl: smpl, log: log))
    onResult?(results.last!)

    // Test 6: Japanese recall
    results.append(runBenchmarkConversation(name: "Japanese Recall", turns: [
        (q: "\u{79C1}\u{306F}\u{6771}\u{4EAC}\u{306B}\u{4F4F}\u{3093}\u{3067}\u{3044}\u{307E}\u{3059}\u{3002}", check: nil),
        (q: "\u{79C1}\u{306F}\u{3069}\u{3053}\u{306B}\u{4F4F}\u{3093}\u{3067}\u{3044}\u{307E}\u{3059}\u{304B}\u{FF1F}", check: { $0.contains("\u{6771}\u{4EAC}") }),
    ], ctx: ctx, model: model, vocab: vocab, smpl: smpl, log: log))
    onResult?(results.last!)

    llama_sampler_free(smpl); llama_free(ctx); llama_model_free(model)

    let passed = results.filter(\.passed).count
    log("=== MULTI-TURN DONE: \(passed)/\(results.count) (\(Int(Float(passed)/Float(results.count)*100))%) ===")
    return results
}

// MARK: - Single conversation runner

private func runBenchmarkConversation(
    name: String,
    turns: [(q: String, check: ((String) -> Bool)?)],
    ctx: OpaquePointer,
    model: OpaquePointer,
    vocab: OpaquePointer,
    smpl: UnsafeMutablePointer<llama_sampler>,
    log: @escaping (String) -> Void
) -> BenchmarkMultiTurnResult {

    var history: [(role: String, content: String)] = []
    var allTurns: [(query: String, response: String)] = []
    var lastCheckResult = true
    var failReason = ""

    for (i, turn) in turns.enumerated() {
        var prompt = "<|im_start|>system\nYou are a helpful assistant. Answer concisely.<|im_end|>\n"
        for h in history {
            prompt += "<|im_start|>\(h.role)\n\(h.content)<|im_end|>\n"
        }
        prompt += "<|im_start|>user\n\(turn.q)<|im_end|>\n<|im_start|>assistant\n<think>\n</think>\n"

        if let mem = llama_get_memory(ctx) { llama_memory_clear(mem, true) }
        let response = benchmarkGenerateRaw(prompt: prompt, ctx: ctx, vocab: vocab, smpl: smpl, maxTokens: 200)

        var cleaned = response
        if let s = cleaned.range(of: "<think>"), let e = cleaned.range(of: "</think>") {
            cleaned = String(cleaned[e.upperBound...])
        }
        cleaned = cleaned.replacingOccurrences(of: "<|im_end|>", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        allTurns.append((query: turn.q, response: String(cleaned.prefix(200))))
        history.append((role: "user", content: turn.q))
        history.append((role: "assistant", content: String(cleaned.prefix(300))))

        log("MT[\(name)] turn\(i+1): Q='\(turn.q.prefix(30))' A='\(cleaned.prefix(60))'")

        if let check = turn.check {
            if !check(cleaned) {
                lastCheckResult = false
                failReason = "Turn \(i+1) check failed. Got: '\(cleaned.prefix(80))'"
            }
        }
    }

    let result = BenchmarkMultiTurnResult(testName: name, turns: allTurns, passed: lastCheckResult, reason: failReason)
    log("MT[\(name)]: \(lastCheckResult ? "PASS" : "FAIL: \(failReason.prefix(60))")")
    return result
}

private func benchmarkGenerateRaw(prompt: String, ctx: OpaquePointer, vocab: OpaquePointer, smpl: UnsafeMutablePointer<llama_sampler>, maxTokens: Int) -> String {
    let maxTok: Int32 = 1024
    let buf = UnsafeMutablePointer<llama_token>.allocate(capacity: Int(maxTok))
    defer { buf.deallocate() }

    let nTok = llama_tokenize(vocab, prompt, Int32(prompt.utf8.count), buf, maxTok, true, true)
    guard nTok > 0 else { return "" }

    var batch = llama_batch_init(nTok, 0, 1)
    for i in 0..<Int(nTok) {
        batch.token[i] = buf[i]; batch.pos[i] = Int32(i)
        batch.n_seq_id[i] = 1; batch.seq_id[i]![0] = 0; batch.logits[i] = 0
    }
    batch.logits[Int(nTok)-1] = 1; batch.n_tokens = nTok
    guard llama_decode(ctx, batch) == 0 else { llama_batch_free(batch); return "" }

    var output = ""
    var pos = nTok
    let pBuf = UnsafeMutablePointer<CChar>.allocate(capacity: 128)
    defer { pBuf.deallocate() }

    for _ in 0..<maxTokens {
        let tok = llama_sampler_sample(smpl, ctx, -1)
        if llama_vocab_is_eog(vocab, tok) { break }
        memset(pBuf, 0, 128)
        let pLen = llama_token_to_piece(vocab, tok, pBuf, 128, 0, true)
        if pLen > 0 { output += String(cString: pBuf) }
        batch.n_tokens = 0
        batch.token[0] = tok; batch.pos[0] = pos
        batch.n_seq_id[0] = 1; batch.seq_id[0]![0] = 0; batch.logits[0] = 1
        batch.n_tokens = 1; pos += 1
        if llama_decode(ctx, batch) != 0 { break }
    }
    llama_batch_free(batch)
    return output
}
