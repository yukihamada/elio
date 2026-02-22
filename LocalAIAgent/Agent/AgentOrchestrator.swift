import Foundation
import Network

@MainActor
final class AgentOrchestrator: ObservableObject {
    @Published private(set) var isProcessing = false
    @Published private(set) var currentStep: AgentStep?

    private let llm: CoreMLInference
    private let mcpClient: MCPClient
    private let maxIterations = 10
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

    init(llm: CoreMLInference, mcpClient: MCPClient, modelId: String? = nil) {
        self.llm = llm
        self.mcpClient = mcpClient
        self.modelId = modelId
    }

    func updateModelId(_ modelId: String) {
        self.modelId = modelId
    }

    var modelFamily: ModelFamily {
        guard let id = modelId?.lowercased() else { return .other }
        // qwen3 family: Qwen-based models and their fine-tunes
        let isQwen = id.contains("qwen") || id.contains("eliochat") ||
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
            return enabledServers.intersection(["websearch", "calendar", "news", "reminders", "notes"])
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
        defer { isProcessing = false }

        let systemPrompt = buildSystemPrompt(enabledServers: enabledServers)

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

                    // HOTFIX: Return tool result immediately to prevent freeze
                    // TODO: Re-enable multi-turn conversation after fixing the freeze issue
                    currentStep = nil
                    return toolResult.content.trimmingCharacters(in: .whitespacesAndNewlines)

                    // Original code (disabled):
                    // let assistantMessage = Message(
                    //     role: .assistant,
                    //     content: response,
                    //     toolCalls: [ToolCall(name: name, arguments: arguments)]
                    // )
                    // workingHistory.append(assistantMessage)
                    //
                    // let toolMessage = Message(
                    //     role: .tool,
                    //     content: toolResult.content,
                    //     toolResults: [ToolResult(
                    //         toolCallId: assistantMessage.toolCalls!.first!.id,
                    //         content: toolResult.content,
                    //         isError: toolResult.isError
                    //     )]
                    // )
                    // workingHistory.append(toolMessage)
                    //
                    // continue

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

        print("[AgentOrchestrator] Model: \(modelId ?? "unknown"), tier: \(String(describing: tier)), family: \(family)")
        print("[AgentOrchestrator] Enabled: \(enabledServers) → Filtered: \(filtered)")

        var basePrompt: String
        if isJapanese {
            basePrompt = buildJapaneseSystemPrompt(
                toolsSchemaJSON: toolsSchemaJSON,
                webSearchEnabled: webSearchEnabled,
                calendarEnabled: calendarEnabled,
                tier: tier,
                family: family
            )
        } else {
            basePrompt = buildEnglishSystemPrompt(
                toolsSchemaJSON: toolsSchemaJSON,
                webSearchEnabled: webSearchEnabled,
                calendarEnabled: calendarEnabled,
                tier: tier,
                family: family
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
        toolsSchemaJSON: String,
        webSearchEnabled: Bool,
        calendarEnabled: Bool,
        tier: ModelTier?,
        family: ModelFamily
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

        return sections.joined(separator: "\n\n")
    }

    private func buildEnglishSystemPrompt(
        toolsSchemaJSON: String,
        webSearchEnabled: Bool,
        calendarEnabled: Bool,
        tier: ModelTier?,
        family: ModelFamily
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
        defer { isProcessing = false }

        let systemPrompt = buildSystemPrompt(enabledServers: enabledServers)

        // Debug: Log enabled servers and web search status
        print("[AgentOrchestrator] Enabled servers: \(enabledServers)")
        print("[AgentOrchestrator] Web search enabled: \(enabledServers.contains("websearch"))")
        print("[AgentOrchestrator] Is online: \(isOnline)")
        print("[AgentOrchestrator] User message: \(message.prefix(100))")

        var workingHistory = history
        var iteration = 0
        var finalResponse = ""
        var buffer = ""

        while iteration < maxIterations {
            iteration += 1
            currentStep = .thinking

            buffer = ""

            // Get model settings (with enableThinking for <think> tag support)
            let settings: ModelSettings
            if let modelId = modelId {
                settings = settingsManager.settings(for: modelId)
            } else {
                settings = .default
            }

            var toolCallDetected = false

            _ = try await llm.generateWithMessages(
                messages: workingHistory,
                systemPrompt: systemPrompt,
                settings: settings
            ) { token in
                buffer += token

                // Stop streaming to UI if tool call is detected (either format)
                if buffer.contains("<tool_call>") || buffer.contains("<|python_tag|>") {
                    toolCallDetected = true
                    return
                }

                // Also detect bare JSON tool calls (for smaller models)
                // Look for pattern like {"name": "...", "arguments": ...}
                if buffer.contains("\"name\"") && buffer.contains("\"arguments\"") && buffer.contains("}") {
                    // Check if we have a complete JSON object
                    if buffer.lastIndex(of: "}") != nil {
                        let afterThink = buffer.range(of: "</think>").map { String(buffer[$0.upperBound...]) } ?? buffer
                        if afterThink.contains("{") && afterThink.contains("}") {
                            toolCallDetected = true
                            return
                        }
                    }
                }

                if !toolCallDetected {
                    onToken(token)
                }
            }

            // Debug: Log raw model output to check if tool calls are being generated
            print("[AgentOrchestrator] Raw buffer (first 500 chars): \(String(buffer.prefix(500)))")
            print("[AgentOrchestrator] Tool call detected during streaming: \(toolCallDetected)")
            if buffer.contains("<tool_call>") {
                print("[AgentOrchestrator] Found <tool_call> tag!")
            }
            if buffer.contains("<|python_tag|>") {
                print("[AgentOrchestrator] Found <|python_tag|> token (Llama3 format)!")
            }
            if buffer.contains("\"name\"") && buffer.contains("\"arguments\"") {
                print("[AgentOrchestrator] Found bare JSON tool call pattern!")
            }

            let parsedContents = ResponseParser.parse(buffer)
            var hasToolCall = false
            var toolCallProcessed = false

            for content in parsedContents {
                switch content {
                case .text(let text):
                    // If we've already processed a tool call, ignore any text after it
                    // (small models may hallucinate responses instead of waiting for tool results)
                    if !toolCallProcessed {
                        finalResponse += text
                    }

                case .toolCall(let name, let arguments):
                    hasToolCall = true
                    toolCallProcessed = true
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

                    // HOTFIX: Return tool result immediately to prevent freeze
                    currentStep = nil
                    return toolResult.content.trimmingCharacters(in: .whitespacesAndNewlines)

                    // Original code (disabled):
                    // let toolMessage = Message(
                    //     role: .tool,
                    //     content: toolResult.content,
                    //     toolResults: [ToolResult(
                    //         toolCallId: assistantMessage.toolCalls!.first!.id,
                    //         content: toolResult.content,
                    //         isError: toolResult.isError
                    //     )]
                    // )
                    // workingHistory.append(toolMessage)

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
