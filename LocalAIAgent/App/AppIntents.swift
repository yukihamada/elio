import AppIntents
import SwiftUI

// MARK: - Ask Elio Intent

/// Siriから「Elioに聞いて」で起動できるインテント
struct AskElioIntent: AppIntent {
    static var title: LocalizedStringResource = "Ask Elio"
    static var description = IntentDescription("Ask Elio a question")
    static var openAppWhenRun: Bool = true

    @Parameter(title: "Question")
    var question: String?

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        // アプリを開いて質問を入力
        if let question = question, !question.isEmpty {
            // 質問がある場合は通知を送る
            NotificationCenter.default.post(
                name: .siriQuestionReceived,
                object: nil,
                userInfo: ["question": question]
            )
            return .result(dialog: "Elioに「\(question)」を聞きます")
        }
        return .result(dialog: "Elioを開きます")
    }
}

// MARK: - Check Schedule Intent

/// 今日の予定を確認するインテント
struct CheckScheduleIntent: AppIntent {
    static var title: LocalizedStringResource = "Check Today's Schedule"
    static var description = IntentDescription("Check your schedule for today")
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        NotificationCenter.default.post(
            name: .siriQuestionReceived,
            object: nil,
            userInfo: ["question": "今日の予定を教えて"]
        )
        return .result(dialog: "今日の予定を確認します")
    }
}

// MARK: - Check Weather Intent

/// 天気を確認するインテント
struct CheckWeatherIntent: AppIntent {
    static var title: LocalizedStringResource = "Check Weather"
    static var description = IntentDescription("Check today's weather")
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        NotificationCenter.default.post(
            name: .siriQuestionReceived,
            object: nil,
            userInfo: ["question": "今日の天気は？"]
        )
        return .result(dialog: "今日の天気を確認します")
    }
}

// MARK: - Create Reminder Intent

/// リマインダーを作成するインテント
struct CreateReminderIntent: AppIntent {
    static var title: LocalizedStringResource = "Create Reminder with Elio"
    static var description = IntentDescription("Create a reminder using Elio")
    static var openAppWhenRun: Bool = true

    @Parameter(title: "Reminder")
    var reminderText: String?

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let question: String
        if let text = reminderText, !text.isEmpty {
            question = "「\(text)」というリマインダーを作成して"
        } else {
            question = "リマインダーを作成"
        }

        NotificationCenter.default.post(
            name: .siriQuestionReceived,
            object: nil,
            userInfo: ["question": question]
        )
        return .result(dialog: "リマインダーを作成します")
    }
}

// MARK: - App Shortcuts Provider

/// Siri Shortcutsに表示されるショートカット
struct ElioShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AskElioIntent(),
            phrases: [
                "Ask \(.applicationName)",
                "\(.applicationName)に聞いて",
                "Elioに質問"
            ],
            shortTitle: "Ask Elio",
            systemImageName: "brain.head.profile"
        )

        AppShortcut(
            intent: CheckScheduleIntent(),
            phrases: [
                "Check my schedule with \(.applicationName)",
                "\(.applicationName)で予定を確認",
                "今日の予定を\(.applicationName)で"
            ],
            shortTitle: "Today's Schedule",
            systemImageName: "calendar"
        )

        AppShortcut(
            intent: CheckWeatherIntent(),
            phrases: [
                "Check weather with \(.applicationName)",
                "\(.applicationName)で天気を確認",
                "天気を\(.applicationName)で"
            ],
            shortTitle: "Weather",
            systemImageName: "cloud.sun"
        )

        AppShortcut(
            intent: CreateReminderIntent(),
            phrases: [
                "Create reminder with \(.applicationName)",
                "\(.applicationName)でリマインダー作成"
            ],
            shortTitle: "Create Reminder",
            systemImageName: "checklist"
        )
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let siriQuestionReceived = Notification.Name("siriQuestionReceived")
}
