import XCTest
@testable import LocalAIAgent

@MainActor
final class SyncManagerTests: XCTestCase {

    func testSyncManagerSingleton() throws {
        let manager = SyncManager.shared
        XCTAssertNotNil(manager)
    }

    func testInitialState() throws {
        let manager = SyncManager.shared
        XCTAssertEqual(manager.baseURL, "https://chatweb.ai")
    }

    func testUserIdAccessible() throws {
        let manager = SyncManager.shared
        XCTAssertTrue(manager.userId == nil || !manager.userId!.isEmpty)
    }

    func testLogoutClearsState() throws {
        let manager = SyncManager.shared
        manager.logout()
        XCTAssertFalse(manager.isLoggedIn)
        XCTAssertNil(manager.userId)
        XCTAssertEqual(manager.creditsRemaining, 0)
    }
}
