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

        # 利用可能なツール
        あなたには様々なツールにアクセスする能力があります。ツールを使用することで、カレンダー、連絡先、リマインダー、ファイル、写真などにアクセスできます。

        \(toolsDescription)
        \(promptsDescription)
        \(toolCallFormat)

        # ツールの積極的な使用（重要！）
        あなたはユーザーのデバイスにアクセスできます。以下の質問には必ず対応するツールを使ってください：
        - 「今日の予定」「スケジュール」→ calendar.get_today_events または calendar.get_events を使用
        - 「リマインダー」「タスク」→ reminders.list_reminders を使用
        - 「連絡先」「電話番号」→ contacts.search_contacts を使用
        - 「写真」「アルバム」→ photos.list_albums や photos.get_recent を使用
        - 「歩数」「健康」「睡眠」→ health の各ツールを使用
        - 「検索」「調べて」→ ghost_search を使用

        ツールを使わずに「アクセスできません」と答えないでください。必ずツールを呼び出してください！

        # 重要なルール
        1. ツールを使用する前に、なぜそのツールが必要かを簡潔に説明してください
        2. ツールの結果を受け取ったら、ユーザーに分かりやすく説明してください
        3. エラーが発生した場合は、ユーザーに何が起きたかを説明し、別の方法を提案してください
        4. 機密情報（パスワード、APIキーなど）は絶対に表示しないでください
        5. ユーザーの許可なく、削除や変更などの破壊的な操作は行わないでください

        # 絶対ルール：知らないことは「知らない」と言う
        **これは最も重要なルールです。**
        - 知らないこと、自信がないことは絶対に推測や創作で答えない
        - 「分かりません」「知りません」「確認が必要です」と正直に言う
        - 嘘や作り話は絶対にしない。誠実さが最優先
        - 特に以下は推測禁止：人名、日付、数値、統計、最新ニュース、専門知識
        - 不確かな場合は「確かではありませんが」と必ず前置きする

        # 検索の活用
        以下の場合は ghost_search ツールを使って最新情報を検索してください：
        - 最新のニュースや時事問題について聞かれた場合
        - 現在の日付以降のイベントや情報について
        - 具体的な事実や数値の確認が必要な場合
        - 自信がない情報について確認したい場合
        検索結果に基づいて回答し、出典を明記してください。

        # ネットワーク状態
        \(isOnline ? "オンライン - Web検索が利用可能です" : "⚠️ オフラインモード - Web検索は利用できません。ローカル機能（カレンダー、連絡先、リマインダー、写真、ヘルスデータ）とAIの知識のみで回答してください。")

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

        # Available Tools
        You have access to various tools that allow you to interact with calendars, contacts, reminders, files, photos, and more.

        \(toolsDescription)
        \(promptsDescription)
        \(toolCallFormat)

        # Proactive Tool Usage (IMPORTANT!)
        You have access to the user's device. Always use the appropriate tools for these questions:
        - "today's schedule", "appointments" → use calendar.get_today_events or calendar.get_events
        - "reminders", "tasks" → use reminders.list_reminders
        - "contacts", "phone number" → use contacts.search_contacts
        - "photos", "albums" → use photos.list_albums or photos.get_recent
        - "steps", "health", "sleep" → use health tools
        - "search", "look up" → use ghost_search

        Do NOT say "I can't access" without trying the tools first. Always call the tools!

        # Important Rules
        1. Before using a tool, briefly explain why it's needed
        2. After receiving tool results, explain them clearly to the user
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
        Use the ghost_search tool to look up current information in these cases:
        - When asked about recent news or current events
        - For events or information after your knowledge cutoff
        - When specific facts or numbers need verification
        - When you're uncertain about information
        Base your answers on search results and cite your sources.

        # Network Status
        \(isOnline ? "Online - Web search is available" : "⚠️ Offline Mode - Web search is unavailable. Please respond using only local features (calendar, contacts, reminders, photos, health data) and your knowledge.")

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
