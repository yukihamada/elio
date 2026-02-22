import Foundation
import LlamaSwift

/// Wrapper to safely pass OpaquePointer across actor boundaries
/// OpaquePointer is thread-safe for llama.cpp operations
private struct SendablePointer: @unchecked Sendable {
    let model: OpaquePointer
    let context: OpaquePointer
}

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

    /// Number of GPU layers to use (device-aware)
    var gpuLayers: Int32 {
        switch self {
        case .auto, .gpu:
            // Device-aware GPU layer allocation based on available memory (cached)
            return Self.cachedOptimalGPULayers
        case .cpu: return 0           // No GPU layers
        case .hybrid: return 20       // Some layers on GPU
        }
    }

    /// Cached GPU layers calculation (computed once at startup)
    /// Aggressive values for maximum speed - offload all layers to GPU when possible
    private static let cachedOptimalGPULayers: Int32 = {
        let physicalMemory = ProcessInfo.processInfo.physicalMemory
        let memoryGB = Double(physicalMemory) / 1_073_741_824

        // Aggressive GPU layer allocation for maximum inference speed
        // Most models have 28-32 layers; offload all to GPU for best performance
        switch memoryGB {
        case 8...:   return 99   // 8GB+ (Pro models) - offload ALL layers to GPU
        case 6..<8:  return 40   // 6GB - most layers on GPU
        case 4..<6:  return 28   // 4GB - majority on GPU
        default:     return 16   // <4GB - balanced
        }
    }()
}

/// GGUF model inference using llama.cpp via llama.swift
@MainActor
final class LlamaInference: ObservableObject {
    @Published private(set) var isLoaded = false
    @Published private(set) var isGenerating = false
    @Published private(set) var loadingProgress: Double = 0
    @Published private(set) var modelName: String = ""
    @Published var inferenceMode: InferenceMode = .auto

    /// Current KV cache quantization settings
    private(set) var kvCacheTypeK: KVCacheQuantType = .q8_0
    private(set) var kvCacheTypeV: KVCacheQuantType = .q8_0

    private var model: OpaquePointer?
    private var context: OpaquePointer?
    private var modelPath: URL?

    // Reusable buffer for token-to-bytes conversion (avoids allocation per token)
    private var tokenBuffer = [CChar](repeating: 0, count: 256)

    // Model configuration
    struct Config: Sendable {
        let name: String
        let contextSize: UInt32
        let eosTokenId: Int32
        let bosTokenId: Int32

        // Dynamic context size based on device tier
        // Note: Minimum 6144 required for system prompt + tools description (~3000 tokens)
        private static var deviceContextSize: UInt32 {
            switch DeviceTier.current {
            case .ultra:
                return 8192   // 8GB+ RAM devices can handle larger context
            case .high:
                return 8192   // 8GB RAM devices
            case .medium:
                return 6144   // 6GB RAM devices
            case .low:
                return 6144   // 4GB RAM devices - need enough for system prompt
            }
        }

        static var qwen3: Config {
            Config(
                name: "Qwen3",
                contextSize: deviceContextSize,
                eosTokenId: 151645,
                bosTokenId: 151643
            )
        }

        static var llama3: Config {
            Config(
                name: "Llama3",
                contextSize: deviceContextSize,
                eosTokenId: 128001,
                bosTokenId: 128000
            )
        }

        static var deepseekR1Qwen: Config {
            Config(
                name: "DeepSeek-R1-Qwen",
                contextSize: deviceContextSize,
                eosTokenId: 151645,
                bosTokenId: 151643
            )
        }

        static var deepseekR1Llama: Config {
            Config(
                name: "DeepSeek-R1-Llama",
                contextSize: deviceContextSize,
                eosTokenId: 128001,
                bosTokenId: 128000
            )
        }

        static var nemotron: Config {
            Config(
                name: "Nemotron",
                contextSize: deviceContextSize,
                eosTokenId: 2,
                bosTokenId: 1
            )
        }
    }

    private var config: Config

    init(config: Config = .qwen3) {
        self.config = config
        // Disable Metal concurrency to avoid crash on A18 Pro
        // See: https://github.com/ggml-org/llama.cpp/pull/14849
        setenv("GGML_METAL_NO_CONCURRENCY", "1", 1)
        // Additional Metal stability settings for A18 Pro
        setenv("GGML_METAL_FULL_THREADS", "0", 1)
        // Set Metal resource path for optimized kernel loading
        setenv("GGML_METAL_PATH_RESOURCES", Bundle.main.bundlePath, 1)
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

    /// Convert KVCacheQuantType to ggml_type
    private func toGGMLType(_ kvType: KVCacheQuantType) -> ggml_type {
        switch kvType {
        case .q8_0: return GGML_TYPE_Q8_0
        case .q4_0: return GGML_TYPE_Q4_0
        case .f16: return GGML_TYPE_F16
        }
    }

    func loadModel(
        from url: URL,
        kvCacheTypeK: KVCacheQuantType = .q8_0,
        kvCacheTypeV: KVCacheQuantType = .q8_0
    ) async throws {
        print("[LlamaInference] loadModel called for: \(url.lastPathComponent)")
        print("[LlamaInference] KV Cache - type_k: \(kvCacheTypeK.rawValue), type_v: \(kvCacheTypeV.rawValue)")

        // Store KV cache settings
        self.kvCacheTypeK = kvCacheTypeK
        self.kvCacheTypeV = kvCacheTypeV

        guard FileManager.default.fileExists(atPath: url.path) else {
            print("[LlamaInference] ERROR: Model file not found at \(url.path)")
            throw LlamaError.modelNotFound
        }

        // Check file size
        if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
           let size = attrs[.size] as? Int64 {
            print("[LlamaInference] Model file size: \(size / 1_000_000) MB")
        }

        // Unload any existing model first to free GPU memory
        if isLoaded {
            print("[LlamaInference] Unloading existing model...")
            cleanup()
            isLoaded = false
        }

        self.modelPath = url
        self.modelName = url.deletingPathExtension().lastPathComponent

        loadingProgress = 0.1
        print("[LlamaInference] Starting model load...")

        // Capture values needed for background thread
        let gpuLayers = inferenceMode.gpuLayers
        let contextSize = config.contextSize
        let modelUrl = url
        let ggmlTypeK = toGGMLType(kvCacheTypeK)
        let ggmlTypeV = toGGMLType(kvCacheTypeV)

        print("[LlamaInference] Config - gpuLayers: \(gpuLayers), contextSize: \(contextSize)")

        // Perform heavy model loading on background thread to avoid blocking UI
        let pointers = try await Task.detached(priority: .userInitiated) {
            print("[LlamaInference] Background task started - loading model file...")

            // Model parameters - configure based on inference mode
            var modelParams = llama_model_default_params()
            modelParams.n_gpu_layers = gpuLayers

            // Load model (this is the main blocking operation - can take 1-7 seconds)
            let loadStart = Date()
            guard let model = llama_model_load_from_file(modelUrl.path, modelParams) else {
                print("[LlamaInference] ERROR: llama_model_load_from_file returned nil")
                throw LlamaError.modelNotFound
            }
            let loadDuration = Date().timeIntervalSince(loadStart)
            print("[LlamaInference] Model loaded in \(String(format: "%.2f", loadDuration))s")

            // Context parameters - optimized for speed on iOS
            var contextParams = llama_context_default_params()
            contextParams.n_ctx = contextSize
            // Larger batch sizes for faster prompt processing
            contextParams.n_batch = min(1024, contextSize)  // Increased from 512
            contextParams.n_ubatch = 512  // Increased micro-batch for better throughput
            // Use all performance cores for maximum speed
            let perfCores = max(4, ProcessInfo.processInfo.activeProcessorCount)
            contextParams.n_threads = Int32(perfCores)
            contextParams.n_threads_batch = Int32(perfCores)

            // KV Cache quantization for faster inference (reduces memory bandwidth)
            contextParams.type_k = ggmlTypeK
            contextParams.type_v = ggmlTypeV

            // Enable Flash Attention for Metal GPU acceleration
            contextParams.flash_attn_type = LLAMA_FLASH_ATTN_TYPE_ENABLED

            // Offload KQV operations to GPU for maximum speed
            contextParams.offload_kqv = true

            // Create context (secondary blocking operation)
            print("[LlamaInference] Creating context...")
            let ctxStart = Date()
            guard let context = llama_init_from_model(model, contextParams) else {
                print("[LlamaInference] ERROR: llama_init_from_model returned nil")
                llama_model_free(model)
                throw LlamaError.contextCreationFailed
            }
            let ctxDuration = Date().timeIntervalSince(ctxStart)
            print("[LlamaInference] Context created in \(String(format: "%.2f", ctxDuration))s")

            return SendablePointer(model: model, context: context)
        }.value

        // Back on MainActor - update state
        self.model = pointers.model
        self.context = pointers.context
        self.loadingProgress = 1.0
        self.isLoaded = true
        print("[LlamaInference] Model load complete!")
    }

    /// Generate with ModelSettings
    func generate(
        prompt: String,
        settings: ModelSettings,
        stopSequences: [String] = [],
        onToken: @escaping @MainActor (String) -> Void
    ) async throws -> String {
        try await generate(
            prompt: prompt,
            maxTokens: settings.maxTokens,
            temperature: settings.temperature,
            topP: settings.topP,
            topK: Int32(settings.topK),
            repeatPenalty: settings.repeatPenalty,
            stopSequences: stopSequences,
            onToken: onToken
        )
    }

    func generate(
        prompt: String,
        maxTokens: Int = 512,
        temperature: Float = 0.7,
        topP: Float = 0.9,
        topK: Int32 = 40,
        repeatPenalty: Float = 1.1,
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

        // Check for context overflow before processing
        let maxContextWithBuffer = Int(config.contextSize) - maxTokens
        if promptTokens.count > maxContextWithBuffer {
            logWarning("LLM", "Context overflow detected", [
                "tokenCount": "\(promptTokens.count)",
                "maxContext": "\(maxContextWithBuffer)"
            ])
            throw LlamaError.contextOverflow(tokenCount: promptTokens.count, maxContext: maxContextWithBuffer)
        }

        // Clear memory
        let memory = llama_get_memory(context)
        llama_memory_clear(memory, true)

        // Process prompt in chunks to avoid exceeding n_batch limit
        // n_batch is set to min(512, contextSize), so we process in chunks of 512
        let batchSize = 512
        let totalTokens = promptTokens.count
        var processedTokens = 0

        while processedTokens < totalTokens {
            let remainingTokens = totalTokens - processedTokens
            let chunkSize = min(batchSize, remainingTokens)

            let decodeResult: Int32 = promptTokens.withUnsafeMutableBufferPointer { bufferPtr in
                let chunkPtr = bufferPtr.baseAddress! + processedTokens
                let batch = llama_batch_get_one(chunkPtr, Int32(chunkSize))
                return llama_decode(context, batch)
            }

            if decodeResult != 0 {
                throw LlamaError.generationFailed("Failed to process prompt chunk at offset \(processedTokens): \(decodeResult)")
            }

            processedTokens += chunkSize

            // Yield to allow UI updates during long prompt processing
            if processedTokens < totalTokens {
                await Task.yield()
            }
        }

        // Create sampler chain
        let samplerParams = llama_sampler_chain_default_params()
        guard let sampler = llama_sampler_chain_init(samplerParams) else {
            throw LlamaError.generationFailed("Failed to create sampler chain")
        }
        defer { llama_sampler_free(sampler) }

        // Faster sampling: use greedy for low temperatures
        if temperature < 0.1 {
            // Greedy decoding - fastest
            llama_sampler_chain_add(sampler, llama_sampler_init_greedy())
        } else {
            // Add repeat penalty first
            if repeatPenalty > 1.0 {
                llama_sampler_chain_add(sampler, llama_sampler_init_penalties(64, repeatPenalty, 0.0, 0.0))
            }
            // Add samplers to chain with user-specified values
            llama_sampler_chain_add(sampler, llama_sampler_init_top_k(topK))
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

            // Yield periodically for cancellation responsiveness (less frequent = faster throughput)
            if tokenIndex % 64 == 0 {
                await Task.yield()
            }

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

            // Yield to allow UI updates every 2 tokens for better responsiveness
            if tokenIndex % 2 == 0 {
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
        // Use reusable buffer to avoid allocation per token
        let length = llama_token_to_piece(vocab, token, &tokenBuffer, Int32(tokenBuffer.count), 0, true)

        if length > 0 {
            return tokenBuffer.prefix(Int(length)).map { UInt8(bitPattern: $0) }
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
        let modelMetadataName = config.name.lowercased()
        let modelFileName = modelPath?.lastPathComponent.lowercased() ?? ""

        // Check both metadata name and filename for model identification
        // Filename takes priority (e.g., "eliochat-1.7b.gguf" should be treated as ElioChat even if metadata says "Photon")
        let isElioChat = modelFileName.contains("eliochat") || modelMetadataName.contains("eliochat")
        let isQwen = modelMetadataName.contains("qwen") || modelFileName.contains("qwen")
        let isDeepSeekQwen = modelMetadataName.contains("deepseek") && modelMetadataName.contains("qwen")
        let isDeepSeekLlama = modelMetadataName.contains("deepseek") && modelMetadataName.contains("llama")
        let isPhoton = modelMetadataName.contains("photon") && !isElioChat  // Don't treat as Photon if it's ElioChat
        let isNemotron = modelMetadataName.contains("nemotron") || modelFileName.contains("nemotron")
        let isLlama = modelMetadataName.contains("llama") || modelFileName.contains("llama")

        // Debug: Log model identification
        print("[LlamaInference] formatChatPrompt - modelFileName: \(modelFileName)")
        print("[LlamaInference] formatChatPrompt - modelMetadataName: \(modelMetadataName)")
        print("[LlamaInference] formatChatPrompt - isElioChat: \(isElioChat), isQwen: \(isQwen), isPhoton: \(isPhoton), isNemotron: \(isNemotron)")
        print("[LlamaInference] formatChatPrompt - enableThinking: \(enableThinking)")

        if isDeepSeekQwen {
            // DeepSeek-R1 Distill (Qwen-based) format
            prompt = "<|im_start|>system\n\(systemPrompt)<|im_end|>\n"
            for message in messages {
                let role = message.role == .user ? "user" : "assistant"
                prompt += "<|im_start|>\(role)\n\(message.content)<|im_end|>\n"
            }
            prompt += "<|im_start|>assistant\n<think>\n"
        } else if isDeepSeekLlama {
            // DeepSeek-R1 Distill (Llama-based) format
            prompt = "<|begin_of_text|><|start_header_id|>system<|end_header_id|>\n\n\(systemPrompt)<|eot_id|>"
            for message in messages {
                let role = message.role == .user ? "user" : "assistant"
                prompt += "<|start_header_id|>\(role)<|end_header_id|>\n\n\(message.content)<|eot_id|>"
            }
            prompt += "<|start_header_id|>assistant<|end_header_id|>\n\n<think>\n"
        } else if isNemotron {
            // NVIDIA Nemotron-Nano (Mamba-2 + Transformer hybrid) - ChatML with thinking mode
            prompt = "<|im_start|>system\n\(systemPrompt)<|im_end|>\n"
            for message in messages {
                let role = message.role == .user ? "user" : "assistant"
                prompt += "<|im_start|>\(role)\n\(message.content)<|im_end|>\n"
            }
            if enableThinking {
                prompt += "<|im_start|>assistant\n<think>\n"
            } else {
                prompt += "<|im_start|>assistant\n"
            }
        } else if isElioChat || isQwen {
            // ElioChat / Qwen3 (Qwen-based) with thinking mode support
            prompt = "<|im_start|>system\n\(systemPrompt)<|im_end|>\n"
            for message in messages {
                let role = message.role == .user ? "user" : "assistant"
                prompt += "<|im_start|>\(role)\n\(message.content)<|im_end|>\n"
            }
            // Enable thinking mode for Qwen3/ElioChat by starting with <think>
            if enableThinking {
                prompt += "<|im_start|>assistant\n<think>\n"
            } else {
                prompt += "<|im_start|>assistant\n"
            }
        } else if isPhoton {
            // Photon (Qwen-based) - does NOT support thinking mode (only if not identified as ElioChat)
            prompt = "<|im_start|>system\n\(systemPrompt)<|im_end|>\n"
            for message in messages {
                let role = message.role == .user ? "user" : "assistant"
                prompt += "<|im_start|>\(role)\n\(message.content)<|im_end|>\n"
            }
            prompt += "<|im_start|>assistant\n"
        } else if isLlama {
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
    case contextOverflow(tokenCount: Int, maxContext: Int)

    var errorDescription: String? {
        switch self {
        case .modelNotFound: return String(localized: "error.model.not.found")
        case .modelNotLoaded: return String(localized: "error.model.not.loaded")
        case .contextCreationFailed: return String(localized: "error.context.failed")
        case .tokenizationFailed: return String(localized: "error.tokenization.failed")
        case .generationFailed(let msg): return String(localized: "error.generation.failed") + ": \(msg)"
        case .contextOverflow(let tokenCount, let maxContext):
            return String(localized: "error.context.overflow", defaultValue: "Context overflow: \(tokenCount) tokens exceeds maximum \(maxContext)")
        }
    }
}
