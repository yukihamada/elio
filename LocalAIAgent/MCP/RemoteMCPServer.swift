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
    /// HTTP error. We intentionally do NOT carry the server's raw response body to
    /// avoid leaking attacker-controlled text into the UI / model context.
    case http(Int)
    case rpc(MCPError)
    case decode(String)
    case empty
    case tooLarge

    var errorDescription: String? {
        switch self {
        case .invalidURL(let u): return "無効なURL: \(u)"
        case .timeout: return "タイムアウト（15秒）"
        case .unauthorized(let code): return "認証エラー (\(code)): トークンが無効か未設定です"
        case .http(let code): return "HTTPエラー \(code): サーバーがリクエストを拒否しました"
        case .rpc(let e): return "RPCエラー \(e.code): \(e.message)"
        case .decode(let msg): return "応答の解析に失敗: \(msg)"
        case .empty: return "空の応答"
        case .tooLarge: return "応答が大きすぎます（5MB上限）"
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

    /// Hard cap on a single response body. Protects against a malicious / runaway
    /// remote server flooding the device (memory DoS).
    static let maxResponseBytes = 5 * 1024 * 1024 // 5 MB

    /// Validation for remote-supplied tool names (mitigates prompt injection /
    /// tool-name spoofing). Names must match the same shape MCP tools use locally.
    static let toolNamePattern = "^[A-Za-z0-9_-]{1,64}$"
    static let maxToolDescriptionLength = 500

    private let cacheLock = NSLock()
    private var cachedTools: [MCPTool] = []

    private let session: URLSession
    /// Keep a strong ref to our delegate (URLSession only holds it weakly).
    private let sessionDelegate: NoRedirectDelegate?

    init(config: RemoteMCPServerConfig, token: String?, session: URLSession? = nil) throws {
        guard let url = URL(string: config.urlString), url.scheme == "https" else {
            throw RemoteMCPError.invalidURL(config.urlString)
        }
        self.id = config.id
        self.name = config.name
        self.serverDescription = config.urlString
        self.icon = config.icon
        self.url = url
        self.token = (token?.isEmpty == false) ? token : nil

        if let session = session {
            // Caller-provided session (tests). Don't attach a delegate.
            self.session = session
            self.sessionDelegate = nil
        } else {
            // Dedicated session: bounded resource timeout + redirect refusal so the
            // bearer token is never forwarded to a different host on a 3xx.
            let cfg = URLSessionConfiguration.ephemeral
            cfg.timeoutIntervalForRequest = timeout
            cfg.timeoutIntervalForResource = 30
            cfg.httpAdditionalHeaders = nil
            let delegate = NoRedirectDelegate()
            self.sessionDelegate = delegate
            self.session = URLSession(configuration: cfg, delegate: delegate, delegateQueue: nil)
        }
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
    ///
    /// - Parameter reservedNames: tool names already claimed by built-in or
    ///   previously-registered servers. Any remote tool whose name collides is
    ///   dropped (with a warning) so a remote server cannot shadow / hijack an
    ///   existing tool such as `read_file`.
    @discardableResult
    func refreshTools(reservedNames: Set<String> = []) async throws -> [MCPTool] {
        // 1. initialize (server echoes protocolVersion; we don't strictly require it)
        _ = try? await initialize()

        // 2. tools/list
        let response = try await send(method: MCPMethod.listTools.rawValue, params: nil)
        if let error = response.error {
            throw RemoteMCPError.rpc(error)
        }
        let defs = response.result?.tools ?? []
        var seen = Set<String>()
        let tools = defs.compactMap { def -> MCPTool? in
            guard let tool = Self.sanitizedTool(from: def) else { return nil }
            if reservedNames.contains(tool.name) {
                NSLog("[RemoteMCP] dropping remote tool '%@' from '%@': collides with an existing tool name", tool.name, name)
                return nil
            }
            // Also de-dupe within this server's own list.
            guard seen.insert(tool.name).inserted else { return nil }
            return tool
        }
        storeTools(tools)
        return tools
    }

    /// Validate + normalize a remote tool definition.
    /// - Rejects (returns nil) tools whose name doesn't match `^[A-Za-z0-9_-]{1,64}$`.
    /// - Caps the description at 500 chars and replaces control characters / newlines
    ///   with spaces so a remote server can't smuggle instructions into the prompt.
    static func sanitizedTool(from def: MCPToolDefinition) -> MCPTool? {
        guard def.name.range(of: toolNamePattern, options: .regularExpression) != nil else {
            return nil
        }
        let rawDescription = def.description ?? def.name
        return MCPTool(
            name: def.name,
            description: sanitizeDescription(rawDescription),
            inputSchema: def.inputSchema
        )
    }

    static func sanitizeDescription(_ raw: String) -> String {
        let normalized = String(raw.unicodeScalars.map { scalar -> Character in
            // Replace newlines and any other control character with a space.
            if scalar == "\n" || scalar == "\r" || scalar == "\t" || CharacterSet.controlCharacters.contains(scalar) {
                return " "
            }
            return Character(scalar)
        })
        let collapsed = normalized
            .components(separatedBy: " ")
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return String(collapsed.prefix(maxToolDescriptionLength))
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
        let requestId = nextId
        let body = MCPRequest(id: requestId, method: method, params: params)
        let data = try JSONEncoder().encode(body)
        return try await perform(bodyData: data, expectedId: requestId)
    }

    private func send<P: Encodable>(method: String, encodableParams: P) async throws -> MCPResponse {
        let requestId = nextId
        let body = GenericRequest(jsonrpc: "2.0", id: requestId, method: method, params: encodableParams)
        let data = try JSONEncoder().encode(body)
        return try await perform(bodyData: data, expectedId: requestId)
    }

    private func perform(bodyData: Data, expectedId: Int) async throws -> MCPResponse {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
        if let token = token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = bodyData

        // Stream the response so we can abort once it exceeds maxResponseBytes
        // instead of buffering an unbounded body in memory.
        let bytes: URLSession.AsyncBytes
        let response: URLResponse
        do {
            (bytes, response) = try await session.bytes(for: request)
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
            // Drain a little so the connection can be reused, but never surface the
            // server's raw body to the UI / model context.
            throw RemoteMCPError.http(http.statusCode)
        }

        let data = try await Self.collect(bytes, limit: Self.maxResponseBytes)
        return try Self.parseResponse(data, expectedId: expectedId)
    }

    /// Accumulate an async byte stream up to `limit`, throwing `.tooLarge` if exceeded.
    /// Generic over the byte sequence so it can be unit-tested without a live session.
    static func collect<S: AsyncSequence>(_ bytes: S, limit: Int) async throws -> Data
    where S.Element == UInt8 {
        var data = Data()
        data.reserveCapacity(min(limit, 64 * 1024))
        for try await byte in bytes {
            data.append(byte)
            if data.count > limit {
                throw RemoteMCPError.tooLarge
            }
        }
        return data
    }

    /// Parse either a raw JSON-RPC response or an SSE stream (`data:` lines).
    /// Only frames whose `id` matches `expectedId` are accepted; id-less frames
    /// (server notifications) are skipped.
    static func parseResponse(_ data: Data, expectedId: Int? = nil) throws -> MCPResponse {
        guard !data.isEmpty else { throw RemoteMCPError.empty }
        let decoder = JSONDecoder()

        func matchesId(_ resp: MCPResponse) -> Bool {
            guard let expectedId = expectedId else { return true }
            // Notifications (no id) are not responses to our request → skip.
            guard let id = resp.id else { return false }
            return id == expectedId
        }

        // Fast path: plain JSON object.
        if let response = try? decoder.decode(MCPResponse.self, from: data) {
            if matchesId(response) { return response }
            throw RemoteMCPError.decode("response id mismatch")
        }

        // SSE path: concatenate the JSON payloads of `data:` lines, decode the last
        // frame that parses as an MCPResponse AND matches our request id.
        guard let text = String(data: data, encoding: .utf8) else {
            throw RemoteMCPError.decode("non-UTF8 body")
        }
        var lastParsed: MCPResponse?
        var dataBuffer = ""
        func flush() {
            guard !dataBuffer.isEmpty else { return }
            if let d = dataBuffer.data(using: .utf8),
               let resp = try? decoder.decode(MCPResponse.self, from: d),
               matchesId(resp) {
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
        throw RemoteMCPError.decode("no matching JSON-RPC frame in response")
    }
}

// MARK: - Redirect refusal delegate

/// Refuses HTTP redirects so a remote MCP server cannot 3xx us to another host
/// and capture the `Authorization: Bearer` header.
private final class NoRedirectDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        // nil → do not follow the redirect; the original response is returned.
        completionHandler(nil)
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
