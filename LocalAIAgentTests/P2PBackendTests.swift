import XCTest
@testable import LocalAIAgent

final class P2PBackendTests: XCTestCase {

    // MARK: - P2PBackend State Tests

    @MainActor
    func testP2PBackendInitialState() throws {
        let backend = P2PBackend()
        XCTAssertNil(backend.selectedServer)
        XCTAssertTrue(backend.availableServers.isEmpty)
        XCTAssertTrue(backend.trustedServers.isEmpty)
        XCTAssertEqual(backend.mode, .privateNetwork)
    }

    @MainActor
    func testP2PBackendProperties() throws {
        let backend = P2PBackend()
        XCTAssertEqual(backend.backendId, "private_p2p")
        XCTAssertFalse(backend.isGenerating)
    }

    // MARK: - P2PServer Tests

    func testP2PServerEquality() throws {
        let server1 = P2PServer(
            id: "device-1",
            name: "Mac-1",
            endpoint: .hostPort(host: .ipv4(.loopback), port: 8080),
            pairingCode: "1234"
        )
        let server2 = P2PServer(
            id: "device-1",
            name: "Mac-Different",
            endpoint: .hostPort(host: .ipv4(.loopback), port: 9090),
            pairingCode: "5678"
        )
        let server3 = P2PServer(
            id: "device-2",
            name: "Mac-1",
            endpoint: .hostPort(host: .ipv4(.loopback), port: 8080),
            pairingCode: "1234"
        )

        XCTAssertEqual(server1, server2, "Servers with same ID should be equal")
        XCTAssertNotEqual(server1, server3, "Servers with different IDs should not be equal")
    }

    // MARK: - Trust Management Tests

    @MainActor
    func testTrustDevice() throws {
        let backend = P2PBackend()
        let server = P2PServer(
            id: "test-device",
            name: "Test Mac",
            endpoint: .hostPort(host: .ipv4(.loopback), port: 8080),
            pairingCode: nil
        )

        XCTAssertFalse(backend.isDeviceTrusted(server))

        backend.trustDevice(server)
        XCTAssertTrue(backend.isDeviceTrusted(server))

        backend.untrustDevice(server)
        XCTAssertFalse(backend.isDeviceTrusted(server))
    }
}
