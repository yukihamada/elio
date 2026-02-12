import Foundation

/// Groq API backend for Fast mode
/// Uses Llama-3.3-70b or Mixtral for ultra-fast inference
/// Token cost: 1 per message
@MainActor
final class GroqBackend: InferenceBackend, ObservableObject {
    private let keychain = KeychainManager.shared
    private var currentTask: Task<String, Error>?

    @Published private(set) var isGenerating = false

    var backendId: String { "groq" }
    var displayName: String { ChatMode.fast.displayName }
    var tokenCost: Int { 1 }

    var isReady: Bool {
        keychain.hasAPIKey(for: .groq)
    }

    // Groq API settings
    private let baseURL = "https://api.groq.com/openai/v1/chat/completions"
    private let defaultModel = "llama-3.3-70b-versatile"

    func generate(
        messages: [Message],
        systemPrompt: String,
        settings: ModelSettings,
        onToken: @escaping (String) -> Void
    ) async throws -> String {
        guard let apiKey = keychain.getAPIKey(for: .groq) else {
            throw InferenceError.apiKeyMissing
        }

        isGenerating = true
        defer { isGenerating = false }

        // Build request
        let request = try buildRequest(
            messages: messages,
            systemPrompt: systemPrompt,
            settings: settings,
            apiKey: apiKey
        )

        // Stream SSE response
        let result = try await streamSSE(request: request, onToken: onToken)
        return result
    }

    func stopGeneration() {
        currentTask?.cancel()
        currentTask = nil
        isGenerating = false
    }

    // MARK: - Private

    private func buildRequest(
        messages: [Message],
        systemPrompt: String,
        settings: ModelSettings,
        apiKey: String
    ) throws -> URLRequest {
        var request = URLRequest(url: URL(string: baseURL)!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Build messages array
        var apiMessages: [[String: Any]] = [
            ["role": "system", "content": systemPrompt]
        ]

        for message in messages {
            let role: String
            switch message.role {
            case .user: role = "user"
            case .assistant: role = "assistant"
            case .system: role = "system"
            case .tool: role = "user" // Groq doesn't support tool role, use user
            }
            apiMessages.append(["role": role, "content": message.content])
        }

        let body: [String: Any] = [
            "model": defaultModel,
            "messages": apiMessages,
            "temperature": Double(settings.temperature),
            "top_p": Double(settings.topP),
            "max_tokens": settings.maxTokens,
            "stream": true
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    private func streamSSE(
        request: URLRequest,
        onToken: @escaping (String) -> Void
    ) async throws -> String {
        let (asyncBytes, response) = try await URLSession.shared.bytes(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw InferenceError.invalidResponse
        }

        if httpResponse.statusCode == 429 {
            throw InferenceError.rateLimited
        }

        guard httpResponse.statusCode == 200 else {
            throw InferenceError.serverError(httpResponse.statusCode, "Groq API error")
        }

        var fullResponse = ""

        for try await line in asyncBytes.lines {
            // Check for cancellation
            try Task.checkCancellation()

            // Parse SSE format: "data: {...}"
            guard line.hasPrefix("data: ") else { continue }

            let jsonString = String(line.dropFirst(6))

            // Check for stream end
            if jsonString == "[DONE]" {
                break
            }

            // Parse JSON
            guard let data = jsonString.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = json["choices"] as? [[String: Any]],
                  let delta = choices.first?["delta"] as? [String: Any],
                  let content = delta["content"] as? String else {
                continue
            }

            fullResponse += content
            await MainActor.run {
                onToken(content)
            }
        }

        return fullResponse
    }
}
