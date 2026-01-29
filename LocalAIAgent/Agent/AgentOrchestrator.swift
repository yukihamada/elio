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

    init(llm: CoreMLInference, mcpClient: MCPClient, modelId: String? = nil) {
        self.llm = llm
        self.mcpClient = mcpClient
        self.modelId = modelId
    }

    func updateModelId(_ modelId: String) {
        self.modelId = modelId
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
        let toolsSchemaJSON = mcpClient.getToolsSchemaJSON(enabledServers: enabledServers)
        let webSearchEnabled = enabledServers.contains("websearch")

        var basePrompt: String
        if isJapanese {
            basePrompt = buildJapaneseSystemPrompt(
                toolsSchemaJSON: toolsSchemaJSON,
                webSearchEnabled: webSearchEnabled
            )
        } else {
            basePrompt = buildEnglishSystemPrompt(
                toolsSchemaJSON: toolsSchemaJSON,
                webSearchEnabled: webSearchEnabled
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
        webSearchEnabled: Bool
    ) -> String {
        // Hermes-style MCP system prompt for Qwen3
        let webSearchNote: String
        if webSearchEnabled && isOnline {
            webSearchNote = "web_searchでWeb検索が可能です。"
        } else if !isOnline {
            webSearchNote = "（オフライン - Web検索は利用不可）"
        } else {
            webSearchNote = "（Web検索は無効）"
        }

        return """
        あなたは親切なアシスタントです。日本語で回答してください。
        \(webSearchNote)
        今日: \(formattedDate())

        # Tools

        You may call one or more functions to assist with the user query.

        You are provided with function signatures within <tools></tools> XML tags:
        <tools>
        \(toolsSchemaJSON)
        </tools>

        For each function call, return a json object with function name and arguments within <tool_call></tool_call> XML tags:
        <tool_call>
        {"name": "<function-name>", "arguments": <args-json-object>}
        </tool_call>

        重要: 最新情報やニュースを聞かれたら、確認せずにすぐweb_searchツールを使用してください。情報を捏造しないでください。
        """
    }

    private func buildEnglishSystemPrompt(
        toolsSchemaJSON: String,
        webSearchEnabled: Bool
    ) -> String {
        // Hermes-style MCP system prompt for Qwen3
        let webSearchNote: String
        if webSearchEnabled && isOnline {
            webSearchNote = "Use web_search for web searches."
        } else if !isOnline {
            webSearchNote = "(Offline - Web search unavailable)"
        } else {
            webSearchNote = "(Web search disabled)"
        }

        return """
        You are a helpful assistant.
        \(webSearchNote)
        Today: \(formattedDate())

        # Tools

        You may call one or more functions to assist with the user query.

        You are provided with function signatures within <tools></tools> XML tags:
        <tools>
        \(toolsSchemaJSON)
        </tools>

        For each function call, return a json object with function name and arguments within <tool_call></tool_call> XML tags:
        <tool_call>
        {"name": "<function-name>", "arguments": <args-json-object>}
        </tool_call>

        IMPORTANT: When asked about current events or news, use web_search immediately without asking for clarification. Do not make up information.
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
                if buffer.contains("<tool_call>") {
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
