import Foundation
import LlamaSwift

/// Direct llama.cpp engine using raw C API for maximum reliability.
/// Ported from NOU app's DirectEngine - bypasses wrapper code that can cause garbled output.
/// Features: KV cache preservation, repeat penalty, min_p sampling, thinking suppression.
@MainActor
final class DirectLlamaEngine: ObservableObject {
    private var model: OpaquePointer?
    private var ctx: OpaquePointer?
    private var vocab: OpaquePointer?
    private var batch: llama_batch?
    private var smpl: UnsafeMutablePointer<llama_sampler>?
    private var curPos: Int32 = 0

    @Published private(set) var isLoaded = false
    @Published private(set) var isGenerating = false

    // KV Cache preservation: track tokens already in cache
    private var cachedTokens: [llama_token] = []
    private var cacheValid: Bool = false

    // Conversation history for multi-turn with summarization
    private var history: [(role: String, content: String)] = []
    private let maxHistoryTurns = 3
    private var conversationSummary: String? = nil

    // Model identification
    private var modelPath: URL?
    private var isQwen: Bool = true

    /// Background queue for inference
    private static let inferenceQueue = DispatchQueue(label: "love.elio.app.direct.inference", qos: .userInitiated)

    /// Set to true from any thread to abort the current inference loop.
    nonisolated(unsafe) static var abortFlag = false

    init() {
        llama_backend_init()
        // Metal stability settings
        setenv("GGML_METAL_NO_CONCURRENCY", "1", 1)
        setenv("GGML_METAL_FULL_THREADS", "0", 1)
        setenv("GGML_METAL_NO_RESIDENCY", "1", 1)
        setenv("GGML_METAL_PATH_RESOURCES", Bundle.main.bundlePath, 1)
    }

    deinit {
        if let s = smpl { llama_sampler_free(s) }
        if var b = batch { llama_batch_free(b) }
        if let c = ctx { llama_free(c) }
        if let m = model { llama_model_free(m) }
        llama_backend_free()
    }

    private func cleanup() {
        if let s = smpl { llama_sampler_free(s); smpl = nil }
        if var b = batch { llama_batch_free(b); batch = nil }
        if let c = ctx { llama_free(c); ctx = nil }
        if let m = model { llama_model_free(m); model = nil }
        vocab = nil
    }

    // MARK: - Model Loading

    func loadModel(from url: URL, nGPULayers: Int32 = 99, contextSize: UInt32 = 0) async throws {
        if isLoaded { cleanup(); isLoaded = false }

        let nameLower = url.lastPathComponent.lowercased()
        self.isQwen = !nameLower.contains("llama")
        self.modelPath = url

        // Determine context size based on device
        let effectiveContextSize: UInt32 = contextSize > 0 ? contextSize : {
            let memGB = Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824
            switch memGB {
            case 8...: return 8192
            case 6..<8: return 6144
            case 4..<6: return 4096
            default: return 2048
            }
        }()

        let modelUrl = url
        let gpuLayers = nGPULayers

        let result = try await Task.detached(priority: .userInitiated) { () -> (OpaquePointer, OpaquePointer, OpaquePointer, llama_batch, UnsafeMutablePointer<llama_sampler>) in
            var mp = llama_model_default_params()
            mp.n_gpu_layers = gpuLayers
            mp.use_mmap = true

            guard let m = llama_model_load_from_file(modelUrl.path, mp) else {
                throw LlamaError.modelNotFound
            }

            let v = llama_model_get_vocab(m)!

            var cp = llama_context_default_params()
            let trainCtx = llama_model_n_ctx_train(m)
            if trainCtx > 0 {
                cp.n_ctx = min(effectiveContextSize, UInt32(trainCtx))
            } else {
                cp.n_ctx = effectiveContextSize
            }
            cp.n_ctx = max(cp.n_ctx, 2048)

            let perfCores = max(4, ProcessInfo.processInfo.activeProcessorCount)
            cp.n_threads = Int32(perfCores)
            cp.n_threads_batch = Int32(perfCores)
            cp.n_batch = cp.n_ctx
            cp.n_ubatch = min(1024, cp.n_ctx)
            // KV cache quantization
            cp.type_k = GGML_TYPE_Q8_0
            cp.type_v = GGML_TYPE_Q8_0
            // Flash Attention
            cp.flash_attn_type = LLAMA_FLASH_ATTN_TYPE_ENABLED
            cp.offload_kqv = true

            guard let c = llama_init_from_model(m, cp) else {
                llama_model_free(m)
                throw LlamaError.contextCreationFailed
            }

            let b = llama_batch_init(512, 0, 1)

            // Sampler chain - tuned for small models (from NOU)
            let s = llama_sampler_chain_init(llama_sampler_chain_default_params())!
            llama_sampler_chain_add(s, llama_sampler_init_penalties(64, 1.15, 0.0, 0.0))
            llama_sampler_chain_add(s, llama_sampler_init_temp(0.7))
            llama_sampler_chain_add(s, llama_sampler_init_top_k(40))
            llama_sampler_chain_add(s, llama_sampler_init_top_p(0.9, 1))
            llama_sampler_chain_add(s, llama_sampler_init_min_p(0.05, 1))
            llama_sampler_chain_add(s, llama_sampler_init_dist(UInt32.max))

            return (m, c, v, b, s)
        }.value

        self.model = result.0
        self.ctx = result.1
        self.vocab = result.2
        self.batch = result.3
        self.smpl = result.4
        self.isLoaded = true

        print("[DirectLlamaEngine] Loaded: \(url.lastPathComponent), ctx=\(llama_n_ctx(result.1))")
    }

    // MARK: - KV Cache

    /// Invalidate KV cache (call when context changes incompatibly)
    func invalidateCache() {
        cacheValid = false
        cachedTokens = []
    }

    /// Clear conversation history and cache
    func clearHistory() {
        history = []
        conversationSummary = nil
        invalidateCache()
    }

    // MARK: - Generate (raw C API with KV cache preservation)

    /// Generate response for a prompt, reusing KV cache when possible.
    /// Runs inference on background queue to keep UI responsive.
    func generate(
        prompt: String,
        maxTokens: Int = 1024,
        onToken: @escaping @MainActor (String) -> Void
    ) async throws -> String {
        guard isLoaded, let model = model, let ctx = ctx, let vocab = vocab,
              var batch = batch, let smpl = smpl else {
            throw LlamaError.modelNotLoaded
        }

        Self.abortFlag = false
        isGenerating = true
        defer { isGenerating = false }

        // Capture values for background
        let capturedCtx = ctx
        let capturedVocab = vocab
        let capturedSmpl = smpl
        let capturedCachedTokens = cachedTokens
        let capturedCacheValid = cacheValid

        let result: (text: String, newCachedTokens: [llama_token]) = try await withCheckedThrowingContinuation { continuation in
            Self.inferenceQueue.async {
                do {
                    let output = try Self.generateOnBackground(
                        prompt: prompt,
                        maxTokens: maxTokens,
                        ctx: capturedCtx,
                        vocab: capturedVocab,
                        batch: &batch,
                        smpl: capturedSmpl,
                        cachedTokens: capturedCachedTokens,
                        cacheValid: capturedCacheValid,
                        onToken: onToken
                    )
                    continuation.resume(returning: output)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }

        // Update cache state on main actor
        self.batch = batch
        self.cachedTokens = result.newCachedTokens
        self.cacheValid = true

        return result.text
    }

    /// Core inference loop on background thread.
    /// Port of DirectEngine.generate() from NOU with KV cache preservation.
    private static func generateOnBackground(
        prompt: String,
        maxTokens: Int,
        ctx: OpaquePointer,
        vocab: OpaquePointer,
        batch: inout llama_batch,
        smpl: UnsafeMutablePointer<llama_sampler>,
        cachedTokens: [llama_token],
        cacheValid: Bool,
        onToken: @escaping @MainActor (String) -> Void
    ) throws -> (text: String, newCachedTokens: [llama_token]) {
        // Tokenize
        let ctxSize = Int32(llama_n_ctx(ctx))
        let outputReserve: Int32 = 512
        let maxPromptTokens = max(256, ctxSize - outputReserve)
        let tokenBuf = UnsafeMutablePointer<llama_token>.allocate(capacity: Int(maxPromptTokens))
        defer { tokenBuf.deallocate() }

        var nTok = llama_tokenize(vocab, prompt, Int32(prompt.utf8.count), tokenBuf, maxPromptTokens, true, true)
        guard nTok > 0 else { return ("", []) }
        if nTok > maxPromptTokens { nTok = maxPromptTokens }

        let newTokens = Array(UnsafeBufferPointer(start: tokenBuf, count: Int(nTok)))

        // Find how many tokens match the cached prefix
        var matchLen = 0
        if cacheValid {
            let maxMatch = min(cachedTokens.count, newTokens.count)
            for i in 0..<maxMatch {
                if cachedTokens[i] == newTokens[i] {
                    matchLen += 1
                } else {
                    break
                }
            }
        }

        var curPos: Int32 = 0

        if matchLen > 0 && matchLen == cachedTokens.count {
            // Cache is a prefix of new tokens -- only need to encode the delta
            let deltaStart = matchLen
            let deltaCount = Int(nTok) - deltaStart
            curPos = Int32(matchLen)

            if deltaCount > 0 {
                batch.n_tokens = 0
                for i in 0..<deltaCount {
                    batch.token[i] = newTokens[deltaStart + i]
                    batch.pos[i] = Int32(deltaStart + i)
                    batch.n_seq_id[i] = 1
                    batch.seq_id[i]![0] = 0
                    batch.logits[i] = 0
                }
                batch.logits[deltaCount - 1] = 1
                batch.n_tokens = Int32(deltaCount)

                guard llama_decode(ctx, batch) == 0 else {
                    throw LlamaError.generationFailed("decode delta failed")
                }
                curPos = nTok
            }
        } else {
            // Cache miss - clear and re-encode everything
            if let mem = llama_get_memory(ctx) {
                llama_memory_clear(mem, true)
            }
            curPos = 0

            // Process in chunks for large prompts
            let chunkSize = 512
            var processed = 0
            while processed < Int(nTok) {
                let remaining = Int(nTok) - processed
                let thisChunk = min(chunkSize, remaining)

                batch.n_tokens = 0
                for i in 0..<thisChunk {
                    batch.token[i] = newTokens[processed + i]
                    batch.pos[i] = Int32(processed + i)
                    batch.n_seq_id[i] = 1
                    batch.seq_id[i]![0] = 0
                    batch.logits[i] = 0
                }
                // Only need logits for last token of last chunk
                if processed + thisChunk == Int(nTok) {
                    batch.logits[thisChunk - 1] = 1
                }
                batch.n_tokens = Int32(thisChunk)

                guard llama_decode(ctx, batch) == 0 else {
                    throw LlamaError.generationFailed("decode prompt chunk failed")
                }
                processed += thisChunk
            }
            curPos = nTok
        }

        // Track cached tokens
        var updatedCachedTokens = newTokens

        // Generate tokens
        var output = ""
        output.reserveCapacity(maxTokens * 4)
        let pBuf = UnsafeMutablePointer<CChar>.allocate(capacity: 256)
        defer { pBuf.deallocate() }

        var pendingUIText = ""
        var tokensSinceDispatch = 0
        let dispatchInterval = 4

        for _ in 0..<maxTokens {
            if tokensSinceDispatch % 8 == 0 && DirectLlamaEngine.abortFlag { break }

            let tok = llama_sampler_sample(smpl, ctx, -1)
            if llama_vocab_is_eog(vocab, tok) { break }

            memset(pBuf, 0, 256)
            let pLen = llama_token_to_piece(vocab, tok, pBuf, 256, 0, true)
            if pLen > 0 {
                let piece = String(cString: pBuf)
                output += piece
                pendingUIText += piece
                tokensSinceDispatch += 1

                if tokensSinceDispatch >= dispatchInterval || piece.contains("\n") {
                    let text = pendingUIText
                    pendingUIText = ""
                    tokensSinceDispatch = 0
                    Task { @MainActor in
                        onToken(text)
                    }
                }
            }

            // Next step
            batch.n_tokens = 0
            batch.token[0] = tok
            batch.pos[0] = curPos
            batch.n_seq_id[0] = 1
            batch.seq_id[0]![0] = 0
            batch.logits[0] = 1
            batch.n_tokens = 1
            curPos += 1

            if llama_decode(ctx, batch) != 0 { break }

            // Track generated tokens in cache for next turn reuse
            updatedCachedTokens.append(tok)
        }

        // Flush remaining UI text
        if !pendingUIText.isEmpty {
            let text = pendingUIText
            Task { @MainActor in
                onToken(text)
            }
        }

        return (output, updatedCachedTokens)
    }

    // MARK: - Chat Generation (with history, summarization, thinking suppression)

    /// Generate response for a chat message with multi-turn history and KV cache.
    func chat(
        message: String,
        systemPrompt: String = "You are a helpful assistant.",
        maxTokens: Int = 1024,
        onToken: @escaping @MainActor (String) -> Void
    ) async throws -> String {
        // Summarize older turns if history exceeds threshold
        if history.count > maxHistoryTurns * 2 {
            await summarizeOlderTurns()
        }

        // Build prompt with conversation history
        let summaryContext = conversationSummary.map { "[Prior context: \($0)]" } ?? ""
        let systemWithSummary = summaryContext.isEmpty ? systemPrompt : "\(systemPrompt)\n\(summaryContext)"

        let formatted = formatChatPrompt(
            messages: history,
            userMessage: message,
            systemPrompt: systemWithSummary,
            suppressThinking: true
        )

        // Generate with thinking suppression
        var rawResult = ""
        let output = try await generate(prompt: formatted, maxTokens: maxTokens) { token in
            rawResult += token
        }

        let cleaned = stripThinking(output)

        // Stream cleaned tokens to callback (re-emit without thinking tags)
        if !cleaned.isEmpty {
            await onToken(cleaned)
        }

        // Save to history
        history.append((role: "user", content: message))
        history.append((role: "assistant", content: String(cleaned.prefix(500))))
        if history.count > maxHistoryTurns * 2 {
            history = Array(history.suffix(maxHistoryTurns * 2))
        }

        return cleaned
    }

    // MARK: - Tool Selection (lightweight completion for ToolRouter)

    /// Fast completion for tool selection - no history, no thinking.
    func complete(prompt: String, system: String) async throws -> String {
        let formatted = formatChatPrompt(
            messages: [],
            userMessage: prompt,
            systemPrompt: system,
            suppressThinking: true
        )
        let raw = try await generate(prompt: formatted, maxTokens: 64) { _ in }
        return stripThinking(raw)
    }

    // MARK: - Conversation Summarization

    private func summarizeOlderTurns() async {
        let olderTurns = Array(history.prefix(history.count - maxHistoryTurns * 2))
        guard !olderTurns.isEmpty else { return }

        let turnsText = olderTurns.map { "\($0.role): \($0.content)" }
            .joined(separator: "\n")
        let truncated = String(turnsText.prefix(600))

        let summaryPrompt = formatChatPrompt(
            messages: [],
            userMessage: truncated,
            systemPrompt: "Summarize this conversation in 2 sentences. Be very brief.",
            suppressThinking: true
        )

        print("[DirectLlamaEngine] Summarizing \(olderTurns.count) older turns")
        let summary = try? await generate(prompt: summaryPrompt, maxTokens: 128) { _ in }
        let cleaned = stripThinking(summary ?? "")

        if !cleaned.isEmpty {
            conversationSummary = String(cleaned.prefix(200))
            history = Array(history.suffix(maxHistoryTurns * 2))
            print("[DirectLlamaEngine] Summary: '\(conversationSummary?.prefix(80) ?? "")'")
        }
    }

    // MARK: - Prompt Formatting

    private func formatChatPrompt(
        messages: [(role: String, content: String)],
        userMessage: String,
        systemPrompt: String,
        suppressThinking: Bool
    ) -> String {
        if isQwen {
            var prompt = "<|im_start|>system\n\(systemPrompt)<|im_end|>\n"
            for turn in messages {
                prompt += "<|im_start|>\(turn.role)\n\(turn.content)<|im_end|>\n"
            }
            prompt += "<|im_start|>user\n\(userMessage)<|im_end|>\n"
            if suppressThinking {
                prompt += "<|im_start|>assistant\n<think>\n</think>\n"
            } else {
                prompt += "<|im_start|>assistant\n"
            }
            return prompt
        } else {
            var prompt = "<|begin_of_text|><|start_header_id|>system<|end_header_id|>\n\n\(systemPrompt)<|eot_id|>"
            for turn in messages {
                let role = turn.role == "user" ? "user" : "assistant"
                prompt += "<|start_header_id|>\(role)<|end_header_id|>\n\n\(turn.content)<|eot_id|>"
            }
            prompt += "<|start_header_id|>user<|end_header_id|>\n\n\(userMessage)<|eot_id|><|start_header_id|>assistant<|end_header_id|>\n\n"
            return prompt
        }
    }

    private func stripThinking(_ text: String) -> String {
        var result = text
        while let s = result.range(of: "<think>"), let e = result.range(of: "</think>") {
            result = String(result[result.startIndex..<s.lowerBound]) + String(result[e.upperBound...])
        }
        result = result.replacingOccurrences(of: "<think>", with: "")
        result = result.replacingOccurrences(of: "</think>", with: "")
        result = result.replacingOccurrences(of: "<|im_end|>", with: "")
        result = result.replacingOccurrences(of: "<|im_start|>", with: "")
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Unload

    func unload() {
        cleanup()
        isLoaded = false
        cachedTokens = []
        cacheValid = false
        history = []
        conversationSummary = nil
    }
}
