import Foundation
import Network

@MainActor
final class AgentOrchestrator: ObservableObject {
    @Published private(set) var isProcessing = false
    @Published private(set) var currentStep: AgentStep?

    private let llm: CoreMLInference
    private let mcpClient: MCPClient
    private let maxIterations = 10

    /// Check if device is online (uses NetworkMonitor singleton)
    private var isOnline: Bool {
        NetworkMonitor.shared.isConnected
    }

    enum AgentStep: Equatable {
        case thinking
        case callingTool(String)
        case waitingForResult
        case generating
    }

    init(llm: CoreMLInference, mcpClient: MCPClient) {
        self.llm = llm
        self.mcpClient = mcpClient
    }

    func process(
        message: String,
        history: [Message],
        enabledServers: Set<String>
    ) async throws -> String {
        isProcessing = true
        defer { isProcessing = false }

        let systemPrompt = buildSystemPrompt(enabledServers: enabledServers)

        var workingHistory = history
        var iteration = 0
        var finalResponse = ""

        while iteration < maxIterations {
            iteration += 1
            currentStep = .thinking

            var generatedText = ""
            let response = try await llm.generateWithMessages(
                messages: workingHistory,
                systemPrompt: systemPrompt,
                maxTokens: 2048
            ) { token in
                generatedText += token
            }

            let parsedContents = ResponseParser.parse(response)

            for content in parsedContents {
                switch content {
                case .text(let text):
                    finalResponse += text

                case .toolCall(let name, let arguments):
                    currentStep = .callingTool(name)

                    let toolResult = await executeToolCall(
                        name: name,
                        arguments: arguments,
                        enabledServers: enabledServers
                    )

                    let assistantMessage = Message(
                        role: .assistant,
                        content: response,
                        toolCalls: [ToolCall(name: name, arguments: arguments)]
                    )
                    workingHistory.append(assistantMessage)

                    let toolMessage = Message(
                        role: .tool,
                        content: toolResult.content,
                        toolResults: [ToolResult(
                            toolCallId: assistantMessage.toolCalls!.first!.id,
                            content: toolResult.content,
                            isError: toolResult.isError
                        )]
                    )
                    workingHistory.append(toolMessage)

                    continue

                case .thinking:
                    continue
                }
            }

            let hasToolCall = parsedContents.contains { content in
                if case .toolCall = content { return true }
                return false
            }

            if !hasToolCall {
                break
            }
        }

        currentStep = nil
        return finalResponse.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var currentLocale: Locale { .current }

    private var isJapanese: Bool {
        currentLocale.language.languageCode?.identifier == "ja"
    }

    /// Custom system prompt from UserDefaults (set via Settings)
    private var customSystemPrompt: String {
        UserDefaults.standard.string(forKey: "custom_system_prompt") ?? ""
    }

    private func buildSystemPrompt(enabledServers: Set<String>) -> String {
        let toolsDescription = mcpClient.getToolsDescription(enabledServers: enabledServers, locale: currentLocale)
        let promptsDescription = mcpClient.getPromptsDescription(enabledServers: enabledServers, locale: currentLocale)
        let toolCallFormat = MCPClient.toolCallFormat(locale: currentLocale)

        var basePrompt: String
        if isJapanese {
            basePrompt = buildJapaneseSystemPrompt(
                toolsDescription: toolsDescription,
                promptsDescription: promptsDescription,
                toolCallFormat: toolCallFormat
            )
        } else {
            basePrompt = buildEnglishSystemPrompt(
                toolsDescription: toolsDescription,
                promptsDescription: promptsDescription,
                toolCallFormat: toolCallFormat
            )
        }

        // Append custom prompt if set
        if !customSystemPrompt.isEmpty {
            let customHeader = isJapanese ? "\n\n# ユーザー設定の追加指示\n" : "\n\n# User Custom Instructions\n"
            basePrompt += customHeader + customSystemPrompt
        }

        return basePrompt
    }

    private func buildJapaneseSystemPrompt(
        toolsDescription: String,
        promptsDescription: String,
        toolCallFormat: String
    ) -> String {
        """
        # Elio について
        あなたは「Elio」（エリオ）です。プライバシーを最優先するローカルAIアシスタントとして、ユーザーのデバイス上で完全に動作します。
        - すべての処理はデバイス内で完結し、データは外部に送信されません
        - インターネット接続がなくても基本機能は動作します
        - ユーザーのプライバシーと信頼を守ることが最も重要な使命です

        # 応答スタイル（重要）
        - 回答の冒頭で「素晴らしい質問ですね」「良い質問です」などの褒め言葉を使わない。直接回答する
        - ユーザーの質問スタイルに合わせる：短い質問には簡潔に、詳細な質問には詳しく答える
        - 「分析して」「詳しく」「調査して」と言われたら、複数のツールを使って徹底的に調べる

        # 知識の信頼度による判断
        情報の種類に応じて回答方法を変える：
        1. **永続的事実**（数学、物理法則、歴史的事実）→ 直接回答
        2. **変化する情報**（統計、ランキング、価格）→ 回答 + 「最新情報はghost_searchで確認できます」
        3. **リアルタイム情報**（天気、ニュース、現在の状況）→ 必ずghost_searchを使用

        # 利用可能なツール
        あなたには様々なツールにアクセスする能力があります。

        \(toolsDescription)
        \(promptsDescription)
        \(toolCallFormat)

        # ツール使用のトリガーワード（必ずツールを使う）
        以下のキーワードを検出したら、対応するツールを必ず呼び出す：
        | キーワード | 使用ツール |
        |-----------|-----------|
        | 今日の予定、スケジュール、カレンダー | calendar.get_today_events |
        | リマインダー、タスク、忘れないように | reminders.list_reminders または reminders.create_reminder |
        | 連絡先、電話番号、メールアドレス | contacts.search_contacts |
        | 写真、アルバム、画像 | photos.list_albums, photos.get_recent |
        | 歩数、健康、睡眠、心拍 | health の各ツール |
        | 検索、調べて、最新、ニュース | ghost_search |
        | 場所、現在地、ここはどこ | location.get_current_location |
        | ファイル、ドキュメント | filesystem の各ツール |

        ツールを使わずに「アクセスできません」と答えることは禁止。必ずツールを呼び出す！

        # ツール呼び出しの深さ
        - 単純な質問（「今日の予定は？」）→ 1-2回のツール呼び出し
        - 複合的な質問（「明日の会議の準備を手伝って」）→ 3-5回のツール呼び出し
        - 詳細な分析（「今週の健康状態をまとめて」）→ 5回以上のツール呼び出し

        # 重要なルール
        1. ツールを使用する前に、なぜそのツールが必要かを1文で説明
        2. ツールの結果を受け取ったら、ユーザーに分かりやすく要約
        3. エラーが発生した場合は、何が起きたかを説明し、別の方法を提案
        4. 機密情報（パスワード、APIキーなど）は絶対に表示しない
        5. ユーザーの許可なく、削除や変更などの破壊的な操作は行わない

        # 絶対ルール：知らないことは「知らない」と言う
        **これは最も重要なルールです。**
        - 知らないこと、自信がないことは絶対に推測や創作で答えない
        - 「分かりません」「知りません」「確認が必要です」と正直に言う
        - 嘘や作り話は絶対にしない。誠実さが最優先
        - 特に以下は推測禁止：人名、日付、数値、統計、最新ニュース、専門知識
        - 不確かな場合は「確かではありませんが」と必ず前置きする

        # 検索の活用
        ghost_search を使う場面：
        - 最新のニュースや時事問題
        - 知識のカットオフ日以降の情報
        - 具体的な事実や数値の確認
        - 不確かな情報の検証
        検索結果に基づいて回答し、出典URLを明記する。

        # ネットワーク状態
        \(isOnline ? "オンライン - Web検索が利用可能" : "⚠️ オフラインモード - Web検索は利用不可。ローカル機能とAIの知識のみで回答")

        今日の日付: \(formattedDate())
        """
    }

    private func buildEnglishSystemPrompt(
        toolsDescription: String,
        promptsDescription: String,
        toolCallFormat: String
    ) -> String {
        """
        # About Elio
        You are Elio, a privacy-first local AI assistant that runs entirely on the user's device.
        - All processing happens locally on the device; no data is sent externally
        - Core features work even without internet connection
        - Protecting user privacy and trust is your most important mission

        # Response Style (IMPORTANT)
        - Never start responses with flattery like "Great question!" or "That's interesting!". Answer directly.
        - Match the user's style: short questions get concise answers, detailed questions get thorough responses.
        - When asked to "analyze", "research", or "investigate", use multiple tools for comprehensive results.

        # Knowledge Confidence Levels
        Adjust your response based on information type:
        1. **Timeless facts** (math, physics, historical events) → Answer directly
        2. **Changing information** (statistics, rankings, prices) → Answer + "Use ghost_search to verify latest data"
        3. **Real-time information** (weather, news, current events) → Always use ghost_search first

        # Available Tools
        You have access to various tools to interact with the user's device.

        \(toolsDescription)
        \(promptsDescription)
        \(toolCallFormat)

        # Tool Trigger Keywords (MUST use tools)
        When detecting these keywords, always call the corresponding tool:
        | Keywords | Tool to Use |
        |----------|-------------|
        | schedule, appointments, calendar | calendar.get_today_events |
        | reminders, tasks, don't forget | reminders.list_reminders or reminders.create_reminder |
        | contacts, phone number, email | contacts.search_contacts |
        | photos, albums, pictures | photos.list_albums, photos.get_recent |
        | steps, health, sleep, heart rate | health tools |
        | search, look up, latest, news | ghost_search |
        | location, where am I | location.get_current_location |
        | files, documents | filesystem tools |

        Never say "I can't access" without calling the tool first!

        # Tool Call Depth
        - Simple queries ("What's my schedule today?") → 1-2 tool calls
        - Complex queries ("Help me prepare for tomorrow's meeting") → 3-5 tool calls
        - Deep analysis ("Summarize my health this week") → 5+ tool calls

        # Important Rules
        1. Before using a tool, explain why in one sentence
        2. After receiving tool results, summarize clearly for the user
        3. If an error occurs, explain what happened and suggest alternatives
        4. Never display sensitive information (passwords, API keys, etc.)
        5. Do not perform destructive operations (delete, modify) without user permission

        # Absolute Rule: Say "I don't know" when you don't know
        **This is the most important rule.**
        - Never guess or make up answers for things you don't know or aren't confident about
        - Say "I don't know", "I'm not sure", or "I need to verify" honestly
        - Never lie or fabricate. Honesty is the top priority
        - Especially forbidden to guess: names, dates, numbers, statistics, recent news, specialized knowledge
        - If uncertain, always preface with "I'm not entirely sure, but..."

        # Using Search
        Use ghost_search for:
        - Recent news or current events
        - Information after knowledge cutoff
        - Verifying specific facts or numbers
        - Validating uncertain information
        Base answers on search results and cite source URLs.

        # Network Status
        \(isOnline ? "Online - Web search available" : "⚠️ Offline Mode - Web search unavailable. Use only local features and AI knowledge.")

        Today's date: \(formattedDate())
        """
    }

    // Maximum characters for tool results to prevent context overflow
    private let maxToolResultLength = 3000

    private func executeToolCall(
        name: String,
        arguments: [String: JSONValue],
        enabledServers: Set<String>
    ) async -> (content: String, isError: Bool) {
        do {
            let result = try await mcpClient.callTool(
                fullToolName: name,
                arguments: arguments,
                enabledServers: enabledServers
            )

            var content = mcpClient.formatToolResult(result)

            // Truncate very long results to prevent context overflow
            if content.count > maxToolResultLength {
                let truncated = String(content.prefix(maxToolResultLength))
                content = truncated + (isJapanese ? "\n...(結果が長いため省略)" : "\n...(truncated)")
            }

            return (content, result.isError ?? false)
        } catch {
            return ("ツール実行エラー: \(error.localizedDescription)", true)
        }
    }

    private func formattedDate() -> String {
        let formatter = DateFormatter()
        if isJapanese {
            formatter.locale = Locale(identifier: "ja_JP")
            formatter.dateFormat = "yyyy年M月d日(E)"
        } else {
            formatter.locale = Locale(identifier: "en_US")
            formatter.dateFormat = "EEEE, MMMM d, yyyy"
        }
        return formatter.string(from: Date())
    }
}

extension AgentOrchestrator {
    func processWithStreaming(
        message: String,
        history: [Message],
        enabledServers: Set<String>,
        onToken: @escaping (String) -> Void,
        onToolCall: @escaping (String) -> Void
    ) async throws -> String {
        isProcessing = true
        defer { isProcessing = false }

        let systemPrompt = buildSystemPrompt(enabledServers: enabledServers)

        var workingHistory = history
        var iteration = 0
        var finalResponse = ""
        var buffer = ""

        while iteration < maxIterations {
            iteration += 1
            currentStep = .thinking

            buffer = ""

            _ = try await llm.generateWithMessages(
                messages: workingHistory,
                systemPrompt: systemPrompt,
                maxTokens: 2048
            ) { token in
                buffer += token

                if buffer.contains("<tool_call>") {
                    return
                }

                onToken(token)
            }

            let parsedContents = ResponseParser.parse(buffer)
            var hasToolCall = false

            for content in parsedContents {
                switch content {
                case .text(let text):
                    finalResponse += text

                case .toolCall(let name, let arguments):
                    hasToolCall = true
                    currentStep = .callingTool(name)
                    onToolCall("ツール実行中: \(name)")

                    let toolResult = await executeToolCall(
                        name: name,
                        arguments: arguments,
                        enabledServers: enabledServers
                    )

                    let assistantMessage = Message(
                        role: .assistant,
                        content: buffer,
                        toolCalls: [ToolCall(name: name, arguments: arguments)]
                    )
                    workingHistory.append(assistantMessage)

                    let toolMessage = Message(
                        role: .tool,
                        content: toolResult.content,
                        toolResults: [ToolResult(
                            toolCallId: assistantMessage.toolCalls!.first!.id,
                            content: toolResult.content,
                            isError: toolResult.isError
                        )]
                    )
                    workingHistory.append(toolMessage)

                case .thinking:
                    continue
                }
            }

            if !hasToolCall {
                break
            }
        }

        currentStep = nil
        return finalResponse.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
