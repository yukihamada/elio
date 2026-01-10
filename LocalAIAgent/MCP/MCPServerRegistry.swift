import Foundation
import UIKit

final class MCPServerRegistry {
    static let shared = MCPServerRegistry()

    private var customServers: [String: any MCPServer] = [:]

    private init() {}

    func registerCustomServer(_ server: any MCPServer) {
        customServers[server.id] = server
    }

    func unregisterCustomServer(id: String) {
        customServers.removeValue(forKey: id)
    }

    func getCustomServers() -> [any MCPServer] {
        Array(customServers.values)
    }

    func loadCustomServersFromJSON(at url: URL) throws -> [any MCPServer] {
        let data = try Data(contentsOf: url)
        let configs = try JSONDecoder().decode([CustomServerConfig].self, from: data)

        return configs.map { config in
            CustomMCPServer(config: config)
        }
    }
}

// MARK: - Custom Server Configuration

struct CustomServerConfig: Codable {
    let id: String
    let name: String
    let description: String
    let icon: String
    let tools: [CustomToolConfig]
}

struct CustomToolConfig: Codable {
    let name: String
    let description: String
    let inputSchema: MCPInputSchema
    let actionType: CustomActionType
    let actionConfig: [String: String]?
}

enum CustomActionType: String, Codable {
    case httpRequest
    case shortcut
    case urlScheme
    case javascript
}

// MARK: - Custom MCP Server Implementation

final class CustomMCPServer: MCPServer {
    let id: String
    let name: String
    let serverDescription: String
    let icon: String

    private let config: CustomServerConfig

    init(config: CustomServerConfig) {
        self.config = config
        self.id = config.id
        self.name = config.name
        self.serverDescription = config.description
        self.icon = config.icon
    }

    func listTools() -> [MCPTool] {
        config.tools.map { toolConfig in
            MCPTool(
                name: toolConfig.name,
                description: toolConfig.description,
                inputSchema: toolConfig.inputSchema
            )
        }
    }

    func callTool(name: String, arguments: [String: JSONValue]) async throws -> MCPResult {
        guard let toolConfig = config.tools.first(where: { $0.name == name }) else {
            throw MCPClientError.toolNotFound(name)
        }

        switch toolConfig.actionType {
        case .httpRequest:
            return try await executeHttpRequest(config: toolConfig, arguments: arguments)
        case .shortcut:
            return try await executeShortcut(config: toolConfig, arguments: arguments)
        case .urlScheme:
            return try await executeUrlScheme(config: toolConfig, arguments: arguments)
        case .javascript:
            return MCPResult(content: [.text("JavaScript execution not supported on iOS")])
        }
    }

    private func executeHttpRequest(config: CustomToolConfig, arguments: [String: JSONValue]) async throws -> MCPResult {
        guard let urlString = config.actionConfig?["url"],
              let url = URL(string: urlString) else {
            throw MCPClientError.invalidArguments("Invalid URL configuration")
        }

        var request = URLRequest(url: url)
        request.httpMethod = config.actionConfig?["method"] ?? "GET"

        let (data, _) = try await URLSession.shared.data(for: request)
        let responseText = String(data: data, encoding: .utf8) ?? "No response"

        return MCPResult(content: [.text(responseText)])
    }

    private func executeShortcut(config: CustomToolConfig, arguments: [String: JSONValue]) async throws -> MCPResult {
        guard let shortcutName = config.actionConfig?["shortcutName"] else {
            throw MCPClientError.invalidArguments("Shortcut name not specified")
        }

        let urlString = "shortcuts://run-shortcut?name=\(shortcutName.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? shortcutName)"

        if let url = URL(string: urlString) {
            await MainActor.run {
                UIApplication.shared.open(url)
            }
        }

        return MCPResult(content: [.text("ショートカット '\(shortcutName)' を実行しました")])
    }

    private func executeUrlScheme(config: CustomToolConfig, arguments: [String: JSONValue]) async throws -> MCPResult {
        guard let urlString = config.actionConfig?["url"],
              let url = URL(string: urlString) else {
            throw MCPClientError.invalidArguments("Invalid URL scheme")
        }

        await MainActor.run {
            UIApplication.shared.open(url)
        }

        return MCPResult(content: [.text("URL scheme を実行しました")])
    }
}
