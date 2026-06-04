import XCTest
@testable import LocalAIAgent

final class RemoteMCPServerTests: XCTestCase {

    // MARK: - JSON-RPC request encoding

    func testCallToolRequestEncoding() throws {
        let req = MCPRequest(
            id: 7,
            method: MCPMethod.callTool.rawValue,
            params: MCPParams(name: "speak", arguments: ["text": .string("hi")])
        )
        let data = try JSONEncoder().encode(req)
        let obj = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertEqual(obj["jsonrpc"] as? String, "2.0")
        XCTAssertEqual(obj["id"] as? Int, 7)
        XCTAssertEqual(obj["method"] as? String, "tools/call")
        let params = obj["params"] as! [String: Any]
        XCTAssertEqual(params["name"] as? String, "speak")
        let args = params["arguments"] as! [String: Any]
        XCTAssertEqual(args["text"] as? String, "hi")
    }

    // MARK: - Plain JSON response

    func testParsePlainJSONResponse() throws {
        let json = """
        {"jsonrpc":"2.0","id":1,"result":{"content":[{"type":"text","text":"hello"}],"isError":false}}
        """
        let resp = try RemoteMCPServer.parseResponse(Data(json.utf8))
        XCTAssertNil(resp.error)
        XCTAssertEqual(resp.result?.content?.first?.text, "hello")
        XCTAssertEqual(resp.result?.isError, false)
    }

    func testParseToolsListResponse() throws {
        let json = """
        {"jsonrpc":"2.0","id":2,"result":{"tools":[
          {"name":"list_techniques","description":"catalog","inputSchema":{"type":"object","properties":{"limit":{"type":"integer"}}}}
        ]}}
        """
        let resp = try RemoteMCPServer.parseResponse(Data(json.utf8))
        XCTAssertEqual(resp.result?.tools?.count, 1)
        XCTAssertEqual(resp.result?.tools?.first?.name, "list_techniques")
    }

    func testParseRPCErrorResponse() throws {
        let json = """
        {"jsonrpc":"2.0","id":3,"error":{"code":-32601,"message":"Method not found"}}
        """
        let resp = try RemoteMCPServer.parseResponse(Data(json.utf8))
        XCTAssertEqual(resp.error?.code, -32601)
        XCTAssertEqual(resp.error?.message, "Method not found")
    }

    // MARK: - SSE response

    func testParseSSEResponse() throws {
        let sse = """
        event: message
        data: {"jsonrpc":"2.0","id":4,"result":{"content":[{"type":"text","text":"sse-ok"}]}}

        """
        let resp = try RemoteMCPServer.parseResponse(Data(sse.utf8))
        XCTAssertEqual(resp.result?.content?.first?.text, "sse-ok")
    }

    func testParseMultilineSSEData() throws {
        // SSE allows a payload split across multiple data: lines (joined by \n).
        let sse = """
        data: {"jsonrpc":"2.0","id":5,
        data: "result":{"content":[{"type":"text","text":"multi"}]}}

        """
        let resp = try RemoteMCPServer.parseResponse(Data(sse.utf8))
        XCTAssertEqual(resp.result?.content?.first?.text, "multi")
    }

    func testParseEmptyThrows() {
        XCTAssertThrowsError(try RemoteMCPServer.parseResponse(Data()))
    }

    // MARK: - Config / Keychain account

    func testConfigKeychainAccountIsStable() {
        let c = RemoteMCPServerConfig(id: "abc", name: "X", urlString: "https://x/mcp")
        XCTAssertEqual(c.keychainAccount, "remote_mcp_token_abc")
    }

    func testInvalidURLThrows() {
        let c = RemoteMCPServerConfig(name: "bad", urlString: "ftp://nope")
        XCTAssertThrowsError(try RemoteMCPServer(config: c, token: nil))
    }

    // MARK: - Live integration (jiuflow.com/mcp, no auth, read-only)

    func testLiveJiuFlowToolsList() async throws {
        // Network test: skip silently if offline / endpoint changes shape.
        let c = RemoteMCPServerConfig(name: "JiuFlow", urlString: "https://jiuflow.com/mcp")
        guard let server = try? RemoteMCPServer(config: c, token: nil) else {
            return XCTFail("server init failed")
        }
        do {
            let tools = try await server.refreshTools()
            XCTAssertFalse(tools.isEmpty, "expected JiuFlow to expose tools")
            XCTAssertTrue(tools.contains { $0.name == "list_techniques" },
                          "expected list_techniques among \(tools.map { $0.name })")
        } catch {
            throw XCTSkip("JiuFlow MCP unreachable: \(error.localizedDescription)")
        }
    }
}
