import Foundation

// MARK: - Remote MCP Server Configuration

/// Persisted configuration for a remote (Streamable HTTP) MCP server.
/// The bearer token is NEVER stored here — it lives in the Keychain keyed by `id`.
struct RemoteMCPServerConfig: Codable, Identifiable, Equatable {
    let id: String
    var name: String
    var urlString: String
    var icon: String
    var isEnabled: Bool
    /// Whether this server expects a bearer token (UI hint only; actual token in Keychain).
    var requiresToken: Bool

    init(
        id: String = UUID().uuidString,
        name: String,
        urlString: String,
        icon: String = "globe",
        isEnabled: Bool = true,
        requiresToken: Bool = false
    ) {
        self.id = id
        self.name = name
        self.urlString = urlString
        self.icon = icon
        self.isEnabled = isEnabled
        self.requiresToken = requiresToken
    }

    var keychainAccount: String { "remote_mcp_token_\(id)" }
}

// MARK: - Remote MCP Errors

enum RemoteMCPError: Error, LocalizedError {
    case invalidURL(String)
    case timeout
    case unauthorized(Int)
    case http(Int, String)
    case rpc(MCPError)
    case decode(String)
    case empty

    var errorDescription: String? {
        switch self {
        case .invalidURL(let u): return "無効なURL: \(u)"
        case .timeout: return "タイムアウト（15秒）"
        case .unauthorized(let code): return "認証エラー (\(code)): トークンが無効か未設定です"
        case .http(let code, let body): return "HTTPエラー \(code): \(body)"
        case .rpc(let e): return "RPCエラー \(e.code): \(e.message)"
        case .decode(let msg): return "応答の解析に失敗: \(msg)"
        case .empty: return "空の応答"
        }
    }
}

// MARK: - Remote MCP Server (MCPServer conformance)

/// A remote MCP server reached over JSON-RPC 2.0 via `POST <url>` (Streamable HTTP).
/// Supports both plain-JSON and SSE (`data:` framed) responses.
///
/// `listTools()` is synchronous (protocol requirement) and returns the cached tool
/// list. Call `refreshTools()` (async) at registration / when settings change to
/// populate the cache via `initialize` + `tools/list`.
final class RemoteMCPServer: MCPServer, @unchecked Sendable {
    let id: String
    let name: String
    let serverDescription: String
    let icon: String

    private let url: URL
    private let token: String?
    private let protocolVersion = "2024-11-05"
    private let timeout: TimeInterval = 15

    private let cacheLock = NSLock()
    private var cachedTools: [MCPTool] = []

    private let session: URLSession

    init(config: RemoteMCPServerConfig, token: String?, session: URLSession = .shared) throws {
        guard let url = URL(string: config.urlString),
              url.scheme == "https" || url.scheme == "http" else {
            throw RemoteMCPError.invalidURL(config.urlString)
        }
        self.id = config.id
        self.name = config.name
        self.serverDescription = config.urlString
        self.icon = config.icon
        self.url = url
        self.token = (token?.isEmpty == false) ? token : nil
        self.session = session
    }

    // MARK: MCPServer

    func listTools() -> [MCPTool] {
        cacheLock.lock(); defer { cacheLock.unlock() }
        return cachedTools
    }

    /// Synchronous (non-async) cache write so NSLock isn't held across an await.
    private func storeTools(_ tools: [MCPTool]) {
        cacheLock.lock()
        cachedTools = tools
        cacheLock.unlock()
    }

    func callTool(name: String, arguments: [String: JSONValue]) async throws -> MCPResult {
        let params = MCPParams(name: name, arguments: arguments)
        let response = try await send(method: MCPMethod.callTool.rawValue, params: params)
        if let error = response.error {
            throw RemoteMCPError.rpc(error)
        }
        guard let result = response.result else {
            throw RemoteMCPError.empty
        }
        // isError on the result is preserved so the orchestrator can surface tool failures.
        return result
    }

    // MARK: - Tool discovery

    /// Result of a connection test: the discovered tools (for UI display).
    @discardableResult
    func refreshTools() async throws -> [MCPTool] {
        // 1. initialize (server echoes protocolVersion; we don't strictly require it)
        _ = try? await initialize()

        // 2. tools/list
        let response = try await send(method: MCPMethod.listTools.rawValue, params: nil)
        if let error = response.error {
            throw RemoteMCPError.rpc(error)
        }
        let defs = response.result?.tools ?? []
        let tools = defs.map { def in
            MCPTool(
                name: def.name,
                description: def.description ?? def.name,
                inputSchema: def.inputSchema
            )
        }
        storeTools(tools)
        return tools
    }

    private func initialize() async throws -> MCPResponse {
        let initParams = InitializeParams(
            protocolVersion: protocolVersion,
            capabilities: [:],
            clientInfo: .init(name: "elio", version: "1.0")
        )
        return try await send(method: MCPMethod.initialize.rawValue, encodableParams: initParams)
    }

    // MARK: - Transport

    private var nextId: Int {
        idLock.lock(); defer { idLock.unlock() }
        idCounter += 1
        return idCounter
    }
    private let idLock = NSLock()
    private var idCounter = 0

    private func send(method: String, params: MCPParams?) async throws -> MCPResponse {
        let body = MCPRequest(id: nextId, method: method, params: params)
        let data = try JSONEncoder().encode(body)
        return try await perform(bodyData: data)
    }

    private func send<P: Encodable>(method: String, encodableParams: P) async throws -> MCPResponse {
        let body = GenericRequest(jsonrpc: "2.0", id: nextId, method: method, params: encodableParams)
        let data = try JSONEncoder().encode(body)
        return try await perform(bodyData: data)
    }

    private func perform(bodyData: Data) async throws -> MCPResponse {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
        if let token = token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = bodyData

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError where error.code == .timedOut {
            throw RemoteMCPError.timeout
        }

        guard let http = response as? HTTPURLResponse else {
            throw RemoteMCPError.decode("not an HTTP response")
        }

        if http.statusCode == 401 || http.statusCode == 403 {
            throw RemoteMCPError.unauthorized(http.statusCode)
        }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw RemoteMCPError.http(http.statusCode, String(body.prefix(200)))
        }

        return try Self.parseResponse(data)
    }

    /// Parse either a raw JSON-RPC response or an SSE stream (`data:` lines).
    static func parseResponse(_ data: Data) throws -> MCPResponse {
        guard !data.isEmpty else { throw RemoteMCPError.empty }
        let decoder = JSONDecoder()

        // Fast path: plain JSON object.
        if let response = try? decoder.decode(MCPResponse.self, from: data) {
            return response
        }

        // SSE path: concatenate the JSON payloads of `data:` lines, decode the last
        // one that parses as an MCPResponse (the JSON-RPC result frame).
        guard let text = String(data: data, encoding: .utf8) else {
            throw RemoteMCPError.decode("non-UTF8 body")
        }
        var lastParsed: MCPResponse?
        var dataBuffer = ""
        func flush() {
            guard !dataBuffer.isEmpty else { return }
            if let d = dataBuffer.data(using: .utf8),
               let resp = try? decoder.decode(MCPResponse.self, from: d) {
                lastParsed = resp
            }
            dataBuffer = ""
        }
        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.hasSuffix("\r") ? String(rawLine.dropLast()) : String(rawLine)
            if line.isEmpty {
                flush()
            } else if line.hasPrefix("data:") {
                let payload = line.dropFirst(5).drop { $0 == " " }
                if !dataBuffer.isEmpty { dataBuffer += "\n" }
                dataBuffer += payload
            }
            // comment lines (":...") and other SSE fields (event:, id:) are ignored
        }
        flush()

        if let resp = lastParsed {
            return resp
        }
        throw RemoteMCPError.decode("no JSON-RPC frame in response")
    }
}

// MARK: - Encodable request helpers (initialize needs richer params than MCPParams)

private struct InitializeParams: Encodable {
    let protocolVersion: String
    let capabilities: [String: String]
    let clientInfo: ClientInfo
    struct ClientInfo: Encodable {
        let name: String
        let version: String
    }
}

private struct GenericRequest<P: Encodable>: Encodable {
    let jsonrpc: String
    let id: Int
    let method: String
    let params: P
}
