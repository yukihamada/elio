import Foundation

/// Wisbee Mode: Privacy-first AI backend
/// Priority 1: Local LLM (LocalBackend) if a model is loaded
/// Priority 2: ChatWeb.ai with `mode: "local"` parameter (local-only processing)
/// NEVER falls back to cloud mode. All data stays on-device or in local-only API.
/// Conversation history is stored locally only (sync is disabled).
@MainActor
final class WisbeeBackend: InferenceBackend, ObservableObject {
    private var localBackend: LocalBackend?
    private let chatwebLocalBackend: ChatWebLocalBackend

    @Published private(set) var isGenerating = false

    /// Indicates which sub-backend is actively being used
    @Published private(set) var activeSource: WisbeeSource = .local

    var backendId: String { "wisbee" }
    var displayName: String { ChatMode.wisbee.displayName }
    var tokenCost: Int { 0 }

    /// Ready if either local model is loaded or network is available for ChatWeb local mode
    var isReady: Bool {
        (localBackend?.isReady ?? false) || NetworkMonitor.shared.isConnected
    }

    /// Which inference source Wisbee is currently using
    enum WisbeeSource {
        case local       // On-device LLM
        case chatwebLocal // ChatWeb.ai local mode (no cloud processing)

        var displayName: String {
            switch self {
            case .local:
                return String(localized: "wisbee.source.local", defaultValue: "On-device")
            case .chatwebLocal:
                return String(localized: "wisbee.source.chatweb_local", defaultValue: "ChatWeb Local")
            }
        }
    }

    init() {
        chatwebLocalBackend = ChatWebLocalBackend()
    }

    /// Configure the local backend with CoreMLInference
    func configureLocalBackend(_ backend: LocalBackend?) {
        localBackend = backend
    }

    /// Set auth token for the ChatWeb local mode requests
    func setAuthToken(_ token: String?) {
        chatwebLocalBackend.authToken = token
    }

    func generate(
        messages: [Message],
        systemPrompt: String,
        settings: ModelSettings,
        onToken: @escaping (String) -> Void
    ) async throws -> String {
        isGenerating = true
        defer { isGenerating = false }

        // Priority 1: Use local LLM if a model is loaded
        if let local = localBackend, local.isReady {
            activeSource = .local
            return try await local.generate(
                messages: messages,
                systemPrompt: systemPrompt,
                settings: settings,
                onToken: onToken
            )
        }

        // Priority 2: Use ChatWeb.ai with local mode (no cloud fallback)
        if NetworkMonitor.shared.isConnected {
            activeSource = .chatwebLocal
            return try await chatwebLocalBackend.generate(
                messages: messages,
                systemPrompt: systemPrompt,
                settings: settings,
                onToken: onToken
            )
        }

        // Neither available
        throw InferenceError.notReady
    }

    func stopGeneration() {
        localBackend?.stopGeneration()
        chatwebLocalBackend.stopGeneration()
        isGenerating = false
    }
}

// MARK: - ChatWeb Local Mode Backend

/// Internal backend that sends requests to ChatWeb.ai with `mode: "local"`
/// This ensures the server processes the request without sending data to cloud providers.
@MainActor
final class ChatWebLocalBackend {
    private var currentTask: Task<String, Error>?

    var authToken: String?
    private(set) var isGenerating = false

    private let streamURL = "https://api.chatweb.ai/api/v1/chat/stream"

    /// Persistent session ID for Wisbee local mode (separate from regular ChatWeb)
    private var sessionId: String {
        let key = "wisbee_session_id"
        if let existing = UserDefaults.standard.string(forKey: key) {
            return existing
        }
        let newId = "wisbee-\(UUID().uuidString.prefix(12).lowercased())"
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

        guard let lastUserMessage = messages.last(where: { $0.role == .user }) else {
            throw InferenceError.invalidResponse
        }

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

    // MARK: - Private

    private func buildRequest(
        message: String,
        history: [[String: String]],
        systemPrompt: String
    ) throws -> URLRequest {
        var request = URLRequest(url: URL(string: streamURL)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Elio Chat iOS (Wisbee)", forHTTPHeaderField: "User-Agent")

        // Add Bearer token if logged in
        if let token = authToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        var body: [String: Any] = [
            "message": message,
            "session_id": sessionId,
            "channel": "elio",
            "mode": "local",  // Key differentiator: local-only processing
            "history": history
        ]

        if !systemPrompt.isEmpty {
            body["system_prompt"] = systemPrompt
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
            throw InferenceError.serverError(httpResponse.statusCode, "ChatWeb.ai local mode error")
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

    private func processSSEEvent(
        _ json: [String: Any],
        currentResponse: String,
        onToken: @escaping (String) -> Void
    ) -> String {
        var fullResponse = currentResponse
        guard let type = json["type"] as? String else { return fullResponse }

        switch type {
        case "message":
            if let text = json["text"] as? String {
                fullResponse += text
                onToken(text)
            }

        case "content":
            if let content = json["content"] as? String {
                fullResponse += content
                onToken(content)
            }

        case "done":
            // In Wisbee mode we intentionally do not post credit updates
            // to keep the privacy boundary clear
            break

        default:
            break
        }

        return fullResponse
    }
}
