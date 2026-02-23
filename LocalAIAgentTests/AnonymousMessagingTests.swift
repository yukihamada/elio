import XCTest
import CryptoKit
@testable import LocalAIAgent

@MainActor
final class AnonymousMessagingTests: XCTestCase {

    // MARK: - Anonymous Alias Tests

    func testAnonymousAliasConsistency() {
        // Same device ID should always produce the same alias
        let deviceId = "test-device-123"
        let alias1 = anonymousAlias(for: deviceId)
        let alias2 = anonymousAlias(for: deviceId)
        XCTAssertEqual(alias1, alias2, "Same device ID should produce same alias")
    }

    func testAnonymousAliasDifferentDevices() {
        let alias1 = anonymousAlias(for: "device-A")
        let alias2 = anonymousAlias(for: "device-B")
        XCTAssertNotEqual(alias1, alias2, "Different devices should have different aliases")
    }

    func testAnonymousAliasLength() {
        let alias = anonymousAlias(for: "any-device")
        XCTAssertEqual(alias.count, 16, "Alias should be 16 hex characters (8 bytes)")
    }

    func testAnonymousAliasDoesNotContainDeviceId() {
        let deviceId = "elio-device-abc123def456"
        let alias = anonymousAlias(for: deviceId)
        XCTAssertFalse(alias.contains("abc123"), "Alias should not contain original device ID parts")
        XCTAssertFalse(alias.contains("elio-device"), "Alias should not contain device prefix")
    }

    func testAnonymousAliasIsHex() {
        let alias = anonymousAlias(for: "test-device")
        let hexChars = CharacterSet(charactersIn: "0123456789abcdef")
        XCTAssertTrue(
            alias.unicodeScalars.allSatisfy { hexChars.contains($0) },
            "Alias should only contain hex characters"
        )
    }

    // MARK: - DirectMessage Anonymity

    func testDirectMessageDoesNotLeakRealId() {
        let realDeviceId = "elio-device-real-id-12345"
        let message = DirectMessage(
            id: UUID().uuidString,
            senderId: anonymousAlias(for: realDeviceId),
            recipientId: anonymousAlias(for: "other-device"),
            content: "Hello",
            sentAt: Date(),
            deliveredAt: nil,
            readAt: nil,
            isFromMe: true
        )

        XCTAssertFalse(message.senderId.contains("elio-device"), "Sender ID should be anonymous")
        XCTAssertFalse(message.recipientId.contains("other-device"), "Recipient ID should be anonymous")
        XCTAssertEqual(message.senderId.count, 16)
    }

    // MARK: - Message Status Icons

    func testMessageStatusIcons() {
        let sending = DirectMessage(id: "1", senderId: "a", recipientId: "b", content: "test",
                                    sentAt: Date(), deliveredAt: nil, readAt: nil, isFromMe: true)
        XCTAssertEqual(sending.statusIcon, "clock")

        var delivered = sending
        delivered.deliveredAt = Date()
        XCTAssertEqual(delivered.statusIcon, "checkmark.circle")

        var read = delivered
        read.readAt = Date()
        XCTAssertEqual(read.statusIcon, "checkmark.circle.fill")
    }

    // MARK: - QR Code URL Parsing

    func testParsePeerQRCode() {
        let url = "elio://peer?code=1234&name=Elio%20User"
        let components = URLComponents(string: url)
        let code = components?.queryItems?.first(where: { $0.name == "code" })?.value
        let name = components?.queryItems?.first(where: { $0.name == "name" })?.value

        XCTAssertEqual(code, "1234")
        XCTAssertEqual(name, "Elio User")
    }

    func testParseFriendQRCode() {
        let url = "elio://friend?code=5678&name=Elio%20User&id=abcdef0123456789"
        let components = URLComponents(string: url)
        let code = components?.queryItems?.first(where: { $0.name == "code" })?.value
        let anonId = components?.queryItems?.first(where: { $0.name == "id" })?.value

        XCTAssertEqual(code, "5678")
        XCTAssertEqual(anonId, "abcdef0123456789")
        XCTAssertEqual(anonId?.count, 16, "ID in QR should be anonymous 16-char hex")
    }

    func testParseChatWebQRCode() {
        let url = "https://chatweb.ai/?ref=elio&channel=elio"
        XCTAssertTrue(url.contains("chatweb.ai"), "Should detect chatweb.ai URL")
    }

    func testParseUnknownQRCode() {
        let url = "https://example.com/random"
        XCTAssertFalse(url.contains("chatweb.ai"))
        XCTAssertFalse(url.hasPrefix("elio://"))
    }

    // MARK: - Conversation Dedup

    func testConversationLastMessagePreview() {
        let conv = DirectConversation(
            id: "1", friendId: "f1", friendName: "Test",
            messages: [
                DirectMessage(id: "1", senderId: "a", recipientId: "b", content: "First",
                              sentAt: Date().addingTimeInterval(-60), deliveredAt: nil, readAt: nil, isFromMe: true),
                DirectMessage(id: "2", senderId: "b", recipientId: "a", content: "Second",
                              sentAt: Date(), deliveredAt: nil, readAt: nil, isFromMe: false),
            ],
            lastMessageAt: Date(), unreadCount: 1
        )

        XCTAssertEqual(conv.lastMessagePreview, "Second")
        XCTAssertEqual(conv.lastMessage?.id, "2")
    }

    func testEmptyConversationPreview() {
        let conv = DirectConversation(
            id: "1", friendId: "f1", friendName: "Test",
            messages: [], lastMessageAt: Date(), unreadCount: 0
        )
        XCTAssertEqual(conv.lastMessagePreview, "No messages yet")
    }

    // MARK: - Helper

    private func anonymousAlias(for deviceId: String) -> String {
        let data = Data((deviceId + "elio-anon-salt-v1").utf8)
        let hash = SHA256.hash(data: data)
        return hash.prefix(8).map { String(format: "%02x", $0) }.joined()
    }
}
