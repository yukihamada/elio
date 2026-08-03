import Foundation
import MLX
import MLXLLM
import MLXLMCommon
import Tokenizers

/// MLX Swift inference engine for Apple Silicon-optimized LLM inference.
/// Provides 20-40% faster inference than llama.cpp on Apple devices.
@MainActor
final class MLXInference: ObservableObject {
    @Published private(set) var isLoaded = false
    @Published private(set) var isGenerating = false
    @Published var loadingProgress: Double = 0

    private var modelContainer: ModelContainer?
    private var modelId: String?

    // MARK: - Model Loading

    /// Load an MLX model from HuggingFace hub
    func loadModel(hubId: String) async throws {
        loadingProgress = 0.1

        // Configure GPU memory limit (leave room for OS)
        let memoryGB = Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824
        let cacheLimit = Int(memoryGB * 0.6) // Use 60% of RAM
        MLX.GPU.set(cacheLimit: cacheLimit * 1024 * 1024 * 1024)

        let modelConfig = ModelConfiguration(id: hubId)

        loadingProgress = 0.3

        modelContainer = try await LLMModelFactory.shared.loadContainer(
            configuration: modelConfig
        ) { progress in
            Task { @MainActor in
                self.loadingProgress = 0.3 + progress.fractionCompleted * 0.6
            }
        }

        modelId = hubId
        loadingProgress = 1.0
        isLoaded = true
        print("[MLXInference] Model loaded: \(hubId)")
    }

    /// Load an MLX model from local directory
    func loadModel(from localPath: URL) async throws {
        loadingProgress = 0.1

        let memoryGB = Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824
        let cacheLimit = Int(memoryGB * 0.6)
        MLX.GPU.set(cacheLimit: cacheLimit * 1024 * 1024 * 1024)

        let modelConfig = ModelConfiguration(directory: localPath)

        loadingProgress = 0.3

        modelContainer = try await LLMModelFactory.shared.loadContainer(
            configuration: modelConfig
        ) { progress in
            Task { @MainActor in
                self.loadingProgress = 0.3 + progress.fractionCompleted * 0.6
            }
        }

        modelId = localPath.lastPathComponent
        loadingProgress = 1.0
        isLoaded = true
        print("[MLXInference] Model loaded from: \(localPath.path)")
    }

    // MARK: - Unload

    func unload() {
        modelContainer = nil
        isLoaded = false
        isGenerating = false
        modelId = nil
        MLX.GPU.clearCache()
    }

    // MARK: - Generation

    /// Generate text with streaming, matching the LlamaInference interface
    func generate(
        prompt: String,
        maxTokens: Int = 1024,
        temperature: Float = 0.7,
        topP: Float = 0.9,
        repetitionPenalty: Float = 1.1,
        onToken: @escaping (String) -> Void
    ) async throws -> String {
        guard let container = modelContainer else {
            throw MLXError.modelNotLoaded
        }

        isGenerating = true
        defer { isGenerating = false }

        let generateParameters = GenerateParameters(
            temperature: temperature,
            topP: topP,
            repetitionPenalty: repetitionPenalty
        )

        var fullText = ""

        let result = try await container.perform { context in
            let input = try await context.processor.prepare(input: .init(prompt: prompt))
            return try MLXLMCommon.generate(
                input: input,
                parameters: generateParameters,
                context: context
            ) { tokens in
                let text = context.tokenizer.decode(tokens: [tokens.last!])
                Task { @MainActor in
                    onToken(text)
                }
                fullText += text

                if tokens.count >= maxTokens {
                    return .stop
                }
                return .more
            }
        }

        return fullText
    }

    /// Generate with messages (ChatML format)
    func generateWithMessages(
        messages: [Message],
        systemPrompt: String,
        settings: ModelSettings,
        enableThinking: Bool = false,
        onToken: @escaping (String) -> Void
    ) async throws -> String {
        let prompt = formatChatPrompt(
            messages: messages,
            systemPrompt: systemPrompt,
            enableThinking: enableThinking
        )

        return try await generate(
            prompt: prompt,
            maxTokens: settings.maxTokens,
            temperature: settings.temperature,
            topP: settings.topP,
            repetitionPenalty: settings.repeatPenalty,
            onToken: onToken
        )
    }

    // MARK: - Chat Template

    /// Format messages into ChatML prompt (same as Qwen3/3.5)
    func formatChatPrompt(
        messages: [Message],
        systemPrompt: String,
        enableThinking: Bool = false
    ) -> String {
        var prompt = "<|im_start|>system\n\(systemPrompt)<|im_end|>\n"

        for message in messages {
            switch message.role {
            case .user:
                prompt += "<|im_start|>user\n\(message.content)<|im_end|>\n"
            case .assistant:
                prompt += "<|im_start|>assistant\n\(message.content)<|im_end|>\n"
            case .tool:
                prompt += "<|im_start|>tool\n\(message.content)<|im_end|>\n"
            case .system:
                continue // Already added
            }
        }

        if enableThinking {
            prompt += "<|im_start|>assistant\n<think>\n"
        } else {
            prompt += "<|im_start|>assistant\n"
        }

        return prompt
    }

    // MARK: - Error

    enum MLXError: Error, LocalizedError {
        case modelNotLoaded
        case generationFailed(String)

        var errorDescription: String? {
            switch self {
            case .modelNotLoaded: return "MLX model not loaded"
            case .generationFailed(let msg): return "Generation failed: \(msg)"
            }
        }
    }
}
