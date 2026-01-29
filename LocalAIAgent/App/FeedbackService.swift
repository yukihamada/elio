import Foundation

/// Service for handling user feedback submission to improve AI quality
@MainActor
final class FeedbackService: ObservableObject {
    static let shared = FeedbackService()

    // MARK: - Published Properties

    @Published var isSubmitting = false
    @Published var lastError: String?

    // MARK: - User Consent

    /// Whether user has consented to send feedback data
    var hasConsented: Bool {
        get { UserDefaults.standard.bool(forKey: "feedback_consent_given") }
        set { UserDefaults.standard.set(newValue, forKey: "feedback_consent_given") }
    }

    /// Whether to ask for consent each time (false = remember consent)
    var askEveryTime: Bool {
        get { UserDefaults.standard.bool(forKey: "feedback_ask_every_time") }
        set { UserDefaults.standard.set(newValue, forKey: "feedback_ask_every_time") }
    }

    // MARK: - API Configuration

    /// Backend API endpoint for feedback submission
    private let feedbackEndpoint = "https://api.elio.love/v1/feedback"

    // MARK: - Initialization

    private init() {}

    // MARK: - Feedback Submission

    /// Submit feedback to the server
    /// - Parameters:
    ///   - type: Feedback type (positive or negative)
    ///   - aiResponse: The AI's response that received feedback
    ///   - userMessage: The user's message that prompted the response
    ///   - conversationId: Optional conversation identifier
    ///   - modelId: The model that generated the response
    ///   - comment: Optional user comment explaining the feedback
    /// - Returns: Whether submission was successful
    @discardableResult
    func submitFeedback(
        type: FeedbackType,
        aiResponse: String,
        userMessage: String?,
        conversationId: String?,
        modelId: String?,
        comment: String? = nil
    ) async -> Bool {
        isSubmitting = true
        lastError = nil

        defer { isSubmitting = false }

        // Prepare feedback data
        let feedbackData = FeedbackData(
            type: type.rawValue,
            aiResponse: aiResponse,
            userMessage: userMessage,
            conversationId: conversationId,
            modelId: modelId,
            comment: comment,
            timestamp: ISO8601DateFormatter().string(from: Date()),
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown",
            locale: Locale.current.identifier
        )

        do {
            // Encode to JSON
            let encoder = JSONEncoder()
            encoder.keyEncodingStrategy = .convertToSnakeCase
            let jsonData = try encoder.encode(feedbackData)

            // Create request
            guard let url = URL(string: feedbackEndpoint) else {
                lastError = "Invalid endpoint URL"
                return false
            }

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("ElioChat-iOS", forHTTPHeaderField: "User-Agent")
            request.httpBody = jsonData
            request.timeoutInterval = 30

            // Send request
            let (_, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                lastError = "Invalid response"
                return false
            }

            if (200...299).contains(httpResponse.statusCode) {
                print("[FeedbackService] Feedback submitted successfully")
                return true
            } else {
                lastError = "Server error: \(httpResponse.statusCode)"
                print("[FeedbackService] Server error: \(httpResponse.statusCode)")
                return false
            }
        } catch {
            lastError = error.localizedDescription
            print("[FeedbackService] Error submitting feedback: \(error)")
            return false
        }
    }

    /// Reset consent (for testing or if user wants to change preference)
    func resetConsent() {
        hasConsented = false
        askEveryTime = false
    }
}

// MARK: - Feedback Types

enum FeedbackType: String, Codable {
    case positive = "positive"
    case negative = "negative"
}

// MARK: - Feedback Data Model

struct FeedbackData: Codable {
    let type: String
    let aiResponse: String
    let userMessage: String?
    let conversationId: String?
    let modelId: String?
    let comment: String?
    let timestamp: String
    let appVersion: String
    let locale: String
}

// MARK: - Consent Information

struct FeedbackConsentInfo {
    static let title = "feedback.consent.title"
    static let message = "feedback.consent.message"

    /// Data categories that will be sent
    static let dataCategories: [(icon: String, titleKey: String, descriptionKey: String)] = [
        ("bubble.left.and.bubble.right", "feedback.data.conversation", "feedback.data.conversation.desc"),
        ("cpu", "feedback.data.model", "feedback.data.model.desc"),
        ("clock", "feedback.data.timestamp", "feedback.data.timestamp.desc")
    ]

    /// Privacy notes
    static let privacyNotes: [String] = [
        "feedback.privacy.anonymous",
        "feedback.privacy.improvement",
        "feedback.privacy.optional"
    ]
}
