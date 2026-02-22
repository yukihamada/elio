import XCTest
@testable import LocalAIAgent

@MainActor
final class FriendsManagerTests: XCTestCase {

    // MARK: - Initialization

    func testFriendsManagerSingleton() throws {
        let manager = FriendsManager.shared
        XCTAssertNotNil(manager)
    }

    // MARK: - Friend Management

    func testAddFriendByPairingCode() async throws {
        let manager = FriendsManager.shared
        let initialCount = manager.friends.count

        let friend = try await manager.addFriend(pairingCode: "9999", name: "Test Friend")
        XCTAssertEqual(friend.name, "Test Friend")
        XCTAssertEqual(manager.friends.count, initialCount + 1)

        // Cleanup
        manager.removeFriend(friend)
        XCTAssertEqual(manager.friends.count, initialCount)
    }

    func testIsFriend() async throws {
        let manager = FriendsManager.shared
        let friend = try await manager.addFriend(pairingCode: "8888", name: "Check Friend")

        XCTAssertTrue(manager.isFriend(deviceId: friend.deviceId))
        XCTAssertFalse(manager.isFriend(deviceId: "nonexistent-device"))

        // Cleanup
        manager.removeFriend(friend)
    }

    func testGetFriend() async throws {
        let manager = FriendsManager.shared
        let friend = try await manager.addFriend(pairingCode: "7777", name: "Get Friend")

        let found = manager.getFriend(deviceId: friend.deviceId)
        XCTAssertNotNil(found)
        XCTAssertEqual(found?.name, "Get Friend")

        XCTAssertNil(manager.getFriend(deviceId: "nonexistent"))

        // Cleanup
        manager.removeFriend(friend)
    }

    // MARK: - Friend Request Tests

    func testReceiveFriendRequest() throws {
        let manager = FriendsManager.shared
        let initialCount = manager.friendRequests.count

        let request = FriendRequest(
            id: "test-req-\(UUID().uuidString)",
            fromDeviceId: "remote-device",
            toDeviceId: "local-device",
            fromName: "Remote User",
            toName: "Local User",
            sentAt: Date(),
            status: .pending
        )

        manager.receiveFriendRequest(request)
        XCTAssertEqual(manager.friendRequests.count, initialCount + 1)

        // Duplicate should be ignored
        manager.receiveFriendRequest(request)
        XCTAssertEqual(manager.friendRequests.count, initialCount + 1)
    }

    func testHandleAcceptance() throws {
        let manager = FriendsManager.shared
        let initialFriendCount = manager.friends.count

        let request = FriendRequest(
            id: "accept-req-\(UUID().uuidString)",
            fromDeviceId: "accepted-device-\(UUID().uuidString)",
            toDeviceId: "local-device",
            fromName: "Accepted User",
            toName: "Local User",
            sentAt: Date(),
            status: .accepted
        )

        manager.handleAcceptance(request)
        XCTAssertEqual(manager.friends.count, initialFriendCount + 1)

        // Cleanup
        if let friend = manager.friends.last {
            manager.removeFriend(friend)
        }
    }

    func testRejectFriendRequest() throws {
        let manager = FriendsManager.shared

        let request = FriendRequest(
            id: "reject-req-\(UUID().uuidString)",
            fromDeviceId: "reject-device",
            toDeviceId: "local-device",
            fromName: "Reject User",
            toName: "Local User",
            sentAt: Date(),
            status: .pending
        )

        manager.receiveFriendRequest(request)
        manager.rejectFriendRequest(request)

        let found = manager.friendRequests.first { $0.id == request.id }
        XCTAssertEqual(found?.status, .rejected)
    }
}
