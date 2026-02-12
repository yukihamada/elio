import Foundation

/// Protocol for all inference backends (Local, Cloud, P2P)
@MainActor
protocol InferenceBackend: AnyObject {
    /// Unique identifier for this backend
    var backendId: String { get }

    /// Display name for UI
    var displayName: String { get }

    /// Token cost per message (0 for local)
    var tokenCost: Int { get }

    /// Whether this backend is ready to use
    var isReady: Bool { get }

    /// Whether the backend is currently generating
    var isGenerating: Bool { get }

    /// Generate a response from messages with streaming
    /// - Parameters:
    ///   - messages: Conversation history
    ///   - systemPrompt: System prompt for the model
    ///   - settings: Model generation settings
    ///   - onToken: Callback for each token as it's generated
    /// - Returns: Complete generated response
    func generate(
        messages: [Message],
        systemPrompt: String,
        settings: ModelSettings,
        onToken: @escaping (String) -> Void
    ) async throws -> String

    /// Stop any ongoing generation
    func stopGeneration()
}

/// Errors that can occur during inference
enum InferenceError: Error, LocalizedError {
    case notReady
    case apiKeyMissing
    case networkError(String)
    case rateLimited
    case insufficientTokens
    case cancelled
    case invalidResponse
    case serverError(Int, String)

    var errorDescription: String? {
        switch self {
        case .notReady:
            return String(localized: "error.backend.not.ready", defaultValue: "Backend not ready")
        case .apiKeyMissing:
            return String(localized: "error.api.key.missing", defaultValue: "API key not configured")
        case .networkError(let message):
            return String(localized: "error.network", defaultValue: "Network error: \(message)")
        case .rateLimited:
            return String(localized: "error.rate.limited", defaultValue: "Rate limited. Please try again later.")
        case .insufficientTokens:
            return String(localized: "error.insufficient.tokens", defaultValue: "Insufficient tokens")
        case .cancelled:
            return String(localized: "error.cancelled", defaultValue: "Generation cancelled")
        case .invalidResponse:
            return String(localized: "error.invalid.response", defaultValue: "Invalid response from server")
        case .serverError(let code, let message):
            return String(localized: "error.server", defaultValue: "Server error (\(code)): \(message)")
        }
    }
}
