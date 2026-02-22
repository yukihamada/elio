import XCTest
@testable import LocalAIAgent

@MainActor
final class ChatModeManagerTests: XCTestCase {

    // MARK: - Initialization Tests

    func testChatModeManagerSingleton() throws {
        let manager = ChatModeManager.shared
        XCTAssertNotNil(manager)
        // currentMode may vary on real devices (persisted state)
        XCTAssertTrue(ChatMode.allCases.contains(manager.currentMode))
    }

    func testInitialModeAvailability() throws {
        let manager = ChatModeManager.shared
        // ChatWeb is always available
        XCTAssertTrue(manager.isModeAvailable(.chatweb))
        // Local requires loaded model
        XCTAssertFalse(manager.isModeAvailable(.local))
    }

    // MARK: - Mode Setting Tests

    func testSetModeUpdatesCurrentMode() throws {
        let manager = ChatModeManager.shared
        let originalMode = manager.currentMode

        manager.setMode(.chatweb)
        XCTAssertEqual(manager.currentMode, .chatweb)

        // Restore
        manager.setMode(originalMode)
    }

    // MARK: - ChatMode Properties Tests

    func testAllChatModesHaveDisplayNames() throws {
        let modes: [ChatMode] = [.local, .chatweb, .fast, .genius, .privateP2P, .publicP2P, .p2pMesh, .speculative]
        for mode in modes {
            XCTAssertFalse(mode.displayName.isEmpty, "\(mode) should have a display name")
        }
    }

    // MARK: - Clear Backend Tests

    func testClearLocalBackend() throws {
        let manager = ChatModeManager.shared
        // Should not crash when called without a configured backend
        manager.clearLocalBackend()
        XCTAssertFalse(manager.isModeAvailable(.local))
    }

    // MARK: - P2P Property Tests

    func testP2PPropertyNotNil() throws {
        let manager = ChatModeManager.shared
        XCTAssertNotNil(manager.p2p, "P2P backend should be initialized")
    }
}
