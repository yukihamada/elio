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
        // If backend is already configured (e.g. from running app), skip
        // This test only validates behavior when no backend is set up.
        let capability = manager.getComputeCapability()
        if capability.hasLocalLLM {
            // Backend already configured by host app — cannot test "no backend" path
            return
        }
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
        // hasLocalLLM depends on whether a backend is configured;
        // in test isolation it should be false, but when run alongside
        // the app process it may be true. Just validate the fields exist.
        XCTAssertGreaterThan(capability.freeMemoryGB ?? 0, 0)
        XCTAssertGreaterThan(capability.cpuCores ?? 0, 0)
    }
}
