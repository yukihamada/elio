import XCTest
@testable import LocalAIAgent

/// Tests for inference backends (GroqBackend, CloudBackend, P2PBackend)
@MainActor
final class BackendTests: XCTestCase {

    // MARK: - GroqBackend Tests

    func testGroqBackendProperties() {
        let backend = GroqBackend()

        XCTAssertEqual(backend.backendId, "groq")
        XCTAssertEqual(backend.tokenCost, 1)
        XCTAssertFalse(backend.displayName.isEmpty)
    }

    func testGroqBackendInitialState() {
        let backend = GroqBackend()

        XCTAssertFalse(backend.isGenerating)
        // isReady depends on API key availability
    }

    // MARK: - CloudBackend Tests

    func testCloudBackendProperties() {
        let backend = CloudBackend()

        // backendId includes provider name, e.g., "cloud_openai"
        XCTAssertTrue(backend.backendId.hasPrefix("cloud_"))
        XCTAssertEqual(backend.tokenCost, 5)
        XCTAssertFalse(backend.displayName.isEmpty)
    }

    func testCloudBackendInitialState() {
        let backend = CloudBackend()

        XCTAssertFalse(backend.isGenerating)
    }

    func testCloudBackendSetProvider() {
        let backend = CloudBackend()

        backend.setProvider(.anthropic)
        XCTAssertEqual(backend.provider, .anthropic)

        backend.setProvider(.google)
        XCTAssertEqual(backend.provider, .google)

        backend.setProvider(.openai)
        XCTAssertEqual(backend.provider, .openai)
    }

    // MARK: - P2PBackend Tests

    func testP2PBackendProperties() {
        let backend = P2PBackend()

        // Default mode is private
        XCTAssertTrue(backend.backendId.contains("p2p"))
        XCTAssertFalse(backend.displayName.isEmpty)
    }

    func testP2PBackendInitialState() {
        let backend = P2PBackend()

        XCTAssertFalse(backend.isGenerating)
        XCTAssertFalse(backend.isReady) // No server connected initially
        XCTAssertNil(backend.selectedServer)
        XCTAssertTrue(backend.availableServers.isEmpty)
        XCTAssertTrue(backend.trustedServers.isEmpty)
    }

    func testP2PBackendModeSwitch() {
        let backend = P2PBackend()

        // Test private mode
        backend.mode = .privateNetwork
        XCTAssertEqual(backend.tokenCost, 0) // Private is free
        XCTAssertEqual(backend.backendId, "private_p2p")

        // Test public mode
        backend.mode = .publicNetwork
        XCTAssertEqual(backend.tokenCost, 2) // Public costs 2 tokens
        XCTAssertEqual(backend.backendId, "public_p2p")
    }

    // MARK: - P2P Protocol Types Tests

    func testP2PStreamChunkCodable() throws {
        let chunk = P2PStreamChunk(token: "Hello", isComplete: false, fullResponse: nil)

        let encoded = try JSONEncoder().encode(chunk)
        let decoded = try JSONDecoder().decode(P2PStreamChunk.self, from: encoded)

        XCTAssertEqual(decoded.token, "Hello")
        XCTAssertFalse(decoded.isComplete)
        XCTAssertNil(decoded.fullResponse)
    }

    func testP2PStreamChunkComplete() throws {
        let chunk = P2PStreamChunk(token: "", isComplete: true, fullResponse: "Full response here")

        let encoded = try JSONEncoder().encode(chunk)
        let decoded = try JSONDecoder().decode(P2PStreamChunk.self, from: encoded)

        XCTAssertTrue(decoded.isComplete)
        XCTAssertEqual(decoded.fullResponse, "Full response here")
    }

    func testP2PErrorResponseCodable() throws {
        let error = P2PErrorResponse(error: "Test error message")

        let encoded = try JSONEncoder().encode(error)
        let decoded = try JSONDecoder().decode(P2PErrorResponse.self, from: encoded)

        XCTAssertEqual(decoded.error, "Test error message")
    }

    func testP2PServerStatsCodable() throws {
        let date = Date()
        let stats = P2PServerStats(date: date, requestsServed: 42, tokensEarned: 42)

        let encoded = try JSONEncoder().encode(stats)
        let decoded = try JSONDecoder().decode(P2PServerStats.self, from: encoded)

        XCTAssertEqual(decoded.requestsServed, 42)
        XCTAssertEqual(decoded.tokensEarned, 42)
    }

    // MARK: - P2P Server Error Tests

    func testP2PServerErrorDescriptions() {
        let backendNotReady = P2PServerError.backendNotReady
        let startFailed = P2PServerError.startFailed("Port in use")
        let connectionFailed = P2PServerError.connectionFailed

        XCTAssertNotNil(backendNotReady.errorDescription)
        XCTAssertNotNil(startFailed.errorDescription)
        XCTAssertNotNil(connectionFailed.errorDescription)

        XCTAssertTrue(startFailed.errorDescription?.contains("Port in use") ?? false)
    }

    // MARK: - ChatWebBackend Tests

    func testChatWebBackendProperties() {
        let backend = ChatWebBackend()

        XCTAssertEqual(backend.backendId, "chatweb")
        XCTAssertEqual(backend.tokenCost, 0)
        XCTAssertFalse(backend.displayName.isEmpty)
    }

    func testChatWebBackendInitialState() {
        let backend = ChatWebBackend()

        XCTAssertFalse(backend.isGenerating)
        XCTAssertTrue(backend.isReady, "ChatWebBackend should always be ready (no API key needed)")
    }

    func testChatWebBackendAuthTokenDefault() {
        let backend = ChatWebBackend()

        XCTAssertNil(backend.authToken, "Auth token should be nil by default")
    }

    func testChatWebBackendStopGeneration() {
        let backend = ChatWebBackend()

        // Should not crash when called with no active task
        backend.stopGeneration()
        XCTAssertFalse(backend.isGenerating)
    }

    // MARK: - PrivateServerManager Tests

    func testPrivateServerManagerShared() {
        let manager1 = PrivateServerManager.shared
        let manager2 = PrivateServerManager.shared
        XCTAssertTrue(manager1 === manager2, "Should return same instance")
    }

    func testPrivateServerManagerInitialState() {
        let manager = PrivateServerManager.shared

        XCTAssertFalse(manager.isRunning)
        XCTAssertEqual(manager.connectedClients, 0)
        XCTAssertNil(manager.serverAddress)
    }
}
