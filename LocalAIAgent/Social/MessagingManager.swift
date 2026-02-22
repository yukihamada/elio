import Foundation
import SwiftUI

/// Manages direct messaging with friends (P2P + Internet)
@MainActor
final class MessagingManager: ObservableObject {
    static let shared = MessagingManager()

    // MARK: - Published Properties

    @Published private(set) var conversations: [DirectConversation] = []
    @Published private(set) var unreadCount: Int = 0

    // MARK: - Private Properties

    private let conversationsKey = "direct_conversations"
    private let friendsManager = FriendsManager.shared

    // MARK: - Initialization

    private init() {
        loadConversations()
        calculateUnreadCount()
    }

    // MARK: - Conversation Management

    /// Get or create conversation with a friend
    func getOrCreateConversation(with friend: Friend) -> DirectConversation {
        if let existing = conversations.first(where: { $0.friendId == friend.id }) {
            return existing
        }

        let conversation = DirectConversation(
            id: UUID().uuidString,
            friendId: friend.id,
            friendName: friend.name,
            messages: [],
            lastMessageAt: Date(),
            unreadCount: 0
        )

        conversations.append(conversation)
        saveConversations()

        return conversation
    }

    /// Send message to friend
    func sendMessage(to friend: Friend, content: String) async throws {
        let message = DirectMessage(
            id: UUID().uuidString,
            senderId: DeviceIdentityManager.shared.deviceId,
            recipientId: friend.deviceId,
            content: content,
            sentAt: Date(),
            deliveredAt: nil,
            readAt: nil,
            isFromMe: true
        )

        // Add to conversation
        if let index = conversations.firstIndex(where: { $0.friendId == friend.id }) {
            conversations[index].messages.append(message)
            conversations[index].lastMessageAt = message.sentAt
            saveConversations()
        }

        // Send via P2P if online
        if friend.isOnline {
            try await sendViaP2P(message: message, to: friend)
        } else {
            // TODO: Queue for later delivery or send via internet
            print("[Messaging] Friend offline, message queued")
        }
    }

    /// Receive message from friend
    func receiveMessage(_ message: DirectMessage) {
        guard let friend = friendsManager.getFriend(deviceId: message.senderId) else {
            print("[Messaging] Message from unknown sender")
            return
        }

        // Add to conversation
        if let index = conversations.firstIndex(where: { $0.friendId == friend.id }) {
            conversations[index].messages.append(message)
            conversations[index].lastMessageAt = message.sentAt
            conversations[index].unreadCount += 1
        } else {
            // Create new conversation
            var conversation = DirectConversation(
                id: UUID().uuidString,
                friendId: friend.id,
                friendName: friend.name,
                messages: [message],
                lastMessageAt: message.sentAt,
                unreadCount: 1
            )
            conversations.append(conversation)
        }

        saveConversations()
        calculateUnreadCount()
    }

    /// Mark conversation as read
    func markAsRead(conversation: DirectConversation) {
        if let index = conversations.firstIndex(where: { $0.id == conversation.id }) {
            conversations[index].unreadCount = 0
            saveConversations()
            calculateUnreadCount()
        }
    }

    /// Delete conversation
    func deleteConversation(_ conversation: DirectConversation) {
        conversations.removeAll { $0.id == conversation.id }
        saveConversations()
        calculateUnreadCount()
    }

    // MARK: - P2P Messaging

    private func sendViaP2P(message: DirectMessage, to friend: Friend) async throws {
        guard let connection = PrivateServerManager.shared.serverPeerConnections[friend.deviceId] else {
            throw MessagingError.peerNotConnected
        }

        let envelope = P2PEnvelope(
            type: .directMessage,
            payload: try JSONEncoder().encode(message)
        )

        let data = try JSONEncoder().encode(envelope)
        var framedData = data
        framedData.append(contentsOf: [0x0A])

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: framedData, completion: .contentProcessed { error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            })
        }

        // Mark as delivered
        if let convIndex = conversations.firstIndex(where: { $0.friendId == friend.id }),
           let msgIndex = conversations[convIndex].messages.firstIndex(where: { $0.id == message.id }) {
            conversations[convIndex].messages[msgIndex].deliveredAt = Date()
            saveConversations()
        }
    }

    // MARK: - Helpers

    private func calculateUnreadCount() {
        unreadCount = conversations.reduce(0) { $0 + $1.unreadCount }
    }

    // MARK: - Persistence

    private func loadConversations() {
        guard let data = UserDefaults.standard.data(forKey: conversationsKey),
              let decoded = try? JSONDecoder().decode([DirectConversation].self, from: data) else {
            return
        }
        conversations = decoded
    }

    private func saveConversations() {
        if let encoded = try? JSONEncoder().encode(conversations) {
            UserDefaults.standard.set(encoded, forKey: conversationsKey)
        }
    }
}

// MARK: - Models

/// Direct conversation with a friend
struct DirectConversation: Identifiable, Codable {
    let id: String
    let friendId: String
    var friendName: String
    var messages: [DirectMessage]
    var lastMessageAt: Date
    var unreadCount: Int

    var lastMessage: DirectMessage? {
        return messages.last
    }

    var lastMessagePreview: String {
        guard let last = lastMessage else { return "No messages yet" }
        return last.content
    }
}

/// Direct message model
struct DirectMessage: Identifiable, Codable {
    let id: String
    let senderId: String
    let recipientId: String
    let content: String
    let sentAt: Date
    var deliveredAt: Date?
    var readAt: Date?
    let isFromMe: Bool

    var statusIcon: String {
        if let _ = readAt {
            return "checkmark.circle.fill"  // Read
        } else if let _ = deliveredAt {
            return "checkmark.circle"  // Delivered
        } else {
            return "clock"  // Sending
        }
    }
}

// MARK: - Errors

enum MessagingError: Error, LocalizedError {
    case peerNotConnected
    case sendFailed

    var errorDescription: String? {
        switch self {
        case .peerNotConnected:
            return "Friend is not connected"
        case .sendFailed:
            return "Failed to send message"
        }
    }
}
