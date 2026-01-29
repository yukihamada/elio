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
        registerServer(ShortcutsServer())
        registerServer(WebSearchServer())
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

    /// Returns tools in JSON Schema format for MCP/Hermes-style tool calling
    func getToolsSchemaJSON(enabledServers: Set<String>) -> String {
        let tools = listAllTools(enabledServers: enabledServers)
        var toolsArray: [[String: Any]] = []

        for tool in tools {
            var properties: [String: [String: Any]] = [:]
            if let props = tool.inputSchema.properties {
                for (key, prop) in props {
                    var propDict: [String: Any] = ["type": prop.type]
                    if let desc = prop.description {
                        propDict["description"] = desc
                    }
                    if let enumVals = prop.enumValues {
                        propDict["enum"] = enumVals
                    }
                    properties[key] = propDict
                }
            }

            let toolDict: [String: Any] = [
                "type": "function",
                "function": [
                    "name": tool.name,
                    "description": tool.description,
                    "parameters": [
                        "type": "object",
                        "properties": properties,
                        "required": tool.inputSchema.required ?? []
                    ] as [String: Any]
                ] as [String: Any]
            ]
            toolsArray.append(toolDict)
        }

        guard let jsonData = try? JSONSerialization.data(withJSONObject: toolsArray, options: [.prettyPrinted, .sortedKeys]) else {
            return "[]"
        }
        return String(data: jsonData, encoding: .utf8) ?? "[]"
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
    // 簡素化されたフォーマット（システムプロンプトに例が含まれるため最小限に）
    static let toolCallFormatJa = ""

    static let toolCallFormatEn = ""

    static func toolCallFormat(locale: Locale = .current) -> String {
        // フォーマットはシステムプロンプト内のfew-shot例で示すため、ここでは空を返す
        return ""
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
