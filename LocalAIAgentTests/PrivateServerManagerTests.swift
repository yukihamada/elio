import XCTest
@testable import LocalAIAgent

@MainActor
final class PrivateServerManagerTests: XCTestCase {

    // MARK: - Initialization

    func testPrivateServerManagerSingleton() throws {
        let manager = PrivateServerManager.shared
        XCTAssertNotNil(manager)
        XCTAssertFalse(manager.isRunning)
    }

    // MARK: - Server State

    func testStartWithoutBackendThrows() async throws {
        let manager = PrivateServerManager.shared
        do {
            try await manager.start()
            XCTFail("Should throw when no backend is configured")
        } catch {
            // Expected: backendNotReady
            XCTAssertTrue(true)
        }
    }

    func testStopWhenNotRunning() throws {
        let manager = PrivateServerManager.shared
        // Should not crash
        manager.stop()
        XCTAssertFalse(manager.isRunning)
    }

    // MARK: - Compute Capability

    func testGetComputeCapability() throws {
        let manager = PrivateServerManager.shared
        let capability = manager.getComputeCapability()
        XCTAssertFalse(capability.hasLocalLLM) // No backend configured
        XCTAssertGreaterThan(capability.freeMemoryGB ?? 0, 0)
        XCTAssertGreaterThan(capability.cpuCores ?? 0, 0)
    }
}
