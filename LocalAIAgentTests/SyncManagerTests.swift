import XCTest
@testable import LocalAIAgent

@MainActor
final class SyncManagerTests: XCTestCase {

    // MARK: - Initialization

    func testSyncManagerInitialState() {
        let syncManager = SyncManager()
        XCTAssertFalse(syncManager.isLoggedIn)
        XCTAssertFalse(syncManager.isSyncing)
        XCTAssertEqual(syncManager.email, "")
        XCTAssertEqual(syncManager.creditsRemaining, 0)
        XCTAssertEqual(syncManager.plan, "free")
    }

    // MARK: - Token Storage

    func testLogoutClearsState() {
        let syncManager = SyncManager()
        syncManager.logout()
        XCTAssertFalse(syncManager.isLoggedIn)
        XCTAssertEqual(syncManager.email, "")
        XCTAssertEqual(syncManager.creditsRemaining, 0)
        XCTAssertEqual(syncManager.plan, "free")
        XCTAssertNil(syncManager.authToken)
    }

    // MARK: - Server Conversation Parsing

    func testServerConversationDecoding() throws {
        let json = """
        {
            "id": "abc-123",
            "title": "Test conversation",
            "updated_at": "2025-01-01T00:00:00Z",
            "message_count": 5,
            "last_message_preview": "Hello world"
        }
        """.data(using: .utf8)!

        let conv = try JSONDecoder().decode(ServerConversation.self, from: json)
        XCTAssertEqual(conv.id, "abc-123")
        XCTAssertEqual(conv.title, "Test conversation")
        XCTAssertEqual(conv.updatedAt, "2025-01-01T00:00:00Z")
        XCTAssertEqual(conv.messageCount, 5)
        XCTAssertEqual(conv.lastMessagePreview, "Hello world")
    }

    func testServerConversationDecodingWithMissingOptionals() throws {
        let json = """
        {
            "id": "abc-123",
            "title": "Test"
        }
        """.data(using: .utf8)!

        let conv = try JSONDecoder().decode(ServerConversation.self, from: json)
        XCTAssertEqual(conv.id, "abc-123")
        XCTAssertEqual(conv.title, "Test")
        XCTAssertNil(conv.updatedAt)
        XCTAssertNil(conv.messageCount)
        XCTAssertNil(conv.lastMessagePreview)
    }

    // MARK: - Sync List Response Parsing

    func testSyncListResponseDecoding() throws {
        let json = """
        {
            "conversations": [
                {"id": "a", "title": "First"},
                {"id": "b", "title": "Second"}
            ],
            "sync_token": "2025-01-01T00:00:00Z"
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(SyncListResponse.self, from: json)
        XCTAssertEqual(response.conversations.count, 2)
        XCTAssertEqual(response.conversations[0].id, "a")
        XCTAssertEqual(response.syncToken, "2025-01-01T00:00:00Z")
    }

    // MARK: - Sync Conversation Detail Parsing

    func testSyncConversationDetailDecoding() throws {
        let json = """
        {
            "conversation_id": "abc-123",
            "title": "Test conversation",
            "messages": [
                {"role": "user", "content": "Hello", "timestamp": "2025-01-01T00:00:00Z"},
                {"role": "assistant", "content": "Hi there!", "timestamp": "2025-01-01T00:00:01Z"}
            ]
        }
        """.data(using: .utf8)!

        let detail = try JSONDecoder().decode(SyncConversationDetail.self, from: json)
        XCTAssertEqual(detail.conversationId, "abc-123")
        XCTAssertEqual(detail.title, "Test conversation")
        XCTAssertEqual(detail.messages.count, 2)
        XCTAssertEqual(detail.messages[0].role, "user")
        XCTAssertEqual(detail.messages[0].content, "Hello")
        XCTAssertEqual(detail.messages[1].role, "assistant")
    }

    // MARK: - Push Response Parsing

    func testSyncPushResponseDecoding() throws {
        let json = """
        {
            "synced": [
                {"client_id": "local-1", "server_id": "server-abc"},
                {"client_id": "local-2", "server_id": "server-def"}
            ]
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(SyncPushResponse.self, from: json)
        XCTAssertEqual(response.synced.count, 2)
        XCTAssertEqual(response.synced[0].clientId, "local-1")
        XCTAssertEqual(response.synced[0].serverId, "server-abc")
    }

    // MARK: - Auth Response Parsing

    func testLoginResponseDecoding() throws {
        let json = """
        {
            "ok": true,
            "token": "test-token-123",
            "user_id": "user-abc",
            "email": "test@example.com"
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(LoginResponse.self, from: json)
        XCTAssertTrue(response.ok)
        XCTAssertEqual(response.token, "test-token-123")
        XCTAssertEqual(response.userId, "user-abc")
        XCTAssertEqual(response.email, "test@example.com")
    }

    func testAuthMeResponseDecoding() throws {
        let json = """
        {
            "authenticated": true,
            "user_id": "user-abc",
            "email": "test@example.com",
            "credits_remaining": 29500,
            "credits_used": 500,
            "plan": "starter"
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(AuthMeResponse.self, from: json)
        XCTAssertTrue(response.authenticated)
        XCTAssertEqual(response.userId, "user-abc")
        XCTAssertEqual(response.email, "test@example.com")
        XCTAssertEqual(response.creditsRemaining, 29500)
        XCTAssertEqual(response.plan, "starter")
    }

    // MARK: - Conversation → Push Payload Conversion

    func testConversationToPushPayload() {
        let messages = [
            Message(role: .user, content: "Hello"),
            Message(role: .assistant, content: "Hi there!"),
        ]
        let conversation = Conversation(
            title: "Test chat",
            messages: messages
        )

        let payload = SyncManager.buildPushPayload(for: [conversation])
        XCTAssertEqual(payload.count, 1)
        XCTAssertEqual(payload[0]["title"] as? String, "Test chat")

        let msgs = payload[0]["messages"] as? [[String: Any]]
        XCTAssertEqual(msgs?.count, 2)
        XCTAssertEqual(msgs?[0]["role"] as? String, "user")
        XCTAssertEqual(msgs?[0]["content"] as? String, "Hello")
        XCTAssertEqual(msgs?[1]["role"] as? String, "assistant")
    }

    // MARK: - Base URL

    func testBaseURL() {
        let syncManager = SyncManager()
        XCTAssertEqual(syncManager.baseURL, "https://chatweb.ai")
    }
}
