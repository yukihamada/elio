//
//  ScreenshotMockData.swift
//  LocalAIAgent
//
//  Mock data for App Store screenshots
//

import Foundation

struct ScreenshotMockData {

    // MARK: - Screenshot Scenario Types
    enum Scenario: String, CaseIterable {
        case schedule = "schedule"
        case code = "code"
        case translation = "translation"
        case travel = "travel"
        case creative = "creative"
        case privacy = "privacy"
    }

    // MARK: - Japanese Mock Conversations

    /// スケジュール管理
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

    /// コーディング支援
    static let japaneseCodeConversation: Conversation = {
        var conversation = Conversation()
        conversation.title = "Swiftコード"
        conversation.messages = [
            Message(
                role: .user,
                content: "SwiftでAPIを呼ぶ方法は？"
            ),
            Message(
                role: .assistant,
                content: """
                📱 **Swift API呼び出し例**

                ```swift
                func fetchData() async throws {
                    let url = URL(string: "https://api.example.com/data")!
                    let (data, _) = try await URLSession.shared.data(from: url)
                    let result = try JSONDecoder().decode(Response.self, from: data)
                }
                ```

                **ポイント**
                • `async/await`で非同期処理
                • `URLSession`でネットワーク通信
                • `Codable`でJSONパース

                実行してみてください！ 💻
                """,
                thinkingContent: "SwiftのモダンなAPI呼び出し方法を説明します。async/awaitを使った例がベストです。"
            )
        ]
        return conversation
    }()

    /// 翻訳・語学学習
    static let japaneseTranslationConversation: Conversation = {
        var conversation = Conversation()
        conversation.title = "英語翻訳"
        conversation.messages = [
            Message(
                role: .user,
                content: "「お疲れ様です」を英語で"
            ),
            Message(
                role: .assistant,
                content: """
                🌐 **「お疲れ様です」の英訳**

                状況に応じて使い分けます：

                **仕事終わり**
                → "Good work today!"
                → "Thanks for your hard work!"

                **メールの挨拶**
                → "Hello," / "Hi,"

                **ねぎらい**
                → "You've done a great job!"

                日本語特有の表現なので、場面で変えましょう 📝
                """
            )
        ]
        return conversation
    }()

    /// 旅行プランニング
    static let japaneseTravelConversation: Conversation = {
        var conversation = Conversation()
        conversation.title = "京都旅行"
        conversation.messages = [
            Message(
                role: .user,
                content: "週末に京都旅行、おすすめは？"
            ),
            Message(
                role: .assistant,
                content: """
                🎋 **週末京都プラン**

                **1日目**
                🏛 伏見稲荷大社（朝イチがおすすめ）
                🍜 錦市場で食べ歩き
                🌸 祇園散策・八坂神社

                **2日目**
                🎍 嵐山・竹林の小径
                🚂 嵯峨野トロッコ列車
                🍵 抹茶スイーツ巡り

                **穴場情報**
                📍 早朝の清水寺は人が少なくて最高！

                素敵な旅を！ ✨
                """,
                thinkingContent: "週末の京都旅行プランを提案します。定番と穴場をバランスよく入れましょう。"
            )
        ]
        return conversation
    }()

    /// クリエイティブ・文章作成
    static let japaneseCreativeConversation: Conversation = {
        var conversation = Conversation()
        conversation.title = "メール作成"
        conversation.messages = [
            Message(
                role: .user,
                content: "上司への報告メールを書いて"
            ),
            Message(
                role: .assistant,
                content: """
                ✉️ **報告メール例**

                ---
                件名：プロジェクトA 進捗報告

                佐藤部長

                お疲れ様です。山田です。

                プロジェクトAの進捗をご報告します。

                **現状**
                ✅ 設計フェーズ完了
                🔄 開発フェーズ 70%完了

                **今後の予定**
                • 来週中にテスト開始
                • 月末リリース予定

                ご確認よろしくお願いいたします。

                山田
                ---

                必要に応じて修正してください！ 📧
                """
            )
        ]
        return conversation
    }()

    /// プライバシー重視（アプリの特徴訴求）
    static let japanesePrivacyConversation: Conversation = {
        var conversation = Conversation()
        conversation.title = "機密相談"
        conversation.messages = [
            Message(
                role: .user,
                content: "転職を考えてるけど誰にも言えない..."
            ),
            Message(
                role: .assistant,
                content: """
                🤫 **安心してください**

                この会話は**完全にプライベート**です。

                • 📱 すべてiPhone内で処理
                • 🚫 サーバー送信なし
                • 🔒 あなただけの秘密

                転職について、何でも相談してください。

                **よくある悩み**
                • 今の仕事の不満
                • 次のキャリアの方向性
                • 面接対策

                一緒に整理していきましょう 💭
                """,
                thinkingContent: "ユーザーがプライベートな相談をしています。ElioChatの最大の特徴である完全オフライン・プライバシー保護をアピールしましょう。"
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

    /// Schedule management
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

    /// Coding assistance
    static let englishCodeConversation: Conversation = {
        var conversation = Conversation()
        conversation.title = "Swift Code"
        conversation.messages = [
            Message(
                role: .user,
                content: "How to make an API call in Swift?"
            ),
            Message(
                role: .assistant,
                content: """
                📱 **Swift API Call Example**

                ```swift
                func fetchData() async throws {
                    let url = URL(string: "https://api.example.com/data")!
                    let (data, _) = try await URLSession.shared.data(from: url)
                    let result = try JSONDecoder().decode(Response.self, from: data)
                }
                ```

                **Key Points**
                • Use `async/await` for async ops
                • `URLSession` for networking
                • `Codable` for JSON parsing

                Give it a try! 💻
                """,
                thinkingContent: "Explaining modern Swift API calling methods. Using async/await is the best approach."
            )
        ]
        return conversation
    }()

    /// Translation
    static let englishTranslationConversation: Conversation = {
        var conversation = Conversation()
        conversation.title = "Translation"
        conversation.messages = [
            Message(
                role: .user,
                content: "How do I say 'thank you' in Japanese?"
            ),
            Message(
                role: .assistant,
                content: """
                🌐 **"Thank you" in Japanese**

                **Casual**
                → ありがとう (Arigatou)

                **Polite**
                → ありがとうございます
                   (Arigatou gozaimasu)

                **Very Formal**
                → 誠にありがとうございます
                   (Makoto ni arigatou gozaimasu)

                **Tip**: In Japan, a slight bow often accompanies thanks! 🙇
                """
            )
        ]
        return conversation
    }()

    /// Travel planning
    static let englishTravelConversation: Conversation = {
        var conversation = Conversation()
        conversation.title = "Tokyo Trip"
        conversation.messages = [
            Message(
                role: .user,
                content: "Planning a weekend trip to Tokyo, any tips?"
            ),
            Message(
                role: .assistant,
                content: """
                🗼 **Tokyo Weekend Guide**

                **Day 1**
                🏯 Senso-ji Temple (Asakusa)
                🛍 Shibuya & Harajuku
                🌃 Tokyo Tower at night

                **Day 2**
                🎮 Akihabara (anime/tech)
                🌸 Ueno Park
                🍣 Tsukiji Outer Market

                **Pro Tips**
                📱 Get a Suica card for trains
                🍜 Try a standing ramen shop
                ⏰ Visit shrines early morning

                Have an amazing trip! ✨
                """,
                thinkingContent: "Planning a Tokyo weekend itinerary with popular spots and insider tips."
            )
        ]
        return conversation
    }()

    /// Creative writing
    static let englishCreativeConversation: Conversation = {
        var conversation = Conversation()
        conversation.title = "Email Draft"
        conversation.messages = [
            Message(
                role: .user,
                content: "Help me write a professional email to my boss"
            ),
            Message(
                role: .assistant,
                content: """
                ✉️ **Professional Email Template**

                ---
                Subject: Project Update - Week 12

                Hi [Boss's Name],

                I wanted to share a quick update on Project Alpha.

                **Progress**
                ✅ Design phase complete
                🔄 Development at 70%

                **Next Steps**
                • Testing begins next week
                • On track for month-end launch

                Let me know if you have any questions.

                Best regards,
                [Your Name]
                ---

                Feel free to customize! 📧
                """
            )
        ]
        return conversation
    }()

    /// Privacy-focused (app feature highlight)
    static let englishPrivacyConversation: Conversation = {
        var conversation = Conversation()
        conversation.title = "Private Chat"
        conversation.messages = [
            Message(
                role: .user,
                content: "I'm thinking about changing jobs but can't tell anyone..."
            ),
            Message(
                role: .assistant,
                content: """
                🤫 **Your Secret is Safe**

                This conversation is **100% private**.

                • 📱 Everything runs on your iPhone
                • 🚫 No data sent to servers
                • 🔒 Only you can see this

                Feel free to share your thoughts about the job change.

                **Common Concerns**
                • Current job frustrations
                • Career direction
                • Interview preparation

                Let's work through this together 💭
                """,
                thinkingContent: "The user is sharing something private. Highlighting ElioChat's key feature - complete offline privacy."
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

    /// Get the screenshot language from launch arguments or environment
    static var screenshotLanguage: String? {
        // Check for explicit language argument: -ScreenshotLanguage ja or -ScreenshotLanguage en
        let args = ProcessInfo.processInfo.arguments
        if let langIndex = args.firstIndex(of: "-ScreenshotLanguage"),
           langIndex + 1 < args.count {
            return args[langIndex + 1]
        }
        // Check environment variable
        if let lang = ProcessInfo.processInfo.environment["SCREENSHOT_LANGUAGE"] {
            return lang
        }
        return nil
    }

    /// Get the screenshot scenario from launch arguments
    static var screenshotScenario: Scenario {
        let args = ProcessInfo.processInfo.arguments
        if let scenarioIndex = args.firstIndex(of: "-ScreenshotScenario"),
           scenarioIndex + 1 < args.count,
           let scenario = Scenario(rawValue: args[scenarioIndex + 1]) {
            return scenario
        }
        return .schedule // default
    }

    static var isJapanese: Bool {
        if let lang = screenshotLanguage {
            return lang.hasPrefix("ja")
        }
        // Fallback to system locale
        return Locale.current.language.languageCode?.identifier == "ja"
    }

    /// Get mock conversation for a specific scenario
    static func getMockConversation(scenario: Scenario) -> Conversation {
        if isJapanese {
            switch scenario {
            case .schedule: return japaneseMockConversation
            case .code: return japaneseCodeConversation
            case .translation: return japaneseTranslationConversation
            case .travel: return japaneseTravelConversation
            case .creative: return japaneseCreativeConversation
            case .privacy: return japanesePrivacyConversation
            }
        } else {
            switch scenario {
            case .schedule: return englishMockConversation
            case .code: return englishCodeConversation
            case .translation: return englishTranslationConversation
            case .travel: return englishTravelConversation
            case .creative: return englishCreativeConversation
            case .privacy: return englishPrivacyConversation
            }
        }
    }

    static func getMockConversation(for locale: Locale = .current) -> Conversation {
        return getMockConversation(scenario: screenshotScenario)
    }

    static func getMockConversations(for locale: Locale = .current) -> [Conversation] {
        if isJapanese {
            return [
                japaneseMockConversation,
                japaneseCodeConversation,
                japaneseTravelConversation,
                japanesePrivacyConversation,
                japaneseCreativeConversation
            ]
        }
        return [
            englishMockConversation,
            englishCodeConversation,
            englishTravelConversation,
            englishPrivacyConversation,
            englishCreativeConversation
        ]
    }

    static func getMockModelName() -> String {
        return "Qwen3 1.7B"
    }
}
