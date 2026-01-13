import Foundation
import StoreKit
#if canImport(UIKit)
import UIKit
#endif

/// App Storeレビューを最適なタイミングで促すマネージャー
@MainActor
final class ReviewManager {
    static let shared = ReviewManager()

    // MARK: - UserDefaults Keys
    private enum Keys {
        static let conversationCount = "reviewManager.conversationCount"
        static let positiveRatingCount = "reviewManager.positiveRatingCount"
        static let lastReviewPromptDate = "reviewManager.lastReviewPromptDate"
        static let firstLaunchDate = "reviewManager.firstLaunchDate"
        static let hasPromptedVersion = "reviewManager.hasPromptedVersion"
    }

    // MARK: - Thresholds
    private enum Thresholds {
        static let minConversations = 5           // 最低5回の会話
        static let minPositiveRatings = 2         // 最低2回のGood評価
        static let minDaysSinceFirstLaunch = 3    // 最低3日間の利用
        static let daysBetweenPrompts = 60        // プロンプト間隔（日）
    }

    private init() {
        initializeFirstLaunchIfNeeded()
    }

    // MARK: - Tracking

    /// 会話完了時に呼ぶ
    func recordConversationCompleted() {
        let current = UserDefaults.standard.integer(forKey: Keys.conversationCount)
        UserDefaults.standard.set(current + 1, forKey: Keys.conversationCount)
        logInfo("ReviewManager", "Conversation count: \(current + 1)")

        checkAndPromptIfAppropriate()
    }

    /// ポジティブフィードバック時に呼ぶ
    func recordPositiveRating() {
        let current = UserDefaults.standard.integer(forKey: Keys.positiveRatingCount)
        UserDefaults.standard.set(current + 1, forKey: Keys.positiveRatingCount)
        logInfo("ReviewManager", "Positive rating count: \(current + 1)")

        // ポジティブフィードバック直後は最適なタイミング
        checkAndPromptIfAppropriate(isAfterPositiveFeedback: true)
    }

    // MARK: - Review Logic

    private func checkAndPromptIfAppropriate(isAfterPositiveFeedback: Bool = false) {
        // すでにこのバージョンでプロンプト済みか
        let currentVersion = appVersion
        let promptedVersion = UserDefaults.standard.string(forKey: Keys.hasPromptedVersion)

        if promptedVersion == currentVersion {
            logInfo("ReviewManager", "Already prompted for version \(currentVersion)")
            return
        }

        // 最後のプロンプトからの経過日数
        if let lastPromptDate = UserDefaults.standard.object(forKey: Keys.lastReviewPromptDate) as? Date {
            let daysSinceLastPrompt = Calendar.current.dateComponents([.day], from: lastPromptDate, to: Date()).day ?? 0
            if daysSinceLastPrompt < Thresholds.daysBetweenPrompts {
                logInfo("ReviewManager", "Too soon since last prompt: \(daysSinceLastPrompt) days")
                return
            }
        }

        // 初回起動からの日数
        guard let firstLaunchDate = UserDefaults.standard.object(forKey: Keys.firstLaunchDate) as? Date else {
            return
        }
        let daysSinceFirstLaunch = Calendar.current.dateComponents([.day], from: firstLaunchDate, to: Date()).day ?? 0

        // 会話数とポジティブ評価数
        let conversationCount = UserDefaults.standard.integer(forKey: Keys.conversationCount)
        let positiveRatingCount = UserDefaults.standard.integer(forKey: Keys.positiveRatingCount)

        logInfo("ReviewManager", "Checking conditions", [
            "conversations": "\(conversationCount)",
            "positiveRatings": "\(positiveRatingCount)",
            "daysSinceFirstLaunch": "\(daysSinceFirstLaunch)",
            "isAfterPositiveFeedback": "\(isAfterPositiveFeedback)"
        ])

        // 条件チェック
        let meetsConversationThreshold = conversationCount >= Thresholds.minConversations
        let meetsRatingThreshold = positiveRatingCount >= Thresholds.minPositiveRatings
        let meetsDaysThreshold = daysSinceFirstLaunch >= Thresholds.minDaysSinceFirstLaunch

        // ポジティブフィードバック直後かつ基本条件を満たす場合
        if isAfterPositiveFeedback && meetsConversationThreshold && meetsDaysThreshold {
            promptForReview()
            return
        }

        // 全条件を満たす場合
        if meetsConversationThreshold && meetsRatingThreshold && meetsDaysThreshold {
            promptForReview()
        }
    }

    private func promptForReview() {
        logInfo("ReviewManager", "Prompting for App Store review")

        // 記録を更新
        UserDefaults.standard.set(Date(), forKey: Keys.lastReviewPromptDate)
        UserDefaults.standard.set(appVersion, forKey: Keys.hasPromptedVersion)

        // レビューダイアログを表示
        #if canImport(UIKit)
        if let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }) {
            SKStoreReviewController.requestReview(in: scene)
        }
        #endif
    }

    // MARK: - Helpers

    private func initializeFirstLaunchIfNeeded() {
        if UserDefaults.standard.object(forKey: Keys.firstLaunchDate) == nil {
            UserDefaults.standard.set(Date(), forKey: Keys.firstLaunchDate)
            logInfo("ReviewManager", "First launch date recorded")
        }
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    // MARK: - Debug

    #if DEBUG
    func resetForTesting() {
        UserDefaults.standard.removeObject(forKey: Keys.conversationCount)
        UserDefaults.standard.removeObject(forKey: Keys.positiveRatingCount)
        UserDefaults.standard.removeObject(forKey: Keys.lastReviewPromptDate)
        UserDefaults.standard.removeObject(forKey: Keys.firstLaunchDate)
        UserDefaults.standard.removeObject(forKey: Keys.hasPromptedVersion)
        initializeFirstLaunchIfNeeded()
        logInfo("ReviewManager", "Reset for testing")
    }
    #endif
}
