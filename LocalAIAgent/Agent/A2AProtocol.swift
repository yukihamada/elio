import Foundation

// MARK: - A2A (Agent-to-Agent) Protocol
// Each agent is an independent reasoning unit. The router agent semantically
// selects the best specialist and delegates via A2A messages. Agents can also
// delegate sub-tasks to other agents, forming a multi-agent pipeline.

/// A2A message passed between agents (JSON-RPC 2.0 inspired)
struct A2AMessage: Codable {
    let id: UUID
    let from: String      // Source agent name
    let to: String        // Target agent name
    let method: String    // "query" | "delegate" | "respond"
    let content: String   // User message or sub-task
    let context: [String: String]?  // Extra context (prior agent results, etc.)
    let timestamp: Date

    init(from: String, to: String, method: String = "query", content: String, context: [String: String]? = nil) {
        self.id = UUID()
        self.from = from
        self.to = to
        self.method = method
        self.content = content
        self.context = context
        self.timestamp = Date()
    }
}

/// Result from an agent execution
struct A2AResult {
    let agentName: String
    let content: String
    let toolsUsed: [String]
    let delegatedTo: [String]  // Names of agents this agent further delegated to
    let duration: TimeInterval
}

/// Agent execution trace for UI display
struct AgentTrace: Identifiable {
    let id = UUID()
    let agentName: String
    let agentIcon: String
    let agentColor: String
    let status: TraceStatus
    let detail: String
    let timestamp: Date

    enum TraceStatus: String {
        case routing = "routing"
        case running = "running"
        case toolCall = "tool"
        case delegating = "delegating"
        case completed = "completed"
        case error = "error"
    }
}

// MARK: - Agent Runner

/// Runs a single agent with its own system prompt, tools, and settings.
/// Stateless — each invocation is independent.
@MainActor
final class AgentRunner {
    private let llm: CoreMLInference
    private let mcpClient: MCPClient
    private let settingsManager = ModelSettingsManager.shared
    var modelId: String?

    init(llm: CoreMLInference, mcpClient: MCPClient, modelId: String? = nil) {
        self.llm = llm
        self.mcpClient = mcpClient
        self.modelId = modelId
    }

    /// Execute an agent with the given profile and message
    func run(
        agent: AgentProfile,
        message: String,
        history: [Message],
        enabledServers: Set<String>,
        priorContext: String? = nil,
        onToken: @escaping (String) -> Void,
        onTrace: @escaping (AgentTrace) -> Void
    ) async throws -> A2AResult {
        let startTime = Date()
        var toolsUsed: [String] = []

        onTrace(AgentTrace(
            agentName: agent.name,
            agentIcon: agent.icon,
            agentColor: agent.colorHex,
            status: .running,
            detail: "推論開始",
            timestamp: Date()
        ))

        // Build agent-specific system prompt
        let systemPrompt = buildAgentPrompt(agent: agent, enabledServers: enabledServers, priorContext: priorContext)

        // Determine tools for this agent
        let agentServers: Set<String>
        if let tools = agent.enabledTools {
            agentServers = enabledServers.intersection(tools)
        } else {
            agentServers = enabledServers
        }

        // Get settings — use agent's temperature if set
        var settings: ModelSettings
        if let modelId = modelId {
            settings = settingsManager.settings(for: modelId)
        } else {
            settings = .default
        }
        if let temp = agent.temperature {
            settings.temperature = Float(temp)
        }

        // Run inference loop (with tool calling)
        var workingHistory = history
        var finalResponse = ""
        var buffer = ""
        let maxIterations = 5

        for _ in 1...maxIterations {
            buffer = ""
            var toolCallDetected = false

            _ = try await llm.generateWithMessages(
                messages: workingHistory,
                systemPrompt: systemPrompt,
                settings: settings
            ) { token in
                buffer += token
                if buffer.contains("<tool_call>") || buffer.contains("<|python_tag|>") {
                    toolCallDetected = true
                    return
                }
                if !toolCallDetected {
                    onToken(token)
                }
            }

            let parsedContents = ResponseParser.parse(buffer)
            var hasToolCall = false

            for content in parsedContents {
                switch content {
                case .text(let text):
                    if !hasToolCall { finalResponse += text }

                case .toolCall(let name, let arguments):
                    hasToolCall = true
                    toolsUsed.append(name)

                    onTrace(AgentTrace(
                        agentName: agent.name,
                        agentIcon: agent.icon,
                        agentColor: agent.colorHex,
                        status: .toolCall,
                        detail: name,
                        timestamp: Date()
                    ))

                    let toolResult = await executeToolCall(name: name, arguments: arguments, enabledServers: agentServers)

                    let toolCall = ToolCall(name: name, arguments: arguments)
                    workingHistory.append(Message(role: .assistant, content: buffer, toolCalls: [toolCall]))
                    workingHistory.append(Message(role: .tool, content: toolResult.content,
                        toolResults: [ToolResult(toolCallId: toolCall.id, content: toolResult.content, isError: toolResult.isError)]))
                    await Task.yield()
                    break

                case .thinking:
                    continue
                }
            }

            if !hasToolCall { break }
        }

        let duration = Date().timeIntervalSince(startTime)

        onTrace(AgentTrace(
            agentName: agent.name,
            agentIcon: agent.icon,
            agentColor: agent.colorHex,
            status: .completed,
            detail: String(format: "%.1fs", duration),
            timestamp: Date()
        ))

        return A2AResult(
            agentName: agent.name,
            content: finalResponse,
            toolsUsed: toolsUsed,
            delegatedTo: [],
            duration: duration
        )
    }

    // MARK: - Private

    private func buildAgentPrompt(agent: AgentProfile, enabledServers: Set<String>, priorContext: String?) -> String {
        // Only include tools the agent actually uses (keep prompt small)
        let agentServers: Set<String>
        if let tools = agent.enabledTools, !tools.isEmpty {
            agentServers = tools  // Agent-specific tools only
        } else {
            agentServers = []  // No tool schema = much shorter prompt
        }

        var prompt = "あなたは「\(agent.name)」です。"
        if !agent.description.isEmpty {
            prompt += agent.description
        }
        prompt += "\n"

        if !agent.systemPrompt.isEmpty {
            prompt += agent.systemPrompt + "\n"
        }

        // Only include tool schemas for agents that explicitly use tools
        if !agentServers.isEmpty {
            let toolsJSON = mcpClient.getToolsSchemaJSON(enabledServers: agentServers)
            if !toolsJSON.isEmpty {
                prompt += "\n# ツール\n\(toolsJSON)\n"
                prompt += "<tool_call>{\"name\":\"...\",\"arguments\":{...}}</tool_call>の形式で呼び出し。\n"
            }
        }

        if let ctx = priorContext {
            prompt += "\n# 引き継ぎ\n\(ctx)\n"
        }

        return prompt
    }

    private func executeToolCall(name: String, arguments: [String: JSONValue], enabledServers: Set<String>) async -> (content: String, isError: Bool) {
        do {
            let result = try await mcpClient.callTool(fullToolName: name, arguments: arguments, enabledServers: enabledServers)
            let text = result.content?.compactMap(\.text).joined(separator: "\n") ?? ""
            return (text, result.isError ?? false)
        } catch {
            return ("[TOOL_ERROR] \(error.localizedDescription)", true)
        }
    }
}

// MARK: - A2A Router

/// The router agent semantically selects which specialist agent(s) to invoke.
/// Can chain agents: Router → Agent A → (delegates to) Agent B → final response
@MainActor
final class A2ARouter: ObservableObject {
    @Published private(set) var traces: [AgentTrace] = []
    @Published private(set) var activeAgents: [String] = []

    private let llm: CoreMLInference
    private let mcpClient: MCPClient
    private let runner: AgentRunner
    private var modelId: String?

    init(llm: CoreMLInference, mcpClient: MCPClient, modelId: String? = nil) {
        self.llm = llm
        self.mcpClient = mcpClient
        self.runner = AgentRunner(llm: llm, mcpClient: mcpClient, modelId: modelId)
        self.modelId = modelId
    }

    func updateModelId(_ modelId: String) {
        self.modelId = modelId
        self.runner.modelId = modelId
    }

    /// Route a message through the A2A system
    func route(
        message: String,
        history: [Message],
        enabledServers: Set<String>,
        onToken: @escaping (String) -> Void,
        onToolCall: @escaping (String) -> Void
    ) async throws -> String {
        traces = []
        activeAgents = []

        let agents = AgentManager.shared.agents

        // Agent selection: use fast keyword matching (LLM classification disabled —
        // same llm context can't run 2 sequential inferences without reload)
        let agent = keywordFallback(message: message, agents: agents) ?? agents.first!

        onToolCall("agent:\(agent.name)")
        activeAgents = [agent.name]

        traces.append(AgentTrace(
            agentName: "Router",
            agentIcon: "arrow.triangle.branch",
            agentColor: "#6366F1",
            status: .routing,
            detail: "→ \(agent.name)",
            timestamp: Date()
        ))

        // Step 2: Run the selected agent
        let result = try await runner.run(
            agent: agent,
            message: message,
            history: history,
            enabledServers: enabledServers,
            onToken: onToken,
            onTrace: { [weak self] trace in
                self?.traces.append(trace)
                onToolCall("agent_trace:\(trace.agentName):\(trace.status.rawValue):\(trace.detail)")
            }
        )

        // Step 3: Check if the agent wants to delegate to another agent
        // (Detected by special pattern in response: @delegate(AgentName) reason)
        if let delegation = parseDelegation(from: result.content) {
            if let delegateAgent = agents.first(where: { $0.name == delegation.targetAgent }) {
                onToolCall("agent_delegate:\(agent.name)→\(delegateAgent.name)")
                activeAgents.append(delegateAgent.name)

                traces.append(AgentTrace(
                    agentName: agent.name,
                    agentIcon: agent.icon,
                    agentColor: agent.colorHex,
                    status: .delegating,
                    detail: "→ \(delegateAgent.name): \(delegation.reason)",
                    timestamp: Date()
                ))

                // Clear streamed tokens from first agent before delegate streams
                onToken("\n\n---\n**\(delegateAgent.name)** に引き継ぎます...\n\n")

                let delegateResult = try await runner.run(
                    agent: delegateAgent,
                    message: message,
                    history: history,
                    enabledServers: enabledServers,
                    priorContext: "前のエージェント「\(agent.name)」の分析結果:\n\(delegation.content)",
                    onToken: onToken,
                    onTrace: { [weak self] trace in
                        self?.traces.append(trace)
                        onToolCall("agent_trace:\(trace.agentName):\(trace.status.rawValue):\(trace.detail)")
                    }
                )

                return delegateResult.content
            }
        }

        return result.content
    }

    // MARK: - Semantic Agent Selection

    private func selectAgent(message: String, agents: [AgentProfile]) async -> AgentProfile? {
        // For tiny/small models, use keyword fallback (too slow for LLM classification)
        let tier = modelId.flatMap { ModelLoader.shared.getModelInfo($0)?.tier }
        if tier == .tiny || tier == .small {
            return keywordFallback(message: message, agents: agents)
        }

        // Build compact agent list for LLM
        let agentList = agents.map { "- \($0.name)" }.joined(separator: "\n")

        let classifierPrompt = """
        Select one agent name for this message. Output ONLY the name, nothing else.
        Agents:
        \(agentList)
        Default: アシスタント
        """

        let settings = ModelSettings(
            temperature: 0.1, topP: 0.9, topK: 40, maxTokens: 20,
            repeatPenalty: 1.0, enableThinking: false, systemPrompt: "",
            kvCacheTypeK: .q8_0, kvCacheTypeV: .q4_0
        )

        var result = ""
        do {
            _ = try await llm.generateWithMessages(
                messages: [Message(role: .user, content: message)],
                systemPrompt: classifierPrompt,
                settings: settings
            ) { token in result += token }
        } catch {
            return nil
        }

        let cleaned = result.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "「", with: "")
            .replacingOccurrences(of: "」", with: "")

        print("[A2ARouter] LLM selected: \"\(cleaned)\"")

        if let match = agents.first(where: { cleaned.contains($0.name) }) {
            return match.name == "アシスタント" ? nil : match
        }
        return nil
    }

    /// Fast keyword fallback for small models
    private func keywordFallback(message: String, agents: [AgentProfile]) -> AgentProfile? {
        let lower = message.lowercased()
        let keywords: [(String, [String])] = [
            ("フィットネスコーチ", ["歩数", "心拍", "睡眠", "ワークアウト", "運動", "健康", "体重", "ダイエット"]),
            ("DJ", ["音楽", "曲", "再生", "プレイリスト", "次の曲", "音量"]),
            ("コーダー", ["コード", "バグ", "プログラム", "関数", "エラー", "debug"]),
            ("翻訳者", ["翻訳", "英訳", "和訳", "英語にして", "日本語にして"]),
            ("スケジュール管理", ["予定", "カレンダー", "リマインダー", "会議", "スケジュール"]),
            ("リサーチャー", ["調べ", "検索", "最新", "ニュース"]),
            ("料理アシスタント", ["レシピ", "料理", "献立", "食材"]),
            ("データアナリスト", ["計算", "統計", "平均", "集計"]),
            ("メンタルケア", ["つらい", "悩み", "不安", "ストレス"]),
        ]

        for (name, words) in keywords {
            let hits = words.filter { lower.contains($0) }.count
            if hits >= 2 {
                return agents.first(where: { $0.name == name })
            }
        }
        return nil
    }

    // MARK: - Delegation Parsing

    private struct Delegation {
        let targetAgent: String
        let reason: String
        let content: String  // The delegating agent's analysis so far
    }

    /// Check if an agent's response contains a delegation request
    private func parseDelegation(from response: String) -> Delegation? {
        // Pattern: @delegate(AgentName) reason text
        guard let range = response.range(of: #"@delegate\(([^)]+)\)\s*(.+)"#, options: .regularExpression) else {
            return nil
        }

        let match = String(response[range])
        guard let nameRange = match.range(of: #"\(([^)]+)\)"#, options: .regularExpression) else { return nil }

        let agentName = String(match[nameRange]).dropFirst().dropLast()
        let reason = String(match[nameRange.upperBound...]).trimmingCharacters(in: .whitespaces)

        // Content is everything before the @delegate
        let content = String(response[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)

        return Delegation(targetAgent: String(agentName), reason: reason, content: content)
    }
}
