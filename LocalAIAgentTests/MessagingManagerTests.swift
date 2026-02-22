import XCTest
@testable import LocalAIAgent

@MainActor
final class MessagingManagerTests: XCTestCase {

    // MARK: - Initialization

    func testMessagingManagerSingleton() throws {
        let manager = MessagingManager.shared
        XCTAssertNotNil(manager)
    }

    // MARK: - Conversation Management

    func testGetOrCreateConversation() async throws {
        let friend = try await FriendsManager.shared.addFriend(pairingCode: "1111", name: "Msg Test")
        let conversation = MessagingManager.shared.getOrCreateConversation(with: friend)
        XCTAssertEqual(conversation.friendId, friend.id)
        XCTAssertEqual(conversation.friendName, friend.name)

        // Getting again should return same conversation
        let same = MessagingManager.shared.getOrCreateConversation(with: friend)
        XCTAssertEqual(conversation.id, same.id)

        // Cleanup
        FriendsManager.shared.removeFriend(friend)
    }

    // MARK: - Message Receive

    func testReceiveMessageFromUnknownSender() throws {
        let message = DirectMessage(
            id: UUID().uuidString,
            senderId: "unknown-device-\(UUID().uuidString)",
            recipientId: "local",
            content: "Hello",
            sentAt: Date(),
            deliveredAt: nil,
            readAt: nil,
            isFromMe: false
        )

        // Should not crash
        MessagingManager.shared.receiveMessage(message)
    }

    // MARK: - Unread Count

    func testInitialUnreadCount() throws {
        let manager = MessagingManager.shared
        XCTAssertGreaterThanOrEqual(manager.unreadCount, 0)
    }
}
