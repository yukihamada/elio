import Foundation

// MARK: - Notification for ChatWeb events

extension Notification.Name {
    /// Posted when a ChatWeb SSE `done` event arrives with credits info.
    /// `userInfo` keys: "credits_remaining" (Int), "model_used" (String?)
    static let chatWebCreditsUpdated = Notification.Name("chatWebCreditsUpdated")

    /// Posted when a ChatWeb SSE `tool_start` event arrives.
    /// `userInfo` keys: "name" (String), "input" ([String: Any]?)
    static let chatWebToolStart = Notification.Name("chatWebToolStart")

    /// Posted when a ChatWeb SSE `tool_result` event arrives.
    /// `userInfo` keys: "name" (String), "output" (String?)
    static let chatWebToolResult = Notification.Name("chatWebToolResult")

    /// Posted when a ChatWeb SSE `thinking` event arrives.
    /// `userInfo` keys: "text" (String)
    static let chatWebThinking = Notification.Name("chatWebThinking")
}

/// ChatWeb.ai cloud API backend
/// Uses api.chatweb.ai for fast cloud AI inference
/// No API key required - session-based with free credits
/// Token cost: 0 (uses ChatWeb.ai's own credit system)
@MainActor
final class ChatWebBackend: InferenceBackend, ObservableObject {
    private var currentTask: Task<String, Error>?

    @Published private(set) var isGenerating = false

    var backendId: String { "chatweb" }
    var displayName: String { ChatMode.chatweb.displayName }
    var tokenCost: Int { 0 }

    /// Always ready - no API key needed
    var isReady: Bool { true }

    /// Optional auth token for authenticated requests (set by SyncManager)
    var authToken: String?

    /// Selected model for cloud inference (nil = server default)
    var selectedModel: String?

    /// Last known credits remaining (updated from `done` events)
    @Published private(set) var lastCreditsRemaining: Int?

    /// Last model used (from `done` event)
    @Published private(set) var lastModelUsed: String?

    // ChatWeb.ai API settings
    private let streamURL = "https://api.chatweb.ai/api/v1/chat/stream"

    /// Available models that can be selected (populated externally)
    static let availableModels: [(id: String, name: String)] = [
        ("auto", "Auto (server default)"),
        ("claude-sonnet-4-5", "Claude Sonnet 4.5"),
        ("claude-haiku-3-5", "Claude Haiku 3.5"),
        ("gpt-4o", "GPT-4o"),
        ("gpt-4o-mini", "GPT-4o Mini"),
    ]

    /// Persistent session ID for conversation continuity
    private var sessionId: String {
        let key = "chatweb_session_id"
        if let existing = UserDefaults.standard.string(forKey: key) {
            return existing
        }
        let newId = "elio-\(UUID().uuidString.prefix(12).lowercased())"
        UserDefaults.standard.set(newId, forKey: key)
        return newId
    }

    func generate(
        messages: [Message],
        systemPrompt: String,
        settings: ModelSettings,
        onToken: @escaping (String) -> Void
    ) async throws -> String {
        isGenerating = true
        defer { isGenerating = false }

        // Use the last user message as the primary message
        guard let lastUserMessage = messages.last(where: { $0.role == .user }) else {
            throw InferenceError.invalidResponse
        }

        // Build conversation history from all messages
        let history = messages
            .filter { $0.role == .user || $0.role == .assistant }
            .map { msg -> [String: String] in
                [
                    "role": msg.role.rawValue,
                    "content": msg.content
                ]
            }

        let request = try buildRequest(
            message: lastUserMessage.content,
            history: history,
            systemPrompt: systemPrompt
        )
        let result = try await streamSSE(request: request, onToken: onToken)
        return result
    }

    func stopGeneration() {
        currentTask?.cancel()
        currentTask = nil
        isGenerating = false
    }

    /// Reset session (starts a new conversation on ChatWeb.ai side)
    func resetSession() {
        UserDefaults.standard.removeObject(forKey: "chatweb_session_id")
    }

    /// Set the model to use for inference
    func setModel(_ modelId: String?) {
        if modelId == "auto" {
            selectedModel = nil
        } else {
            selectedModel = modelId
        }
    }

    // MARK: - Private

    private func buildRequest(
        message: String,
        history: [[String: String]],
        systemPrompt: String
    ) throws -> URLRequest {
        var request = URLRequest(url: URL(string: streamURL)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Elio Chat iOS", forHTTPHeaderField: "User-Agent")

        // Add Bearer token if logged in
        if let token = authToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        var body: [String: Any] = [
            "message": message,
            "session_id": sessionId,
            "channel": "elio",
            "history": history
        ]

        // Add system prompt if non-empty
        if !systemPrompt.isEmpty {
            body["system_prompt"] = systemPrompt
        }

        // Add model selection if specified
        if let model = selectedModel {
            body["model"] = model
        }

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
            throw InferenceError.serverError(httpResponse.statusCode, "ChatWeb.ai API error")
        }

        var fullResponse = ""

        for try await line in asyncBytes.lines {
            try Task.checkCancellation()

            guard line.hasPrefix("data: ") else { continue }
            let jsonString = String(line.dropFirst(6))

            guard let data = jsonString.data(using: .utf8) else { continue }

            // Try parsing as a JSON array first (agentic SSE format)
            if let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                for event in array {
                    fullResponse = processSSEEvent(event, currentResponse: fullResponse, onToken: onToken)
                }
                continue
            }

            // Fall back to single object parsing
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }

            fullResponse = processSSEEvent(json, currentResponse: fullResponse, onToken: onToken)
        }

        return fullResponse
    }

    /// Process a single SSE event dictionary and return the updated full response string.
    private func processSSEEvent(
        _ json: [String: Any],
        currentResponse: String,
        onToken: @escaping (String) -> Void
    ) -> String {
        var fullResponse = currentResponse
        guard let type = json["type"] as? String else { return fullResponse }

        switch type {
        case "message":
            // New format: {"type":"message","text":"..."}
            if let text = json["text"] as? String {
                fullResponse += text
                onToken(text)
            }

        case "content":
            // Legacy format: {"type":"content","content":"..."}
            if let content = json["content"] as? String {
                fullResponse += content
                onToken(content)
            }

        case "tool_start":
            let name = json["name"] as? String ?? "unknown"
            let input = json["input"] as? [String: Any]
            NotificationCenter.default.post(
                name: .chatWebToolStart,
                object: nil,
                userInfo: [
                    "name": name,
                    "input": input as Any
                ]
            )

        case "tool_result":
            let name = json["name"] as? String ?? "unknown"
            let output = json["output"] as? String
            NotificationCenter.default.post(
                name: .chatWebToolResult,
                object: nil,
                userInfo: [
                    "name": name,
                    "output": output as Any
                ]
            )

        case "thinking":
            if let text = json["text"] as? String {
                NotificationCenter.default.post(
                    name: .chatWebThinking,
                    object: nil,
                    userInfo: ["text": text]
                )
            }

        case "done":
            let creditsRemaining = json["credits_remaining"] as? Int
            let modelUsed = json["model_used"] as? String

            if let credits = creditsRemaining {
                lastCreditsRemaining = credits
            }
            if let model = modelUsed {
                lastModelUsed = model
            }

            // Notify SyncManager and UI about credit updates
            var userInfo: [String: Any] = [:]
            if let credits = creditsRemaining {
                userInfo["credits_remaining"] = credits
            }
            if let model = modelUsed {
                userInfo["model_used"] = model
            }
            if !userInfo.isEmpty {
                NotificationCenter.default.post(
                    name: .chatWebCreditsUpdated,
                    object: nil,
                    userInfo: userInfo
                )
            }

        default:
            break
        }

        return fullResponse
    }
}
