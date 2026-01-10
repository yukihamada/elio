import Foundation
import LlamaSwift

/// Inference acceleration mode
enum InferenceMode: String, CaseIterable, Codable {
    case auto = "auto"           // Automatic (GPU if available)
    case gpu = "gpu"             // Metal GPU acceleration
    case cpu = "cpu"             // CPU only (battery saving)
    case hybrid = "hybrid"       // Mixed CPU/GPU

    var displayName: String {
        switch self {
        case .auto: return String(localized: "inference.mode.auto")
        case .gpu: return String(localized: "inference.mode.gpu")
        case .cpu: return String(localized: "inference.mode.cpu")
        case .hybrid: return String(localized: "inference.mode.hybrid")
        }
    }

    var description: String {
        switch self {
        case .auto: return String(localized: "inference.mode.auto.desc")
        case .gpu: return String(localized: "inference.mode.gpu.desc")
        case .cpu: return String(localized: "inference.mode.cpu.desc")
        case .hybrid: return String(localized: "inference.mode.hybrid.desc")
        }
    }

    var icon: String {
        switch self {
        case .auto: return "sparkles"
        case .gpu: return "gpu"
        case .cpu: return "cpu"
        case .hybrid: return "arrow.triangle.branch"
        }
    }

    /// Number of GPU layers to use
    var gpuLayers: Int32 {
        switch self {
        case .auto, .gpu: return 999  // All layers on GPU
        case .cpu: return 0           // No GPU layers
        case .hybrid: return 20       // Some layers on GPU
        }
    }
}

/// GGUF model inference using llama.cpp via llama.swift
@MainActor
final class LlamaInference: ObservableObject {
    @Published private(set) var isLoaded = false
    @Published private(set) var isGenerating = false
    @Published private(set) var loadingProgress: Double = 0
    @Published private(set) var modelName: String = ""
    @Published var inferenceMode: InferenceMode = .auto

    private var model: OpaquePointer?
    private var context: OpaquePointer?
    private var modelPath: URL?

    // Model configuration
    struct Config: Sendable {
        let name: String
        let contextSize: UInt32
        let eosTokenId: Int32
        let bosTokenId: Int32

        static let qwen3 = Config(
            name: "Qwen3",
            contextSize: 4096,
            eosTokenId: 151645,
            bosTokenId: 151643
        )

        static let llama3 = Config(
            name: "Llama3",
            contextSize: 4096,
            eosTokenId: 128001,
            bosTokenId: 128000
        )

        static let deepseekR1Qwen = Config(
            name: "DeepSeek-R1-Qwen",
            contextSize: 4096,  // Reduced from 32768 for iPhone memory constraints
            eosTokenId: 151645,
            bosTokenId: 151643
        )

        static let deepseekR1Llama = Config(
            name: "DeepSeek-R1-Llama",
            contextSize: 4096,
            eosTokenId: 128001,
            bosTokenId: 128000
        )
    }

    private var config: Config

    init(config: Config = .qwen3) {
        self.config = config
        // Disable Metal concurrency to avoid crash on A18 Pro
        // See: https://github.com/ggml-org/llama.cpp/pull/14849
        setenv("GGML_METAL_NO_CONCURRENCY", "1", 1)
        // Initialize llama backend
        llama_backend_init()
    }

    deinit {
        // Capture pointers before creating task
        let ctx = context
        let mdl = model

        // Clean up synchronously since we have the pointers
        if let ctx = ctx {
            llama_free(ctx)
        }
        if let mdl = mdl {
            llama_model_free(mdl)
        }
        llama_backend_free()
    }

    private func cleanup() {
        if let ctx = context {
            llama_free(ctx)
            context = nil
        }
        if let mdl = model {
            llama_model_free(mdl)
            model = nil
        }
    }

    func loadModel(from url: URL) async throws {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw LlamaError.modelNotFound
        }

        // Unload any existing model first to free GPU memory
        if isLoaded {
            cleanup()
            isLoaded = false
        }

        self.modelPath = url
        self.modelName = url.deletingPathExtension().lastPathComponent

        loadingProgress = 0.1

        // Model parameters - configure based on inference mode
        var modelParams = llama_model_default_params()
        // Set GPU layers based on inference mode
        modelParams.n_gpu_layers = inferenceMode.gpuLayers

        // Load model
        guard let loadedModel = llama_model_load_from_file(url.path, modelParams) else {
            throw LlamaError.modelNotFound
        }

        // Context parameters - optimized for speed
        var contextParams = llama_context_default_params()
        contextParams.n_ctx = config.contextSize
        contextParams.n_batch = 2048  // Increased batch size for faster prompt processing
        contextParams.n_ubatch = 512  // Micro-batch for better memory efficiency
        // Use performance cores for speed
        let perfCores = max(4, ProcessInfo.processInfo.activeProcessorCount - 2)
        contextParams.n_threads = Int32(perfCores)
        contextParams.n_threads_batch = Int32(perfCores)

        // Create context
        guard let loadedContext = llama_init_from_model(loadedModel, contextParams) else {
            llama_model_free(loadedModel)
            throw LlamaError.contextCreationFailed
        }

        self.model = loadedModel
        self.context = loadedContext
        self.loadingProgress = 1.0
        self.isLoaded = true
    }

    func generate(
        prompt: String,
        maxTokens: Int = 512,
        temperature: Float = 0.7,
        topP: Float = 0.9,
        stopSequences: [String] = [],
        onToken: @escaping @MainActor (String) -> Void
    ) async throws -> String {
        guard isLoaded, let model = model, let context = context else {
            throw LlamaError.modelNotLoaded
        }

        isGenerating = true
        defer { isGenerating = false }

        let currentConfig = config

        // Get vocab
        guard let vocab = llama_model_get_vocab(model) else {
            throw LlamaError.tokenizationFailed
        }

        // Tokenize the prompt
        var promptTokens = tokenize(prompt, vocab: vocab, addSpecial: true)

        guard !promptTokens.isEmpty else {
            throw LlamaError.tokenizationFailed
        }

        // Clear memory
        let memory = llama_get_memory(context)
        llama_memory_clear(memory, true)

        // Process prompt - copy count before closure to avoid overlapping access
        let tokenCount = Int32(promptTokens.count)
        let decodeResult: Int32 = promptTokens.withUnsafeMutableBufferPointer { bufferPtr in
            let batch = llama_batch_get_one(bufferPtr.baseAddress!, tokenCount)
            return llama_decode(context, batch)
        }

        if decodeResult != 0 {
            throw LlamaError.generationFailed("Failed to process prompt: \(decodeResult)")
        }

        // Create sampler chain - optimized for speed
        let samplerParams = llama_sampler_chain_default_params()
        guard let sampler = llama_sampler_chain_init(samplerParams) else {
            throw LlamaError.generationFailed("Failed to create sampler chain")
        }
        defer { llama_sampler_free(sampler) }

        // Faster sampling: smaller top_k and use greedy for low temperatures
        if temperature < 0.1 {
            // Greedy decoding - fastest
            llama_sampler_chain_add(sampler, llama_sampler_init_greedy())
        } else {
            // Add samplers to chain - optimized order and values
            llama_sampler_chain_add(sampler, llama_sampler_init_top_k(20))  // Reduced from 40
            llama_sampler_chain_add(sampler, llama_sampler_init_top_p(topP, 1))
            llama_sampler_chain_add(sampler, llama_sampler_init_temp(temperature))
            llama_sampler_chain_add(sampler, llama_sampler_init_dist(UInt32.random(in: 0..<UInt32.max)))
        }

        // Pre-allocate buffer for generated text
        var generatedText = ""
        generatedText.reserveCapacity(maxTokens * 4)  // Estimate ~4 chars per token

        // Reusable token buffer for decode
        var nextTokenArray: [llama_token] = [0]

        // UTF-8 byte buffer for handling incomplete sequences
        var pendingBytes: [UInt8] = []

        // Generate tokens
        for tokenIndex in 0..<maxTokens {
            // Check for cancellation
            try Task.checkCancellation()

            // Sample next token using the sampler chain
            let newToken = llama_sampler_sample(sampler, context, -1)

            // Check for EOS
            if llama_vocab_is_eog(vocab, newToken) || newToken == currentConfig.eosTokenId {
                break
            }

            // Convert token to bytes and accumulate
            let tokenBytes = tokenToBytes(newToken, vocab: vocab)
            pendingBytes.append(contentsOf: tokenBytes)

            // Try to convert accumulated bytes to string
            let (validText, remaining) = bytesToString(pendingBytes)
            pendingBytes = remaining

            if !validText.isEmpty {
                generatedText += validText
                // Call callback with valid UTF-8 text
                onToken(validText)
            }

            // Check stop sequences only if we have any
            if !stopSequences.isEmpty {
                for stopSeq in stopSequences {
                    if generatedText.hasSuffix(stopSeq) {
                        return generatedText
                    }
                }
            }

            // Decode next token - reuse array
            nextTokenArray[0] = newToken
            let result: Int32 = nextTokenArray.withUnsafeMutableBufferPointer { bufferPtr in
                let batch = llama_batch_get_one(bufferPtr.baseAddress!, 1)
                return llama_decode(context, batch)
            }

            if result != 0 {
                break
            }

            // Yield to allow UI updates every few tokens
            if tokenIndex % 4 == 0 {
                await Task.yield()
            }
        }

        // Flush any remaining bytes at the end
        if !pendingBytes.isEmpty {
            if let finalText = String(bytes: pendingBytes, encoding: .utf8), !finalText.isEmpty {
                generatedText += finalText
                onToken(finalText)
            }
        }

        return generatedText
    }

    private func tokenize(_ text: String, vocab: OpaquePointer, addSpecial: Bool) -> [llama_token] {
        let maxTokens = Int32(text.utf8.count) + 32

        var tokens = [llama_token](repeating: 0, count: Int(maxTokens))
        let nTokens = llama_tokenize(vocab, text, Int32(text.utf8.count), &tokens, maxTokens, addSpecial, true)

        if nTokens < 0 {
            return []
        }

        return Array(tokens.prefix(Int(nTokens)))
    }

    private func tokenToBytes(_ token: llama_token, vocab: OpaquePointer) -> [UInt8] {
        var buffer = [CChar](repeating: 0, count: 256)
        let length = llama_token_to_piece(vocab, token, &buffer, Int32(buffer.count), 0, true)

        if length > 0 {
            return buffer.prefix(Int(length)).map { UInt8(bitPattern: $0) }
        }
        return []
    }

    /// Converts bytes to string, handling incomplete UTF-8 sequences
    /// Returns (validString, remainingBytes) - remaining bytes are incomplete UTF-8 that need more data
    private func bytesToString(_ bytes: [UInt8]) -> (String, [UInt8]) {
        guard !bytes.isEmpty else { return ("", []) }

        // Find the last valid UTF-8 boundary
        var validEnd = bytes.count

        // Check if we're in the middle of a multi-byte sequence
        // UTF-8 continuation bytes start with 10xxxxxx (0x80-0xBF)
        // Start bytes: 0xxxxxxx (ASCII), 110xxxxx (2-byte), 1110xxxx (3-byte), 11110xxx (4-byte)
        for i in stride(from: bytes.count - 1, through: max(0, bytes.count - 4), by: -1) {
            let byte = bytes[i]

            if byte & 0x80 == 0 {
                // ASCII byte - valid boundary after this
                break
            } else if byte & 0xC0 == 0xC0 {
                // This is a start byte (110..., 1110..., or 11110...)
                let expectedLength: Int
                if byte & 0xF8 == 0xF0 {
                    expectedLength = 4
                } else if byte & 0xF0 == 0xE0 {
                    expectedLength = 3
                } else if byte & 0xE0 == 0xC0 {
                    expectedLength = 2
                } else {
                    expectedLength = 1
                }

                let availableBytes = bytes.count - i
                if availableBytes < expectedLength {
                    // Incomplete sequence - cut before this start byte
                    validEnd = i
                }
                break
            }
            // Continue checking - this is a continuation byte
        }

        let validBytes = Array(bytes.prefix(validEnd))
        let remainingBytes = Array(bytes.suffix(from: validEnd))

        if let str = String(bytes: validBytes, encoding: .utf8) {
            return (str, remainingBytes)
        }

        // If UTF-8 decoding fails, try to salvage what we can
        // Replace invalid sequences with empty string
        return ("", remainingBytes)
    }

    func formatChatPrompt(messages: [Message], systemPrompt: String, enableThinking: Bool = true) -> String {
        var prompt = ""
        let modelName = config.name.lowercased()

        if modelName.contains("deepseek") && modelName.contains("qwen") {
            // DeepSeek-R1 Distill (Qwen-based) format
            prompt = "<|im_start|>system\n\(systemPrompt)<|im_end|>\n"
            for message in messages {
                let role = message.role == .user ? "user" : "assistant"
                prompt += "<|im_start|>\(role)\n\(message.content)<|im_end|>\n"
            }
            prompt += "<|im_start|>assistant\n<think>\n"
        } else if modelName.contains("deepseek") && modelName.contains("llama") {
            // DeepSeek-R1 Distill (Llama-based) format
            prompt = "<|begin_of_text|><|start_header_id|>system<|end_header_id|>\n\n\(systemPrompt)<|eot_id|>"
            for message in messages {
                let role = message.role == .user ? "user" : "assistant"
                prompt += "<|start_header_id|>\(role)<|end_header_id|>\n\n\(message.content)<|eot_id|>"
            }
            prompt += "<|start_header_id|>assistant<|end_header_id|>\n\n<think>\n"
        } else if modelName.contains("qwen") {
            // Qwen3 with thinking mode support
            prompt = "<|im_start|>system\n\(systemPrompt)<|im_end|>\n"
            for message in messages {
                let role = message.role == .user ? "user" : "assistant"
                prompt += "<|im_start|>\(role)\n\(message.content)<|im_end|>\n"
            }
            // Enable thinking mode for Qwen3 by starting with <think>
            if enableThinking {
                prompt += "<|im_start|>assistant\n<think>\n"
            } else {
                prompt += "<|im_start|>assistant\n"
            }
        } else if modelName.contains("llama") {
            prompt = "<|begin_of_text|><|start_header_id|>system<|end_header_id|>\n\n\(systemPrompt)<|eot_id|>"
            for message in messages {
                let role = message.role == .user ? "user" : "assistant"
                prompt += "<|start_header_id|>\(role)<|end_header_id|>\n\n\(message.content)<|eot_id|>"
            }
            prompt += "<|start_header_id|>assistant<|end_header_id|>\n\n"
        } else {
            prompt = "<|im_start|>system\n\(systemPrompt)<|im_end|>\n"
            for message in messages {
                let role = message.role == .user ? "user" : "assistant"
                prompt += "<|im_start|>\(role)\n\(message.content)<|im_end|>\n"
            }
            // Default to thinking mode for unknown models
            if enableThinking {
                prompt += "<|im_start|>assistant\n<think>\n"
            } else {
                prompt += "<|im_start|>assistant\n"
            }
        }

        return prompt
    }

    func unload() {
        cleanup()
        isLoaded = false
        loadingProgress = 0
        modelName = ""
    }
}

enum LlamaError: Error, LocalizedError {
    case modelNotFound
    case modelNotLoaded
    case contextCreationFailed
    case tokenizationFailed
    case generationFailed(String)

    var errorDescription: String? {
        switch self {
        case .modelNotFound: return String(localized: "error.model.not.found")
        case .modelNotLoaded: return String(localized: "error.model.not.loaded")
        case .contextCreationFailed: return String(localized: "error.context.failed")
        case .tokenizationFailed: return String(localized: "error.tokenization.failed")
        case .generationFailed(let msg): return String(localized: "error.generation.failed") + ": \(msg)"
        }
    }
}
