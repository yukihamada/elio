import Foundation

/// Cloud API backend for Genius mode
/// Supports OpenAI, Anthropic, and Google AI providers
/// Token cost: 5 per message
@MainActor
final class CloudBackend: InferenceBackend, ObservableObject {
    private let keychain = KeychainManager.shared
    private var currentTask: Task<String, Error>?

    @Published private(set) var isGenerating = false
    @Published var provider: CloudProvider = .openai

    var backendId: String { "cloud_\(provider.rawValue)" }
    var displayName: String { ChatMode.genius.displayName }
    var tokenCost: Int { 5 }

    var isReady: Bool {
        switch provider {
        case .openai:
            return keychain.hasAPIKey(for: .openai)
        case .anthropic:
            return keychain.hasAPIKey(for: .anthropic)
        case .google:
            return keychain.hasAPIKey(for: .google)
        }
    }

    func setProvider(_ newProvider: CloudProvider) {
        provider = newProvider
    }

    func generate(
        messages: [Message],
        systemPrompt: String,
        settings: ModelSettings,
        onToken: @escaping (String) -> Void
    ) async throws -> String {
        isGenerating = true
        defer { isGenerating = false }

        switch provider {
        case .openai:
            return try await generateOpenAI(messages: messages, systemPrompt: systemPrompt, settings: settings, onToken: onToken)
        case .anthropic:
            return try await generateAnthropic(messages: messages, systemPrompt: systemPrompt, settings: settings, onToken: onToken)
        case .google:
            return try await generateGoogle(messages: messages, systemPrompt: systemPrompt, settings: settings, onToken: onToken)
        }
    }

    func stopGeneration() {
        currentTask?.cancel()
        currentTask = nil
        isGenerating = false
    }

    // MARK: - OpenAI

    private func generateOpenAI(
        messages: [Message],
        systemPrompt: String,
        settings: ModelSettings,
        onToken: @escaping (String) -> Void
    ) async throws -> String {
        guard let apiKey = keychain.getAPIKey(for: .openai) else {
            throw InferenceError.apiKeyMissing
        }

        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var apiMessages: [[String: Any]] = [
            ["role": "system", "content": systemPrompt]
        ]
        for message in messages {
            let role = message.role == .user ? "user" : "assistant"
            apiMessages.append(["role": role, "content": message.content])
        }

        let body: [String: Any] = [
            "model": provider.defaultModel,
            "messages": apiMessages,
            "temperature": Double(settings.temperature),
            "max_tokens": settings.maxTokens,
            "stream": true
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        return try await streamOpenAIResponse(request: request, onToken: onToken)
    }

    private func streamOpenAIResponse(request: URLRequest, onToken: @escaping (String) -> Void) async throws -> String {
        let (asyncBytes, response) = try await URLSession.shared.bytes(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw InferenceError.invalidResponse
        }

        if httpResponse.statusCode == 429 {
            throw InferenceError.rateLimited
        }

        guard httpResponse.statusCode == 200 else {
            throw InferenceError.serverError(httpResponse.statusCode, "OpenAI API error")
        }

        var fullResponse = ""

        for try await line in asyncBytes.lines {
            try Task.checkCancellation()

            guard line.hasPrefix("data: ") else { continue }
            let jsonString = String(line.dropFirst(6))
            if jsonString == "[DONE]" { break }

            guard let data = jsonString.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = json["choices"] as? [[String: Any]],
                  let delta = choices.first?["delta"] as? [String: Any],
                  let content = delta["content"] as? String else {
                continue
            }

            fullResponse += content
            await MainActor.run { onToken(content) }
        }

        return fullResponse
    }

    // MARK: - Anthropic

    private func generateAnthropic(
        messages: [Message],
        systemPrompt: String,
        settings: ModelSettings,
        onToken: @escaping (String) -> Void
    ) async throws -> String {
        guard let apiKey = keychain.getAPIKey(for: .anthropic) else {
            throw InferenceError.apiKeyMissing
        }

        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var apiMessages: [[String: Any]] = []
        for message in messages {
            let role = message.role == .user ? "user" : "assistant"
            apiMessages.append(["role": role, "content": message.content])
        }

        let body: [String: Any] = [
            "model": provider.defaultModel,
            "system": systemPrompt,
            "messages": apiMessages,
            "max_tokens": settings.maxTokens,
            "stream": true
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        return try await streamAnthropicResponse(request: request, onToken: onToken)
    }

    private func streamAnthropicResponse(request: URLRequest, onToken: @escaping (String) -> Void) async throws -> String {
        let (asyncBytes, response) = try await URLSession.shared.bytes(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw InferenceError.invalidResponse
        }

        if httpResponse.statusCode == 429 {
            throw InferenceError.rateLimited
        }

        guard httpResponse.statusCode == 200 else {
            throw InferenceError.serverError(httpResponse.statusCode, "Anthropic API error")
        }

        var fullResponse = ""

        for try await line in asyncBytes.lines {
            try Task.checkCancellation()

            guard line.hasPrefix("data: ") else { continue }
            let jsonString = String(line.dropFirst(6))

            guard let data = jsonString.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }

            // Check for message_stop event
            if let eventType = json["type"] as? String, eventType == "message_stop" {
                break
            }

            // Parse content_block_delta
            if let delta = json["delta"] as? [String: Any],
               let text = delta["text"] as? String {
                fullResponse += text
                await MainActor.run { onToken(text) }
            }
        }

        return fullResponse
    }

    // MARK: - Google

    private func generateGoogle(
        messages: [Message],
        systemPrompt: String,
        settings: ModelSettings,
        onToken: @escaping (String) -> Void
    ) async throws -> String {
        guard let apiKey = keychain.getAPIKey(for: .google) else {
            throw InferenceError.apiKeyMissing
        }

        let urlString = "https://generativelanguage.googleapis.com/v1beta/models/\(provider.defaultModel):streamGenerateContent?key=\(apiKey)"
        var request = URLRequest(url: URL(string: urlString)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Build contents array
        var contents: [[String: Any]] = []

        // Add system instruction first as a user message (Gemini style)
        contents.append([
            "role": "user",
            "parts": [["text": systemPrompt]]
        ])
        contents.append([
            "role": "model",
            "parts": [["text": "Understood. I will follow these instructions."]]
        ])

        for message in messages {
            let role = message.role == .user ? "user" : "model"
            contents.append([
                "role": role,
                "parts": [["text": message.content]]
            ])
        }

        let body: [String: Any] = [
            "contents": contents,
            "generationConfig": [
                "temperature": Double(settings.temperature),
                "maxOutputTokens": settings.maxTokens
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        return try await streamGoogleResponse(request: request, onToken: onToken)
    }

    private func streamGoogleResponse(request: URLRequest, onToken: @escaping (String) -> Void) async throws -> String {
        let (asyncBytes, response) = try await URLSession.shared.bytes(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw InferenceError.invalidResponse
        }

        if httpResponse.statusCode == 429 {
            throw InferenceError.rateLimited
        }

        guard httpResponse.statusCode == 200 else {
            throw InferenceError.serverError(httpResponse.statusCode, "Google AI API error")
        }

        var fullResponse = ""
        var buffer = ""

        for try await line in asyncBytes.lines {
            try Task.checkCancellation()

            buffer += line

            // Google streams JSON objects, parse when complete
            guard let data = buffer.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }

            buffer = ""

            // Parse candidates array
            if let candidates = json["candidates"] as? [[String: Any]],
               let content = candidates.first?["content"] as? [String: Any],
               let parts = content["parts"] as? [[String: Any]],
               let text = parts.first?["text"] as? String {
                fullResponse += text
                await MainActor.run { onToken(text) }
            }
        }

        return fullResponse
    }
}
