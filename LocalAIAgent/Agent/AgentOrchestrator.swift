import Foundation
import Network

@MainActor
final class AgentOrchestrator: ObservableObject {
    @Published private(set) var isProcessing = false
    @Published private(set) var currentStep: AgentStep?
    @Published private(set) var activeAgent: AgentProfile?  // Auto-detected agent for current message

    private let llm: CoreMLInference
    private let mcpClient: MCPClient
    private let appState: AppState // Add AppState dependency
    private let maxIterations = 1  // Single pass only — no tool loop to prevent MainActor hangs
    private var modelId: String?
    private let settingsManager = ModelSettingsManager.shared

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

    enum ModelFamily {
        case qwen3   // Qwen, ElioChat, TinySwallow, Nemotron, DeepSeek-Qwen distills, Jan
        case llama3  // Pure Llama 3.x (non-Japanese fine-tunes only)
        case other   // Gemma, Phi, Granite, ELYZA, Swallow, etc.
    }

    init(llm: CoreMLInference, mcpClient: MCPClient, appState: AppState, modelId: String? = nil) {
        self.llm = llm
        self.mcpClient = mcpClient
        self.appState = appState // Initialize AppState
        self.modelId = modelId
    }

    func updateModelId(_ modelId: String) {
        self.modelId = modelId
    }

    var modelFamily: ModelFamily {
        guard let id = modelId?.lowercased() else { return .other }
        // qwen3 family: Qwen-based models and their fine-tunes
        let isQwen = id.contains("qwen") || id.contains("eliochat") || id.contains("futa") ||
                     id.contains("tinyswallow") || id.contains("nemotron") ||
                     id.contains("jan-nano") || id.contains("rakuten") ||
                     (id.contains("deepseek") && id.contains("qwen"))
        if isQwen { return .qwen3 }
        // llama3 family: pure Llama 3.x only (not elyza/swallow Japanese fine-tunes)
        let isLlama3 = id.contains("llama-3") && !id.contains("elyza") && !id.contains("swallow")
        if isLlama3 { return .llama3 }
        return .other
    }

    private func modelTier() -> ModelTier? {
        guard let id = modelId else { return nil }
        return ModelLoader.shared.getModelInfo(id)?.tier
    }

    /// Filter enabled servers based on model tier to reduce context pressure on small models.
    private func filteredServers(_ enabledServers: Set<String>) -> Set<String> {
        guard let tier = modelTier() else { return enabledServers }
        switch tier {
        case .tiny:
            return []  // No tool calls for tiny models
        case .small:
            return enabledServers.intersection(["websearch", "calendar", "news"])
        case .medium:
            return enabledServers.intersection(["websearch", "calendar", "news", "reminders", "notes", "code_execution"])
        case .large, .xlarge:
            return enabledServers
        }
    }

    func process(
        message: String,
        history: [Message],
        enabledServers: Set<String>
    ) async throws -> String {
        isProcessing = true
        defer { isProcessing = false; activeAgent = nil }

        // LLM-based agent auto-detection
        let agent = detectAgent(for: message)
        activeAgent = agent
        let systemPrompt = buildSystemPrompt(enabledServers: enabledServers, agent: agent)

        var workingHistory = history
        var iteration = 0
        var finalResponse = ""

        while iteration < maxIterations {
            iteration += 1
            currentStep = .thinking

            // Get model settings (with enableThinking for <think> tag support)
            let settings: ModelSettings
            if let modelId = modelId {
                settings = settingsManager.settings(for: modelId)
            } else {
                settings = .default
            }

            var generatedText = ""
            let response = try await llm.generateWithMessages(
                messages: workingHistory,
                systemPrompt: systemPrompt,
                settings: settings
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

                    let toolCall = ToolCall(name: name, arguments: arguments)
                    let assistantMessage = Message(
                        role: .assistant,
                        content: response,
                        toolCalls: [toolCall]
                    )
                    workingHistory.append(assistantMessage)

                    let toolMessage = Message(
                        role: .tool,
                        content: toolResult.content,
                        toolResults: [ToolResult(
                            toolCallId: toolCall.id,
                            content: toolResult.content,
                            isError: toolResult.isError
                        )]
                    )
                    workingHistory.append(toolMessage)

                    // Yield to prevent main actor deadlock, then break to re-invoke LLM
                    await Task.yield()
                    break

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

    // MARK: - Auto Agent Detection (keyword-based)

    /// Fast keyword matching for agent selection. No LLM call needed.
    func detectAgent(for message: String) -> AgentProfile? {
        // If user manually pinned an agent (not default), respect that
        if let selected = AgentManager.shared.selectedAgent,
           AgentManager.shared.selectedAgentId != nil,
           selected.name != "アシスタント" {
            return selected
        }

        let lower = message.lowercased()
        let agents = AgentManager.shared.agents
        let keywords: [(String, [String])] = [
            ("フィットネスコーチ", ["歩数", "心拍", "睡眠", "ワークアウト", "運動", "健康", "体重", "ダイエット"]),
            ("DJ", ["音楽", "曲", "再生", "プレイリスト", "次の曲", "音量"]),
            ("コーダー", ["コード", "バグ", "プログラム", "関数", "エラー", "debug", "swift", "python"]),
            ("翻訳者", ["翻訳", "英訳", "和訳", "英語にして", "日本語にして", "translate"]),
            ("スケジュール管理", ["予定", "カレンダー", "リマインダー", "会議", "スケジュール"]),
            ("リサーチャー", ["調べ", "検索", "最新", "ニュース"]),
            ("料理アシスタント", ["レシピ", "料理", "献立", "食材"]),
            ("データアナリスト", ["計算", "統計", "平均", "集計", "数式"]),
            ("メンタルケア", ["つらい", "悩み", "不安", "ストレス", "落ち込"]),
            ("旅行プランナー", ["旅行", "観光", "ホテル", "フライト"]),
            ("学習チューター", ["勉強", "宿題", "解き方", "微分", "積分"]),
            ("ビジネスメール", ["メール", "議事録", "報告書", "企画書"]),
            ("小説家", ["小説", "物語", "シナリオ", "創作"]),
            ("セキュリティ顧問", ["パスワード", "セキュリティ", "フィッシング", "詐欺"]),
            ("ニュースキャスター", ["今日のニュース", "速報", "時事"]),
        ]

        for (name, words) in keywords {
            if words.filter({ lower.contains($0) }).count >= 2 {
                return agents.first(where: { $0.name == name })
            }
        }
        return nil
    }

    private func buildSystemPrompt(enabledServers: Set<String>, agent: AgentProfile?) -> String {
        let tier = modelTier()
        let filtered = filteredServers(enabledServers)
        let family = modelFamily
        let toolsSchemaJSON: String
        if tier == .tiny || filtered.isEmpty {
            toolsSchemaJSON = ""
        } else {
            toolsSchemaJSON = mcpClient.getToolsSchemaJSON(enabledServers: filtered)
        }
        let webSearchEnabled = filtered.contains("websearch")
        let calendarEnabled = filtered.contains("calendar")

        let agentName = agent?.name ?? "アシスタント"
        print("[AgentOrchestrator] Model: \(modelId ?? "unknown"), tier: \(String(describing: tier)), family: \(family)")
        print("[AgentOrchestrator] Agent: \(agentName) (auto-detected)")
        print("[AgentOrchestrator] Enabled: \(enabledServers) → Filtered: \(filtered)")

        var basePrompt: String
        if isJapanese {
            basePrompt = buildJapaneseSystemPrompt(
                toolsSchemaJSON: toolsSchemaJSON,
                webSearchEnabled: webSearchEnabled,
                calendarEnabled: calendarEnabled,
                tier: tier,
                family: family,
                isParentalControlEnabled: appState.isParentalControlEnabled,
                parentalControlFilterLevel: appState.parentalControlFilterLevel,
                childAge: appState.childAge,
                blockedKeywords: appState.parentalControlBlockedKeywords
            )
        } else {
            basePrompt = buildEnglishSystemPrompt(
                toolsSchemaJSON: toolsSchemaJSON,
                webSearchEnabled: webSearchEnabled,
                calendarEnabled: calendarEnabled,
                tier: tier,
                family: family,
                isParentalControlEnabled: appState.isParentalControlEnabled,
                parentalControlFilterLevel: appState.parentalControlFilterLevel,
                childAge: appState.childAge,
                blockedKeywords: appState.parentalControlBlockedKeywords
            )
        }

        // Append auto-detected agent's prompt
        let agentPrompt = agent?.systemPrompt ?? ""
        if !agentPrompt.isEmpty {
            let agentHeader = isJapanese ? "\n\n# エージェント: \(agentName)\n" : "\n\n# Agent: \(agentName)\n"
            basePrompt += agentHeader + agentPrompt
        }

        // Append custom prompt if set
        if !customSystemPrompt.isEmpty {
            let customHeader = isJapanese ? "\n\n# ユーザー設定の追加指示\n" : "\n\n# User Custom Instructions\n"
            basePrompt += customHeader + customSystemPrompt
        }

        return basePrompt
    }

    private func buildJapaneseSystemPrompt(
        toolsSchemaJSON: String,
        webSearchEnabled: Bool,
        calendarEnabled: Bool,
        tier: ModelTier?,
        family: ModelFamily,
        isParentalControlEnabled: Bool,
        parentalControlFilterLevel: ParentalControlFilterLevel,
        childAge: Int,
        blockedKeywords: [String]
    ) -> String {
        let effectiveTier = tier ?? .large
        let date = formattedDate()

        // --- Tiny or no tools: minimal prompt ---
        if effectiveTier == .tiny || toolsSchemaJSON.isEmpty {
            return """
            あなたは親切なAIアシスタントです。日本語で簡潔に回答してください。
            今日: \(date)
            知らないことは「わかりません」と答えてください。
            """
        }

        // Always use Hermes <tool_call> format — tested to work across all model families.
        // (Llama-3.2's <|python_tag|> requires native chat template, not system prompt instruction)
        let toolCallFormat = """
        <tool_call>
        {"name": "ツール名", "arguments": {"引数名": "値"}}
        </tool_call>
        """

        // --- One-shot example (small/medium, websearch available) ---
        let oneShot: String?
        if effectiveTier <= .medium && webSearchEnabled {
            oneShot = """
            例: ユーザー「最新ニュースは？」→
            <tool_call>
            {"name": "web_search", "arguments": {"query": "最新ニュース"}}
            </tool_call>
            """
        } else {
            oneShot = nil
        }

        // --- Build prompt as sections joined by blank lines ---
        var sections: [String] = []

        // 1. Role + date
        if effectiveTier <= .small {
            sections.append("あなたは親切なAIアシスタントです。日本語で簡潔に回答してください。\n今日: \(date)")
        } else {
            var role = "あなたは親切なAIアシスタントです。日本語で回答してください。"
            if webSearchEnabled && isOnline {
                role += "\nweb_searchツールでWeb検索が可能です。"
            } else if webSearchEnabled && !isOnline {
                role += "\n現在オフラインのためWeb検索は利用できません。"
            }
            role += "\n今日: \(date)"
            sections.append(role)
        }

        // 2. Tools section
        if effectiveTier <= .medium {
            // Compact: skip verbose Hermes preamble to save tokens
            sections.append("# Tools\n<tools>\n\(toolsSchemaJSON)\n</tools>")
        } else {
            sections.append("""
            # Tools

            You may call one or more functions to assist with the user query.

            You are provided with function signatures within <tools></tools> XML tags:
            <tools>
            \(toolsSchemaJSON)
            </tools>
            """)
        }

        // 3. Format instruction
        if effectiveTier <= .medium {
            // Japanese instruction for small models (better compliance)
            sections.append("ツールを使うときは以下の形式で出力してください:\n\(toolCallFormat)")
        } else {
            sections.append("""
            For each function call, return a json object with function name and arguments within <tool_call></tool_call> XML tags:
            <tool_call>
            {"name": "<function-name>", "arguments": <args-json-object>}
            </tool_call>
            """)
        }

        // 4. One-shot example (small/medium only)
        if let example = oneShot {
            sections.append(example)
        }

        // 5. Web search guidance (only when websearch available)
        if webSearchEnabled && isOnline {
            if effectiveTier <= .medium {
                sections.append("最新情報やニュースを聞かれたらすぐweb_searchを使ってください。情報を捏造しないでください。")
            } else {
                sections.append("重要: 最新情報やニュースを聞かれたら、確認せずにすぐweb_searchツールを使用してください。情報を捏造しないでください。")
            }
        }

        // 6. Anti-hallucination guardrail (small only)
        if effectiveTier <= .small {
            sections.append("知らない情報は推測せずツールを使うか「わかりません」と答えてください。")
        }

        // 7. Calendar guidelines (large+ only, when calendar enabled)
        if calendarEnabled && effectiveTier >= .large {
            sections.append("""
            # カレンダー連携ガイドライン
            メッセージに以下のようなイベント情報が含まれている場合、ユーザーにカレンダーへの追加を提案してください:
            - セミナー、勉強会、カンファレンスの案内
            - 会議、ミーティングの日程
            - 予約確認（レストラン、病院、美容院など）
            - 締め切り、提出期限
            - イベント、パーティー、飲み会の誘い

            イベント情報を検出したら:
            1. タイトル、日時、場所、URL、詳細を抽出する
            2. 「カレンダーに追加しますか？」と確認する
            3. ユーザーが同意したら、list_calendarsで利用可能なカレンダーを確認し、適切なカレンダーにcreate_eventで追加する
            4. URLがある場合は必ずurl引数に設定する
            5. 場所がある場合はlocation引数に設定する
            6. 補足情報はnotes引数に含める
            """)
        }

        // 8. Parental control guardrails (only when enabled)
        if isParentalControlEnabled {
            var parentalSection = "# ペアレンタルコントロール\n"
            parentalSection += "子供（\(childAge)歳）が利用しています。以下のガイドラインに従ってください:\n"
            switch parentalControlFilterLevel {
            case .strict:
                parentalSection += "- 暴力的・性的・不適切なコンテンツは一切生成しない\n"
                parentalSection += "- 危険な行為や違法行為を助長しない\n"
                parentalSection += "- 個人情報の収集・共有を求めない\n"
                parentalSection += "- 不適切な話題には「その話題はお答えできません」と丁寧に断る\n"
            case .moderate:
                parentalSection += "- 暴力的・性的なコンテンツは避ける\n"
                parentalSection += "- 危険な行為は注意喚起を添える\n"
                parentalSection += "- 個人情報の共有は最小限に\n"
            case .lenient:
                parentalSection += "- 明らかに有害なコンテンツのみ避ける\n"
            }
            if !blockedKeywords.isEmpty {
                parentalSection += "- 以下のキーワードは使用しない: \(blockedKeywords.joined(separator: ", "))\n"
            }
            sections.append(parentalSection)
        }

        return sections.joined(separator: "\n\n")
    }

    private func buildEnglishSystemPrompt(
        toolsSchemaJSON: String,
        webSearchEnabled: Bool,
        calendarEnabled: Bool,
        tier: ModelTier?,
        family: ModelFamily,
        isParentalControlEnabled: Bool,
        parentalControlFilterLevel: ParentalControlFilterLevel,
        childAge: Int,
        blockedKeywords: [String]
    ) -> String {
        let effectiveTier = tier ?? .large
        let date = formattedDate()

        // --- Tiny or no tools: minimal prompt ---
        if effectiveTier == .tiny || toolsSchemaJSON.isEmpty {
            return """
            You are a helpful AI assistant. Keep your answers concise.
            Today: \(date)
            If you don't know something, say so honestly.
            """
        }

        // Always use Hermes <tool_call> format — tested to work across all model families.
        let toolCallFormat = """
        <tool_call>
        {"name": "tool_name", "arguments": {"key": "value"}}
        </tool_call>
        """

        // --- One-shot example (small/medium, websearch available) ---
        let oneShot: String?
        if effectiveTier <= .medium && webSearchEnabled {
            oneShot = """
            Example: User asks "latest news" →
            <tool_call>
            {"name": "web_search", "arguments": {"query": "latest news"}}
            </tool_call>
            """
        } else {
            oneShot = nil
        }

        // --- Build prompt as sections joined by blank lines ---
        var sections: [String] = []

        // 1. Role + date
        if effectiveTier <= .small {
            sections.append("You are a helpful AI assistant. Keep your answers concise.\nToday: \(date)")
        } else {
            var role = "You are a helpful AI assistant."
            if webSearchEnabled && isOnline {
                role += "\nYou can search the web using the web_search tool."
            } else if webSearchEnabled && !isOnline {
                role += "\nCurrently offline — web search is unavailable."
            }
            role += "\nToday: \(date)"
            sections.append(role)
        }

        // 2. Tools section
        if effectiveTier <= .medium {
            sections.append("# Tools\n<tools>\n\(toolsSchemaJSON)\n</tools>")
        } else {
            sections.append("""
            # Tools

            You may call one or more functions to assist with the user query.

            You are provided with function signatures within <tools></tools> XML tags:
            <tools>
            \(toolsSchemaJSON)
            </tools>
            """)
        }

        // 3. Format instruction
        if effectiveTier <= .medium {
            sections.append("To call a tool, use this format:\n\(toolCallFormat)")
        } else {
            sections.append("""
            For each function call, return a json object with function name and arguments within <tool_call></tool_call> XML tags:
            <tool_call>
            {"name": "<function-name>", "arguments": <args-json-object>}
            </tool_call>
            """)
        }

        // 4. One-shot example (small/medium only)
        if let example = oneShot {
            sections.append(example)
        }

        // 5. Web search guidance (only when websearch available)
        if webSearchEnabled && isOnline {
            if effectiveTier <= .medium {
                sections.append("When asked about current events or news, use web_search immediately. Do not make up information.")
            } else {
                sections.append("IMPORTANT: When asked about current events or news, use web_search immediately without asking for clarification. Do not make up information.")
            }
        }

        // 6. Anti-hallucination guardrail (small only)
        if effectiveTier <= .small {
            sections.append("If unsure, use a tool or say you don't know. Never fabricate information.")
        }

        // 7. Calendar guidelines (large+ only, when calendar enabled)
        if calendarEnabled && effectiveTier >= .large {
            sections.append("""
            # Calendar Integration Guidelines
            When a message contains event-like information, proactively offer to add it to the calendar:
            - Seminars, workshops, conferences
            - Meetings, appointments
            - Reservation confirmations (restaurants, doctors, etc.)
            - Deadlines, due dates
            - Events, parties, social gatherings

            When you detect event information:
            1. Extract title, date/time, location, URL, and details
            2. Ask "Would you like me to add this to your calendar?"
            3. If the user agrees, use list_calendars to check available calendars, then create_event to add it
            4. Always set the url argument if a URL is present
            5. Set the location argument if a venue/address is mentioned
            6. Include supplementary info in the notes argument
            """)
        }

        // 8. Parental control guardrails (only when enabled)
        if isParentalControlEnabled {
            var parentalSection = "# Parental Control\n"
            parentalSection += "A child (\(childAge) years old) is using this. Follow these guidelines:\n"
            switch parentalControlFilterLevel {
            case .strict:
                parentalSection += "- Never generate violent, sexual, or inappropriate content\n"
                parentalSection += "- Do not encourage dangerous or illegal activities\n"
                parentalSection += "- Do not ask to collect or share personal information\n"
                parentalSection += "- Politely decline inappropriate topics with 'I cannot answer that topic'\n"
            case .moderate:
                parentalSection += "- Avoid violent and sexual content\n"
                parentalSection += "- Add warnings for dangerous activities\n"
                parentalSection += "- Minimize personal information sharing\n"
            case .lenient:
                parentalSection += "- Only avoid clearly harmful content\n"
            }
            if !blockedKeywords.isEmpty {
                parentalSection += "- Do not use the following keywords: \(blockedKeywords.joined(separator: ", "))\n"
            }
            sections.append(parentalSection)
        }

        return sections.joined(separator: "\n\n")
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
        defer { isProcessing = false; activeAgent = nil }

        // LLM-based agent auto-detection
        onToolCall("agent:選択中...")
        let agent = detectAgent(for: message)
        activeAgent = agent
        if let agent = agent {
            onToolCall("agent:\(agent.name)")
        } else {
            onToolCall("agent:アシスタント")
        }

        let systemPrompt = buildSystemPrompt(enabledServers: enabledServers, agent: agent)

        print("[AgentOrchestrator] LLM selected agent: \(agent?.name ?? "アシスタント")")
        print("[AgentOrchestrator] User message: \(message.prefix(100))")

        var workingHistory = history
        var iteration = 0
        var finalResponse = ""
        var buffer = ""

        while iteration < maxIterations {
            iteration += 1
            currentStep = .thinking

            // On follow-up iterations (after tool results), clear streamed text
            // so the model generates a fresh response incorporating tool results
            if iteration > 1 {
                finalResponse = ""
                onToolCall("[step:\(iteration)/\(maxIterations)]")
            }

            buffer = ""

            let settings: ModelSettings
            if let modelId = modelId {
                settings = settingsManager.settings(for: modelId)
            } else {
                settings = .default
            }

            var toolCallDetected = false
            var inThinkBlock = false  // Suppress <think>...</think> from stream

            // Simple streaming: pass tokens through, skip <think> and tool_call blocks
            _ = try await llm.generateWithMessages(
                messages: workingHistory,
                systemPrompt: systemPrompt,
                settings: settings
            ) { token in
                buffer += token

                // Suppress tool call blocks
                if buffer.contains("<tool_call>") || buffer.contains("<|python_tag|>") {
                    toolCallDetected = true
                    return
                }
                if toolCallDetected { return }

                // Enter think block
                if token.contains("<think>") { inThinkBlock = true }
                // Exit think block
                if inThinkBlock && token.contains("</think>") {
                    inThinkBlock = false
                    return  // Don't emit the </think> line
                }
                // Suppress everything inside think block
                if inThinkBlock { return }

                onToken(token)
            }

            print("[AgentOrchestrator] Iteration \(iteration) buffer (\(buffer.count) chars): \(String(buffer.prefix(300)))")
            let hasToolCallTag = buffer.contains("<tool_call>")
            print("[AgentOrchestrator] toolCallDetected=\(toolCallDetected), hasToolCallTag=\(hasToolCallTag)")

            let parsedContents = ResponseParser.parse(buffer)
            var hasToolCall = false
            var toolCallProcessed = false

            for content in parsedContents {
                switch content {
                case .text(let text):
                    if !toolCallProcessed {
                        finalResponse += text
                    }

                case .toolCall(let name, let arguments):
                    hasToolCall = true
                    toolCallProcessed = true
                    currentStep = .callingTool(name)
                    onToolCall("tool_start:\(name)")

                    let toolResult = await executeToolCall(
                        name: name,
                        arguments: arguments,
                        enabledServers: enabledServers
                    )

                    // Notify UI of tool result
                    let resultPreview = String(toolResult.content.prefix(200))
                    onToolCall("tool_result:\(name):\(toolResult.isError ? "error" : "ok"):\(resultPreview)")

                    let toolCall = ToolCall(name: name, arguments: arguments)
                    let assistantMessage = Message(
                        role: .assistant,
                        content: buffer,
                        toolCalls: [toolCall]
                    )
                    workingHistory.append(assistantMessage)

                    let toolMessage = Message(
                        role: .tool,
                        content: toolResult.content,
                        toolResults: [ToolResult(
                            toolCallId: toolCall.id,
                            content: toolResult.content,
                            isError: toolResult.isError
                        )]
                    )
                    workingHistory.append(toolMessage)

                    // Yield to prevent main actor starvation, then break to re-invoke LLM
                    await Task.yield()
                    break

                case .thinking:
                    continue
                }
            }

            if !hasToolCall {
                break
            }
        }

        currentStep = nil
        return finalResponse
    }
}
