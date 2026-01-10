import Foundation
import CoreML

@MainActor
final class CoreMLInference: ObservableObject {
    @Published private(set) var isLoaded = false
    @Published private(set) var isGenerating = false

    private var model: MLModel?
    private var ggufModelPath: URL?
    private var tokenizer: Tokenizer?
    private var config: ModelConfig
    private var isGGUFModel = false
    private var llamaInference: LlamaInference?

    struct ModelConfig {
        let name: String
        let maxContextLength: Int
        let vocabularySize: Int
        let eosTokenId: Int
        let bosTokenId: Int

        static let llama3_2_3B = ModelConfig(
            name: "Llama-3.2-3B",
            maxContextLength: 4096,
            vocabularySize: 128256,
            eosTokenId: 128001,
            bosTokenId: 128000
        )

        static let phi3Mini = ModelConfig(
            name: "Phi-3-mini-4k",
            maxContextLength: 4096,
            vocabularySize: 32064,
            eosTokenId: 32000,
            bosTokenId: 1
        )

        static let mistral7B = ModelConfig(
            name: "Mistral-7B",
            maxContextLength: 8192,
            vocabularySize: 32000,
            eosTokenId: 2,
            bosTokenId: 1
        )
    }

    init(config: ModelConfig = .llama3_2_3B) {
        self.config = config
    }

    deinit {
        // Ensure llama resources are freed
        // Note: llamaInference will be cleaned up by its own deinit
    }

    /// Explicitly unload the model and free resources
    func unload() {
        llamaInference?.unload()
        llamaInference = nil
        model = nil
        tokenizer = nil
        isLoaded = false
        isGGUFModel = false
        ggufModelPath = nil
    }

    /// Set the inference acceleration mode
    func setInferenceMode(_ mode: InferenceMode) {
        llamaInference?.inferenceMode = mode
    }

    func loadModel(from url: URL) async throws {
        let compiledURL = try await compileModelIfNeeded(url)

        let configuration = MLModelConfiguration()
        configuration.computeUnits = .cpuAndNeuralEngine

        model = try await MLModel.load(contentsOf: compiledURL, configuration: configuration)

        tokenizer = try await Tokenizer.load(for: config.name)

        isGGUFModel = false
        isLoaded = true
    }

    func loadGGUFModel(from url: URL) async throws {
        // Unload any existing model first to free GPU memory
        if isLoaded {
            unload()
        }

        // Store the GGUF model path for llama.cpp inference
        self.ggufModelPath = url

        // Determine llama config based on model name
        let llamaConfig: LlamaInference.Config
        let nameLower = config.name.lowercased()

        if nameLower.contains("deepseek") && nameLower.contains("qwen") {
            llamaConfig = .deepseekR1Qwen
        } else if nameLower.contains("deepseek") && nameLower.contains("llama") {
            llamaConfig = .deepseekR1Llama
        } else if nameLower.contains("qwen") {
            llamaConfig = .qwen3
        } else if nameLower.contains("llama") {
            llamaConfig = .llama3
        } else {
            // Default to Qwen for models with similar tokenizer (like Phi, Gemma)
            llamaConfig = .qwen3
        }

        // Initialize and load the llama.cpp model
        llamaInference = LlamaInference(config: llamaConfig)
        try await llamaInference?.loadModel(from: url)

        isGGUFModel = true
        isLoaded = true
    }

    private func compileModelIfNeeded(_ url: URL) async throws -> URL {
        let compiledPath = url.deletingPathExtension().appendingPathExtension("mlmodelc")

        if FileManager.default.fileExists(atPath: compiledPath.path) {
            return compiledPath
        }

        return try await Task.detached(priority: .userInitiated) {
            try MLModel.compileModel(at: url)
        }.value
    }

    func generate(
        prompt: String,
        maxTokens: Int = 512,
        temperature: Float = 0.7,
        topP: Float = 0.9,
        stopSequences: [String] = [],
        onToken: @escaping (String) -> Void
    ) async throws -> String {
        guard isLoaded else {
            throw LLMError.modelNotLoaded
        }

        isGenerating = true
        defer { isGenerating = false }

        // Use GGUF inference if model is GGUF format (doesn't need tokenizer)
        if isGGUFModel {
            return try await generateWithGGUF(
                prompt: prompt,
                maxTokens: maxTokens,
                temperature: temperature,
                topP: topP,
                stopSequences: stopSequences,
                onToken: onToken
            )
        }

        // CoreML model requires tokenizer
        guard let tokenizer = tokenizer else {
            throw LLMError.tokenizerNotLoaded
        }

        guard model != nil else {
            throw LLMError.modelNotLoaded
        }

        var inputIds = tokenizer.encode(prompt)

        if inputIds.count > config.maxContextLength - maxTokens {
            inputIds = Array(inputIds.suffix(config.maxContextLength - maxTokens))
        }

        var generatedTokens: [Int] = []
        var generatedText = ""

        for _ in 0..<maxTokens {
            let nextTokenId = try await predictNextToken(
                inputIds: inputIds + generatedTokens,
                temperature: temperature,
                topP: topP
            )

            if nextTokenId == config.eosTokenId {
                break
            }

            generatedTokens.append(nextTokenId)

            let tokenText = tokenizer.decode([nextTokenId])
            generatedText += tokenText
            onToken(tokenText)

            let shouldStop = stopSequences.contains { generatedText.hasSuffix($0) }
            if shouldStop {
                break
            }
        }

        return generatedText
    }

    private func predictNextToken(
        inputIds: [Int],
        temperature: Float,
        topP: Float
    ) async throws -> Int {
        guard let model = model else {
            throw LLMError.modelNotLoaded
        }

        let inputArray = try MLMultiArray(shape: [1, NSNumber(value: inputIds.count)], dataType: .int32)
        for (index, tokenId) in inputIds.enumerated() {
            inputArray[[0, index] as [NSNumber]] = NSNumber(value: tokenId)
        }

        let input = try MLDictionaryFeatureProvider(dictionary: ["input_ids": inputArray])

        let output = try await Task.detached(priority: .userInitiated) {
            try model.prediction(from: input)
        }.value

        guard let logits = output.featureValue(for: "logits")?.multiArrayValue else {
            throw LLMError.invalidOutput
        }

        let nextTokenId = sampleFromLogits(logits, temperature: temperature, topP: topP)
        return nextTokenId
    }

    private func sampleFromLogits(_ logits: MLMultiArray, temperature: Float, topP: Float) -> Int {
        let vocabSize = logits.shape.last!.intValue
        let lastPosition = logits.shape[1].intValue - 1

        var logitsArray = [Float](repeating: 0, count: vocabSize)
        for i in 0..<vocabSize {
            logitsArray[i] = logits[[0, lastPosition, i] as [NSNumber]].floatValue
        }

        if temperature <= 0.01 {
            return logitsArray.enumerated().max(by: { $0.element < $1.element })?.offset ?? 0
        }

        for i in 0..<vocabSize {
            logitsArray[i] /= temperature
        }

        let maxLogit = logitsArray.max() ?? 0
        var probs = logitsArray.map { exp($0 - maxLogit) }
        let sumProbs = probs.reduce(0, +)
        probs = probs.map { $0 / sumProbs }

        let sortedIndices = probs.enumerated().sorted { $0.element > $1.element }.map { $0.offset }
        var cumSum: Float = 0
        var topPIndices: [Int] = []

        for idx in sortedIndices {
            cumSum += probs[idx]
            topPIndices.append(idx)
            if cumSum >= topP {
                break
            }
        }

        var filteredProbs = [Float](repeating: 0, count: vocabSize)
        for idx in topPIndices {
            filteredProbs[idx] = probs[idx]
        }
        let filteredSum = filteredProbs.reduce(0, +)
        filteredProbs = filteredProbs.map { $0 / filteredSum }

        let random = Float.random(in: 0..<1)
        var cumulative: Float = 0
        for (idx, prob) in filteredProbs.enumerated() {
            cumulative += prob
            if cumulative >= random {
                return idx
            }
        }

        return topPIndices.first ?? 0
    }

    // MARK: - GGUF Model Inference

    private func generateWithGGUF(
        prompt: String,
        maxTokens: Int,
        temperature: Float,
        topP: Float,
        stopSequences: [String],
        onToken: @escaping (String) -> Void
    ) async throws -> String {
        guard let llamaInference = llamaInference else {
            throw LLMError.modelNotLoaded
        }

        // Use llama.cpp for inference
        return try await llamaInference.generate(
            prompt: prompt,
            maxTokens: maxTokens,
            temperature: temperature,
            topP: topP,
            stopSequences: stopSequences,
            onToken: onToken
        )
    }

    func generateWithMessages(
        messages: [Message],
        systemPrompt: String,
        maxTokens: Int = 512,
        onToken: @escaping (String) -> Void
    ) async throws -> String {
        let formattedPrompt = formatMessages(messages, systemPrompt: systemPrompt)
        return try await generate(
            prompt: formattedPrompt,
            maxTokens: maxTokens,
            temperature: 0.6,  // Lower temperature for faster, more focused generation
            topP: 0.85,        // Slightly tighter top_p for speed
            stopSequences: ["</tool_call>", "\n\nUser:", "\n\nHuman:", "<|im_end|>", "<|eot_id|>"],
            onToken: onToken
        )
    }

    private func formatMessages(_ messages: [Message], systemPrompt: String) -> String {
        var prompt = ""

        // Detect model family from name
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
            // Qwen3 format
            prompt = "<|im_start|>system\n\(systemPrompt)<|im_end|>\n"

            for message in messages {
                let role = message.role == .user ? "user" : "assistant"
                prompt += "<|im_start|>\(role)\n\(message.content)<|im_end|>\n"
            }

            prompt += "<|im_start|>assistant\n"

        } else if modelName.contains("llama") {
            // Llama 3 format
            prompt = "<|begin_of_text|><|start_header_id|>system<|end_header_id|>\n\n\(systemPrompt)<|eot_id|>"

            for message in messages {
                let role = message.role == .user ? "user" : "assistant"
                prompt += "<|start_header_id|>\(role)<|end_header_id|>\n\n\(message.content)<|eot_id|>"
            }

            prompt += "<|start_header_id|>assistant<|end_header_id|>\n\n"

        } else if modelName.contains("phi") {
            // Phi-3 format
            prompt = "<|system|>\n\(systemPrompt)<|end|>\n"

            for message in messages {
                let role = message.role == .user ? "<|user|>" : "<|assistant|>"
                prompt += "\(role)\n\(message.content)<|end|>\n"
            }

            prompt += "<|assistant|>\n"

        } else if modelName.contains("gemma") {
            // Gemma format
            prompt = "<start_of_turn>user\n\(systemPrompt)\n"

            for message in messages {
                if message.role == .user {
                    prompt += "\(message.content)<end_of_turn>\n<start_of_turn>model\n"
                } else {
                    prompt += "\(message.content)<end_of_turn>\n<start_of_turn>user\n"
                }
            }

        } else {
            // Default ChatML-like format
            prompt = "### System:\n\(systemPrompt)\n\n"

            for message in messages {
                let role = message.role == .user ? "User" : "Assistant"
                prompt += "### \(role):\n\(message.content)\n\n"
            }

            prompt += "### Assistant:\n"
        }

        return prompt
    }
}

enum LLMError: Error, LocalizedError {
    case modelNotLoaded
    case tokenizerNotLoaded
    case invalidOutput
    case generationFailed(String)

    var errorDescription: String? {
        switch self {
        case .modelNotLoaded: return String(localized: "error.model.not.loaded")
        case .tokenizerNotLoaded: return String(localized: "error.tokenizer.not.loaded", defaultValue: "Tokenizer not loaded")
        case .invalidOutput: return String(localized: "error.invalid.output", defaultValue: "Invalid model output")
        case .generationFailed(let msg): return String(localized: "error.generation.failed") + ": \(msg)"
        }
    }
}
