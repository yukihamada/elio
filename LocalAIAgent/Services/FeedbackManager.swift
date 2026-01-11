import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// フィードバック送信を管理するシングルトン
final class FeedbackManager {
    static let shared = FeedbackManager()

    private let apiEndpoint = "https://elio.love/api/v1/feedback"
    private let userDefaultsKey = "feedbackOptIn"

    private init() {}

    // MARK: - Types

    enum Rating: String, Codable {
        case good, bad
    }

    struct FeedbackPayload: Codable {
        let feedbackId: UUID
        let messageId: UUID
        let conversationId: UUID
        let rating: Rating
        let userMessage: String
        let assistantMessage: String
        let modelName: String
        let deviceInfo: DeviceInfo
        let timestamp: Date
    }

    struct DeviceInfo: Codable {
        let model: String
        let osVersion: String
        let appVersion: String
        let locale: String
    }

    struct FeedbackResponse: Codable {
        let success: Bool
        let feedbackId: UUID?
        let error: FeedbackError?

        struct FeedbackError: Codable {
            let code: String
            let message: String
        }
    }

    enum FeedbackError: Error, LocalizedError {
        case optInRequired
        case networkError(Error)
        case serverError(Int, String?)
        case encodingError

        var errorDescription: String? {
            switch self {
            case .optInRequired:
                return "フィードバック送信の許可が必要です"
            case .networkError(let error):
                return "ネットワークエラー: \(error.localizedDescription)"
            case .serverError(let code, let message):
                return "サーバーエラー (\(code)): \(message ?? "不明")"
            case .encodingError:
                return "データのエンコードに失敗しました"
            }
        }
    }

    // MARK: - User Opt-In

    var isOptedIn: Bool {
        get { UserDefaults.standard.bool(forKey: userDefaultsKey) }
        set { UserDefaults.standard.set(newValue, forKey: userDefaultsKey) }
    }

    // MARK: - Device Info

    private func getDeviceInfo() -> DeviceInfo {
        var systemInfo = utsname()
        uname(&systemInfo)
        let modelCode = withUnsafePointer(to: &systemInfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                String(validatingUTF8: $0) ?? "Unknown"
            }
        }

        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        let buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"

        #if canImport(UIKit)
        let osVersion = UIDevice.current.systemVersion
        #else
        let osVersion = ProcessInfo.processInfo.operatingSystemVersionString
        #endif

        return DeviceInfo(
            model: modelCode,
            osVersion: osVersion,
            appVersion: "\(appVersion).\(buildNumber)",
            locale: Locale.current.identifier
        )
    }

    // MARK: - Submit Feedback

    /// フィードバックを送信
    /// - Parameters:
    ///   - rating: Good or Bad
    ///   - messageId: 対象のメッセージID
    ///   - conversationId: 会話ID
    ///   - userMessage: ユーザーの質問
    ///   - assistantMessage: AIの回答
    ///   - modelName: 使用モデル名
    func submitFeedback(
        rating: Rating,
        messageId: UUID,
        conversationId: UUID,
        userMessage: String,
        assistantMessage: String,
        modelName: String
    ) async throws {
        // オプトインチェック
        guard isOptedIn else {
            logWarning("Feedback", "User not opted in for feedback")
            throw FeedbackError.optInRequired
        }

        let payload = FeedbackPayload(
            feedbackId: UUID(),
            messageId: messageId,
            conversationId: conversationId,
            rating: rating,
            userMessage: userMessage,
            assistantMessage: assistantMessage,
            modelName: modelName,
            deviceInfo: getDeviceInfo(),
            timestamp: Date()
        )

        logInfo("Feedback", "Submitting \(rating.rawValue) feedback", [
            "messageId": messageId.uuidString,
            "model": modelName
        ])

        // APIリクエスト
        guard let url = URL(string: apiEndpoint) else {
            throw FeedbackError.encodingError
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        do {
            request.httpBody = try encoder.encode(payload)
        } catch {
            logError("Feedback", "Failed to encode payload: \(error)")
            throw FeedbackError.encodingError
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw FeedbackError.networkError(URLError(.badServerResponse))
            }

            if (200...299).contains(httpResponse.statusCode) {
                logInfo("Feedback", "Feedback submitted successfully", [
                    "feedbackId": payload.feedbackId.uuidString
                ])
            } else {
                let errorMessage = String(data: data, encoding: .utf8)
                logError("Feedback", "Server returned error", [
                    "statusCode": "\(httpResponse.statusCode)",
                    "response": errorMessage ?? "nil"
                ])
                throw FeedbackError.serverError(httpResponse.statusCode, errorMessage)
            }
        } catch let error as FeedbackError {
            throw error
        } catch {
            logError("Feedback", "Network error: \(error)")
            throw FeedbackError.networkError(error)
        }
    }

    /// フィードバックを非同期で送信（エラーは握りつぶす）
    func submitFeedbackAsync(
        rating: Rating,
        messageId: UUID,
        conversationId: UUID,
        userMessage: String,
        assistantMessage: String,
        modelName: String
    ) {
        Task {
            do {
                try await submitFeedback(
                    rating: rating,
                    messageId: messageId,
                    conversationId: conversationId,
                    userMessage: userMessage,
                    assistantMessage: assistantMessage,
                    modelName: modelName
                )
            } catch {
                // エラーはログに記録済み、UIには影響させない
            }
        }
    }
}
