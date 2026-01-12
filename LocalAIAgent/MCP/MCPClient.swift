import Foundation

@MainActor
final class MCPClient: ObservableObject {
    @Published private(set) var servers: [String: any MCPServer] = [:]
    @Published private(set) var serverInfos: [MCPServerInfo] = []

    private var requestId = 0

    func registerServer(_ server: any MCPServer) {
        servers[server.id] = server
        updateServerInfos()
    }

    func unregisterServer(id: String) {
        servers.removeValue(forKey: id)
        updateServerInfos()
    }

    func registerBuiltInServers() {
        registerServer(FileSystemServer())
        registerServer(CalendarServer())
        registerServer(RemindersServer())
        registerServer(ContactsServer())
        registerServer(PhotosServer())
        registerServer(LocationServer())
        registerServer(HealthServer())
        registerServer(ShortcutsServer())
        registerServer(WebSearchServer())
        registerServer(WeatherServer())
        registerServer(NotesServer())
        // Translation requires iOS 18.0+ and uses SwiftUI view modifiers
        // Disabled for now - needs UI-based implementation
        // if #available(iOS 18.0, *) {
        //     registerServer(TranslationServer())
        // }
    }

    private func updateServerInfos() {
        serverInfos = servers.values.map { $0.toServerInfo() }
    }

    func listAllTools(enabledServers: Set<String>) -> [MCPTool] {
        servers
            .filter { enabledServers.contains($0.key) }
            .flatMap { $0.value.listTools() }
    }

    func callTool(
        serverId: String,
        toolName: String,
        arguments: [String: JSONValue]
    ) async throws -> MCPResult {
        guard let server = servers[serverId] else {
            throw MCPClientError.serverNotFound(serverId)
        }

        return try await server.callTool(name: toolName, arguments: arguments)
    }

    func callTool(
        fullToolName: String,
        arguments: [String: JSONValue],
        enabledServers: Set<String>
    ) async throws -> MCPResult {
        // ツール名からサーバーを特定
        for (serverId, server) in servers where enabledServers.contains(serverId) {
            let tools = server.listTools()
            if tools.contains(where: { $0.name == fullToolName }) {
                return try await server.callTool(name: fullToolName, arguments: arguments)
            }
        }

        throw MCPClientError.toolNotFound(fullToolName)
    }

    func getToolsDescription(enabledServers: Set<String>, locale: Locale = .current) -> String {
        let tools = listAllTools(enabledServers: enabledServers)
        let isJapanese = locale.language.languageCode?.identifier == "ja"

        var description = isJapanese ? "利用可能なツール:\n\n" : "Available Tools:\n\n"

        for tool in tools {
            description += "### \(tool.name)\n"
            description += "\(tool.description)\n"

            if let properties = tool.inputSchema.properties, !properties.isEmpty {
                description += isJapanese ? "パラメータ:\n" : "Parameters:\n"
                for (key, prop) in properties {
                    let requiredLabel = isJapanese ? " (必須)" : " (required)"
                    let required = tool.inputSchema.required?.contains(key) == true ? requiredLabel : ""
                    description += "- \(key): \(prop.type)\(required)"
                    if let desc = prop.description {
                        description += " - \(desc)"
                    }
                    description += "\n"
                }
            }
            description += "\n"
        }

        return description
    }

    // MARK: - Prompt Support

    func listAllPrompts(enabledServers: Set<String>) -> [MCPPrompt] {
        servers
            .filter { enabledServers.contains($0.key) }
            .flatMap { $0.value.listPrompts() }
    }

    func getPrompt(
        name: String,
        arguments: [String: String],
        enabledServers: Set<String>
    ) -> MCPPromptResult? {
        for (serverId, server) in servers where enabledServers.contains(serverId) {
            if let result = server.getPrompt(name: name, arguments: arguments) {
                return result
            }
        }
        return nil
    }

    func getPromptsDescription(enabledServers: Set<String>, locale: Locale = .current) -> String {
        let prompts = listAllPrompts(enabledServers: enabledServers)
        let isJapanese = locale.language.languageCode?.identifier == "ja"

        if prompts.isEmpty {
            return ""
        }

        var description = isJapanese ? "利用可能なプロンプト:\n\n" : "Available Prompts:\n\n"

        for prompt in prompts {
            description += "### \(prompt.name)\n"
            description += "\(prompt.localizedDescription(locale: locale))\n"

            if let args = prompt.arguments, !args.isEmpty {
                description += isJapanese ? "引数:\n" : "Arguments:\n"
                for arg in args {
                    let requiredLabel = isJapanese ? " (必須)" : " (required)"
                    let required = arg.required ? requiredLabel : ""
                    let argDesc = isJapanese ? arg.description : (arg.descriptionEn ?? arg.description)
                    description += "- \(arg.name)\(required): \(argDesc)\n"
                }
            }
            description += "\n"
        }

        return description
    }

    private func nextRequestId() -> Int {
        requestId += 1
        return requestId
    }
}

// MARK: - Tool Call Formatting for LLM

extension MCPClient {
    static let toolCallFormatJa = """
    ツールを使用する場合は、以下の形式で回答してください:

    <tool_call>
    {
      "name": "ツール名",
      "arguments": {
        "引数名": "値"
      }
    }
    </tool_call>

    ツールの結果を受け取った後、ユーザーに分かりやすく回答してください。
    複数のツールが必要な場合は、一つずつ実行してください。
    """

    static let toolCallFormatEn = """
    When using a tool, respond in the following format:

    <tool_call>
    {
      "name": "tool_name",
      "arguments": {
        "argument_name": "value"
      }
    }
    </tool_call>

    After receiving the tool result, explain it clearly to the user.
    If multiple tools are needed, execute them one at a time.
    """

    static func toolCallFormat(locale: Locale = .current) -> String {
        if locale.language.languageCode?.identifier == "ja" {
            return toolCallFormatJa
        }
        return toolCallFormatEn
    }

    func formatToolResult(_ result: MCPResult, locale: Locale = .current) -> String {
        guard let contents = result.content else {
            let isJapanese = locale.language.languageCode?.identifier == "ja"
            return isJapanese ? "結果がありません" : "No result"
        }

        return contents.compactMap { content -> String? in
            switch content.type {
            case "text": return content.text
            case "image":
                let isJapanese = locale.language.languageCode?.identifier == "ja"
                return isJapanese ? "[画像データ]" : "[Image data]"
            default: return nil
            }
        }.joined(separator: "\n")
    }
}
