import Foundation

// MARK: - MCP Protocol Types (JSON-RPC 2.0 based)

struct MCPRequest: Codable {
    let jsonrpc: String
    let id: Int
    let method: String
    let params: MCPParams?

    init(id: Int, method: String, params: MCPParams? = nil) {
        self.jsonrpc = "2.0"
        self.id = id
        self.method = method
        self.params = params
    }
}

struct MCPParams: Codable {
    let name: String?
    let arguments: [String: JSONValue]?

    init(name: String? = nil, arguments: [String: JSONValue]? = nil) {
        self.name = name
        self.arguments = arguments
    }
}

struct MCPResponse: Codable {
    let jsonrpc: String
    let id: Int?
    let result: MCPResult?
    let error: MCPError?
}

struct MCPResult: Codable {
    let content: [MCPContent]?
    let tools: [MCPToolDefinition]?
    let isError: Bool?

    init(content: [MCPContent]? = nil, tools: [MCPToolDefinition]? = nil, isError: Bool? = nil) {
        self.content = content
        self.tools = tools
        self.isError = isError
    }
}

struct MCPContent: Codable {
    let type: String
    let text: String?
    let data: String?
    let mimeType: String?

    init(type: String = "text", text: String? = nil, data: String? = nil, mimeType: String? = nil) {
        self.type = type
        self.text = text
        self.data = data
        self.mimeType = mimeType
    }

    static func text(_ text: String) -> MCPContent {
        MCPContent(type: "text", text: text)
    }

    static func image(data: String, mimeType: String) -> MCPContent {
        MCPContent(type: "image", data: data, mimeType: mimeType)
    }
}

struct MCPToolDefinition: Codable {
    let name: String
    let description: String?
    let inputSchema: MCPInputSchema

    init(name: String, description: String?, inputSchema: MCPInputSchema) {
        self.name = name
        self.description = description
        self.inputSchema = inputSchema
    }
}

// MARK: - MCP Prompt Types

struct MCPPrompt: Identifiable, Codable {
    let name: String
    let description: String
    let descriptionEn: String?
    let arguments: [MCPPromptArgument]?

    var id: String { name }

    init(name: String, description: String, descriptionEn: String? = nil, arguments: [MCPPromptArgument]? = nil) {
        self.name = name
        self.description = description
        self.descriptionEn = descriptionEn
        self.arguments = arguments
    }

    func localizedDescription(locale: Locale = .current) -> String {
        if locale.language.languageCode?.identifier == "ja" {
            return description
        }
        return descriptionEn ?? description
    }
}

struct MCPPromptArgument: Codable {
    let name: String
    let description: String
    let descriptionEn: String?
    let required: Bool

    init(name: String, description: String, descriptionEn: String? = nil, required: Bool = false) {
        self.name = name
        self.description = description
        self.descriptionEn = descriptionEn
        self.required = required
    }
}

struct MCPPromptMessage: Codable {
    let role: String // "user" or "assistant"
    let content: MCPPromptContent

    init(role: String, content: MCPPromptContent) {
        self.role = role
        self.content = content
    }
}

struct MCPPromptContent: Codable {
    let type: String
    let text: String

    init(type: String = "text", text: String) {
        self.type = type
        self.text = text
    }

    static func text(_ text: String) -> MCPPromptContent {
        MCPPromptContent(type: "text", text: text)
    }
}

struct MCPPromptResult: Codable {
    let description: String?
    let messages: [MCPPromptMessage]

    init(description: String? = nil, messages: [MCPPromptMessage]) {
        self.description = description
        self.messages = messages
    }
}

struct MCPError: Codable {
    let code: Int
    let message: String
    let data: String?

    static let parseError = MCPError(code: -32700, message: "Parse error", data: nil)
    static let invalidRequest = MCPError(code: -32600, message: "Invalid Request", data: nil)
    static let methodNotFound = MCPError(code: -32601, message: "Method not found", data: nil)
    static let invalidParams = MCPError(code: -32602, message: "Invalid params", data: nil)
    static let internalError = MCPError(code: -32603, message: "Internal error", data: nil)

    static func serverError(message: String) -> MCPError {
        MCPError(code: -32000, message: message, data: nil)
    }
}

// MARK: - MCP Server Protocol

protocol MCPServer {
    var id: String { get }
    var name: String { get }
    var serverDescription: String { get }
    var icon: String { get }

    func listTools() -> [MCPTool]
    func callTool(name: String, arguments: [String: JSONValue]) async throws -> MCPResult

    // Prompt support (optional - default empty implementation)
    func listPrompts() -> [MCPPrompt]
    func getPrompt(name: String, arguments: [String: String]) -> MCPPromptResult?
}

extension MCPServer {
    // Default empty implementations for prompts
    func listPrompts() -> [MCPPrompt] { [] }
    func getPrompt(name: String, arguments: [String: String]) -> MCPPromptResult? { nil }

    func toServerInfo(isEnabled: Bool = true) -> MCPServerInfo {
        MCPServerInfo(
            id: id,
            name: name,
            description: serverDescription,
            icon: icon,
            isEnabled: isEnabled,
            tools: listTools()
        )
    }
}

// MARK: - MCP Methods

enum MCPMethod: String {
    case initialize = "initialize"
    case listTools = "tools/list"
    case callTool = "tools/call"
    case listResources = "resources/list"
    case readResource = "resources/read"
    case listPrompts = "prompts/list"
    case getPrompt = "prompts/get"
}

// MARK: - Error Types

enum MCPClientError: Error, LocalizedError {
    case serverNotFound(String)
    case toolNotFound(String)
    case invalidArguments(String)
    case executionFailed(String)
    case permissionDenied(String)

    var errorDescription: String? {
        switch self {
        case .serverNotFound(let server): return "サーバーが見つかりません: \(server)"
        case .toolNotFound(let tool): return "ツールが見つかりません: \(tool)"
        case .invalidArguments(let msg): return "無効な引数: \(msg)"
        case .executionFailed(let msg): return "実行エラー: \(msg)"
        case .permissionDenied(let msg): return "権限がありません: \(msg)"
        }
    }
}
