//
//  ScreenshotMockData.swift
//  LocalAIAgent
//
//  Mock data for App Store screenshots
//

import Foundation

struct ScreenshotMockData {

    // MARK: - Japanese Mock Conversations

    static let japaneseMockConversation: Conversation = {
        var conversation = Conversation()
        conversation.title = "今日の予定"
        conversation.messages = [
            Message(
                role: .user,
                content: "今日の予定を教えて"
            ),
            Message(
                role: .assistant,
                content: """
                今日の予定を確認しました！

                📅 **本日のスケジュール**

                • **10:00** - チームミーティング
                • **12:00** - ランチ（田中さんと）
                • **14:00** - プロジェクト進捗確認
                • **16:00** - クライアント電話

                素敵な一日をお過ごしください！ ☀️
                """,
                thinkingContent: "ユーザーが今日の予定を知りたいので、カレンダーを確認して分かりやすく整理します。"
            ),
            Message(
                role: .user,
                content: "14時の会議をリマインドして"
            ),
            Message(
                role: .assistant,
                content: """
                ✅ リマインダーを設定しました！

                **プロジェクト進捗確認**
                🕐 今日 13:45（15分前通知）

                会議の準備は万端ですか？
                """
            )
        ]
        return conversation
    }()

    static let japaneseMockConversation2: Conversation = {
        var conversation = Conversation()
        conversation.title = "天気予報"
        conversation.messages = [
            Message(
                role: .user,
                content: "今日の天気は？"
            ),
            Message(
                role: .assistant,
                content: """
                🌤️ **東京の天気**

                **現在**: 晴れ 22°C
                **最高**: 25°C / **最低**: 18°C

                午後から少し雲が出てきますが、傘は必要なさそうです。

                お出かけ日和ですね！
                """
            )
        ]
        return conversation
    }()

    static let japaneseMockConversation3: Conversation = {
        var conversation = Conversation()
        conversation.title = "レシピ提案"
        conversation.messages = [
            Message(
                role: .user,
                content: "簡単な夕食のレシピを教えて"
            ),
            Message(
                role: .assistant,
                content: """
                🍳 **15分でできる親子丼**

                **材料（2人分）**
                • 鶏もも肉 200g
                • 玉ねぎ 1/2個
                • 卵 3個
                • めんつゆ 大さじ3

                **作り方**
                1. 鶏肉と玉ねぎを一口大に切る
                2. フライパンでめんつゆと煮る
                3. 溶き卵を回し入れて蓋をする
                4. ご飯にのせて完成！

                お試しください 😊
                """
            )
        ]
        return conversation
    }()

    // MARK: - English Mock Conversations

    static let englishMockConversation: Conversation = {
        var conversation = Conversation()
        conversation.title = "Today's Schedule"
        conversation.messages = [
            Message(
                role: .user,
                content: "What's on my schedule today?"
            ),
            Message(
                role: .assistant,
                content: """
                I've checked your calendar!

                📅 **Today's Schedule**

                • **10:00 AM** - Team Meeting
                • **12:00 PM** - Lunch with Sarah
                • **2:00 PM** - Project Review
                • **4:00 PM** - Client Call

                Have a productive day! ☀️
                """,
                thinkingContent: "The user wants to know their schedule. Let me check the calendar and organize it clearly."
            ),
            Message(
                role: .user,
                content: "Remind me about the 2 PM meeting"
            ),
            Message(
                role: .assistant,
                content: """
                ✅ Reminder set!

                **Project Review**
                🕐 Today at 1:45 PM (15 min before)

                Are you all set for the meeting?
                """
            )
        ]
        return conversation
    }()

    static let englishMockConversation2: Conversation = {
        var conversation = Conversation()
        conversation.title = "Weather"
        conversation.messages = [
            Message(
                role: .user,
                content: "What's the weather like today?"
            ),
            Message(
                role: .assistant,
                content: """
                🌤️ **San Francisco Weather**

                **Current**: Sunny 72°F
                **High**: 77°F / **Low**: 64°F

                Some clouds expected in the afternoon, but no umbrella needed.

                Perfect day to go outside!
                """
            )
        ]
        return conversation
    }()

    static let englishMockConversation3: Conversation = {
        var conversation = Conversation()
        conversation.title = "Recipe Ideas"
        conversation.messages = [
            Message(
                role: .user,
                content: "Quick dinner recipe ideas?"
            ),
            Message(
                role: .assistant,
                content: """
                🍳 **15-Minute Stir-Fry**

                **Ingredients**
                • Chicken breast 200g
                • Mixed vegetables
                • Soy sauce 2 tbsp
                • Garlic 2 cloves

                **Steps**
                1. Slice chicken into strips
                2. Stir-fry with garlic
                3. Add vegetables
                4. Season with soy sauce
                5. Serve over rice!

                Enjoy your meal! 😊
                """
            )
        ]
        return conversation
    }()

    // MARK: - Helper Methods

    static func getMockConversation(for locale: Locale = .current) -> Conversation {
        if locale.language.languageCode?.identifier == "ja" {
            return japaneseMockConversation
        }
        return englishMockConversation
    }

    static func getMockConversations(for locale: Locale = .current) -> [Conversation] {
        if locale.language.languageCode?.identifier == "ja" {
            return [japaneseMockConversation, japaneseMockConversation2, japaneseMockConversation3]
        }
        return [englishMockConversation, englishMockConversation2, englishMockConversation3]
    }

    static func getMockModelName() -> String {
        return "Qwen3 1.7B"
    }
}
