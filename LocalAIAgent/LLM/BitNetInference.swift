#if !targetEnvironment(macCatalyst)
//
//  BitNetInference.swift
//  LocalAIAgent
//
//  BitNet 1.58-bit model inference engine
//

import Foundation

/// BitNet inference engine for 1.58-bit quantized models
@MainActor
final class BitNetInference: ObservableObject {
    static let shared = BitNetInference()

    @Published private(set) var isModelLoaded = false
    @Published private(set) var isGenerating = false
    @Published private(set) var currentModelName: String?

    private var model: OpaquePointer?
    private var context: OpaquePointer?
    private var generationTask: Task<Void, Never>?

    private init() {
        bitnet_backend_init()
    }

    deinit {
        unloadModel()
        bitnet_backend_free()
    }

    // MARK: - Model Loading

    func loadModel(path: String, gpuLayers: Int32 = 99) async throws {
        unloadModel()

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                var params = bitnet_model_default_params()
                params.n_gpu_layers = gpuLayers

                guard let model = bitnet_load_model(path, params) else {
                    continuation.resume(throwing: BitNetError.modelLoadFailed)
                    return
                }

                var ctxParams = bitnet_context_default_params()
                ctxParams.n_ctx = 4096
                ctxParams.n_batch = 512
                ctxParams.n_threads = UInt32(ProcessInfo.processInfo.activeProcessorCount)

                guard let ctx = bitnet_new_context(model, ctxParams) else {
                    bitnet_free_model(model)
                    continuation.resume(throwing: BitNetError.contextCreationFailed)
                    return
                }

                DispatchQueue.main.async {
                    self?.model = model
                    self?.context = ctx
                    self?.isModelLoaded = true
                    self?.currentModelName = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
                    continuation.resume()
                }
            }
        }
    }

    func unloadModel() {
        generationTask?.cancel()
        generationTask = nil

        if let ctx = context {
            bitnet_free_context(ctx)
            context = nil
        }

        if let model = model {
            bitnet_free_model(model)
            self.model = nil
        }

        isModelLoaded = false
        currentModelName = nil
    }

    // MARK: - Generation

    func generate(
        prompt: String,
        maxTokens: Int = 512,
        temperature: Float = 0.7,
        topP: Float = 0.9,
        topK: Int32 = 40,
        onToken: @escaping (String) -> Void
    ) async throws {
        guard let model = model, let context = context else {
            throw BitNetError.modelNotLoaded
        }

        isGenerating = true
        defer { isGenerating = false }

        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                DispatchQueue.global(qos: .userInitiated).async {
                    // Tokenize input
                    var tokens = [bitnet_token](repeating: 0, count: 4096)
                    let nTokens = bitnet_tokenize(model, prompt, &tokens, Int32(tokens.count), true)

                    if nTokens < 0 {
                        continuation.resume(throwing: BitNetError.tokenizationFailed)
                        return
                    }

                    // Initial evaluation
                    if !bitnet_eval(context, tokens, nTokens, 0) {
                        continuation.resume(throwing: BitNetError.evaluationFailed)
                        return
                    }

                    var samplingParams = bitnet_sampling_default_params()
                    samplingParams.temperature = temperature
                    samplingParams.top_p = topP
                    samplingParams.top_k = topK

                    let eosToken = bitnet_token_eos(model)
                    var nPast = nTokens
                    var generatedTokens = 0

                    // Generation loop
                    while generatedTokens < maxTokens && !Task.isCancelled {
                        let token = bitnet_sample(context, samplingParams)

                        if token == eosToken || token < 0 {
                            break
                        }

                        // Convert token to text
                        if let piece = bitnet_token_to_piece(model, token) {
                            let text = String(cString: piece)
                            DispatchQueue.main.async {
                                onToken(text)
                            }
                        }

                        // Evaluate next token
                        var nextToken = token
                        if !bitnet_eval(context, &nextToken, 1, nPast) {
                            break
                        }

                        nPast += 1
                        generatedTokens += 1
                    }

                    continuation.resume()
                }
            }
        } onCancel: {
            // Handle cancellation
        }
    }

    func stopGeneration() {
        generationTask?.cancel()
        generationTask = nil
    }
}

// MARK: - Errors

enum BitNetError: LocalizedError {
    case modelLoadFailed
    case contextCreationFailed
    case modelNotLoaded
    case tokenizationFailed
    case evaluationFailed

    var errorDescription: String? {
        switch self {
        case .modelLoadFailed:
            return "Failed to load BitNet model"
        case .contextCreationFailed:
            return "Failed to create inference context"
        case .modelNotLoaded:
            return "No model is loaded"
        case .tokenizationFailed:
            return "Failed to tokenize input"
        case .evaluationFailed:
            return "Failed to evaluate tokens"
        }
    }
}
#endif  // !targetEnvironment(macCatalyst)
