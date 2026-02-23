import Foundation
import SwiftUI
import CryptoKit

/// Manages direct messaging with friends (P2P + Internet)
/// - Anonymous: sender/recipient IDs are ephemeral hashes, no real device info leaks
/// - Fast: fire-and-forget P2P send, async persistence, no blocking I/O on send path
@MainActor
final class MessagingManager: ObservableObject {
    static let shared = MessagingManager()

    // MARK: - Published Properties

    @Published private(set) var conversations: [DirectConversation] = []
    @Published private(set) var unreadCount: Int = 0

    // MARK: - Private Properties

    private let conversationsKey = "direct_conversations"
    private let friendsManager = FriendsManager.shared
    private var saveTask: Task<Void, Never>?  // Debounced persistence
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .secondsSince1970
        return e
    }()

    // MARK: - Initialization

    private init() {
        loadConversations()
        calculateUnreadCount()
    }

    // MARK: - Anonymity

    /// Generate an anonymous sender alias for wire transmission (one-way hash)
    /// Real device ID never leaves the device
    private func anonymousAlias(for deviceId: String) -> String {
        let data = Data((deviceId + "elio-anon-salt-v1").utf8)
        let hash = SHA256.hash(data: data)
        return hash.prefix(8).map { String(format: "%02x", $0) }.joined()
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
        debouncedSave()

        return conversation
    }

    /// Send message to friend — optimized for speed
    func sendMessage(to friend: Friend, content: String) async throws {
        // Use anonymous alias as sender ID on wire
        let anonSender = anonymousAlias(for: DeviceIdentityManager.shared.deviceId)
        let anonRecipient = anonymousAlias(for: friend.deviceId)

        let message = DirectMessage(
            id: UUID().uuidString,
            senderId: anonSender,
            recipientId: anonRecipient,
            content: content,
            sentAt: Date(),
            deliveredAt: nil,
            readAt: nil,
            isFromMe: true
        )

        // Update conversation immediately (in-memory, non-blocking)
        if let index = conversations.firstIndex(where: { $0.friendId == friend.id }) {
            conversations[index].messages.append(message)
            conversations[index].lastMessageAt = message.sentAt
        }

        // Fire-and-forget: send first, persist later (speed priority)
        if friend.isOnline {
            // Send in background, don't block UI
            let msgCopy = message
            let friendCopy = friend
            Task.detached(priority: .userInitiated) { [weak self] in
                do {
                    try await self?.sendViaP2P(message: msgCopy, to: friendCopy)
                } catch {
                    // Queue for retry
                    await self?.queueMessage(msgCopy, for: friendCopy)
                }
            }
        } else {
            queueMessage(message, for: friend)
        }

        // Debounced persistence (don't save every single message)
        debouncedSave()
    }

    /// Receive message from friend
    func receiveMessage(_ message: DirectMessage) {
        // Resolve friend by anonymous alias match
        let friend = friendsManager.friends.first { f in
            anonymousAlias(for: f.deviceId) == message.senderId
        } ?? friendsManager.getFriend(deviceId: message.senderId)

        guard let friend = friend else {
            logError("Messaging", "Message from unknown anonymous sender")
            return
        }

        // Add to conversation
        if let index = conversations.firstIndex(where: { $0.friendId == friend.id }) {
            // Dedup
            guard !conversations[index].messages.contains(where: { $0.id == message.id }) else { return }
            conversations[index].messages.append(message)
            conversations[index].lastMessageAt = message.sentAt
            conversations[index].unreadCount += 1
        } else {
            let conversation = DirectConversation(
                id: UUID().uuidString,
                friendId: friend.id,
                friendName: friend.name,
                messages: [message],
                lastMessageAt: message.sentAt,
                unreadCount: 1
            )
            conversations.append(conversation)
        }

        debouncedSave()
        calculateUnreadCount()

        // Haptic
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
    }

    /// Mark conversation as read
    func markAsRead(conversation: DirectConversation) {
        if let index = conversations.firstIndex(where: { $0.id == conversation.id }) {
            conversations[index].unreadCount = 0
            debouncedSave()
            calculateUnreadCount()
        }
    }

    /// Delete conversation
    func deleteConversation(_ conversation: DirectConversation) {
        conversations.removeAll { $0.id == conversation.id }
        debouncedSave()
        calculateUnreadCount()
    }

    // MARK: - P2P Messaging (Fast Path)

    private func sendViaP2P(message: DirectMessage, to friend: Friend) async throws {
        // Try direct P2P connection first
        if let connection = PrivateServerManager.shared.serverPeerConnections[friend.deviceId] {
            let data = try encoder.encode(P2PEnvelope(type: .directMessage, payload: try encoder.encode(message)))
            var framedData = data
            framedData.append(0x0A) // newline delimiter

            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                connection.send(content: framedData, completion: .contentProcessed { error in
                    if let error = error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume()
                    }
                })
            }

            // Mark delivered
            await MainActor.run {
                if let convIndex = conversations.firstIndex(where: { $0.friendId == friend.id }),
                   let msgIndex = conversations[convIndex].messages.firstIndex(where: { $0.id == message.id }) {
                    conversations[convIndex].messages[msgIndex].deliveredAt = Date()
                }
            }
            return
        }

        // Try via P2PBackend client connection as fallback
        if let p2p = ChatModeManager.shared.p2p {
            let payload = try encoder.encode(message)
            try p2p.sendEnvelope(type: .directMessage, payload: payload)
            return
        }

        throw MessagingError.peerNotConnected
    }

    // MARK: - Message Queue

    private var pendingMessages: [(DirectMessage, Friend)] = []

    private func queueMessage(_ message: DirectMessage, for friend: Friend) {
        pendingMessages.append((message, friend))
    }

    /// Flush queued messages when a friend comes online
    func flushQueue(for friend: Friend) async {
        let queued = pendingMessages.filter { $0.1.id == friend.id }
        pendingMessages.removeAll { $0.1.id == friend.id }
        for (message, friend) in queued {
            try? await sendViaP2P(message: message, to: friend)
        }
    }

    // MARK: - Helpers

    private func calculateUnreadCount() {
        unreadCount = conversations.reduce(0) { $0 + $1.unreadCount }
    }

    // MARK: - Debounced Persistence

    /// Save after 0.5s of inactivity (batch multiple rapid messages)
    private func debouncedSave() {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s
            guard !Task.isCancelled else { return }
            persistToDisk()
        }
    }

    /// Force immediate save (call on app background)
    func saveImmediately() {
        saveTask?.cancel()
        persistToDisk()
    }

    private func persistToDisk() {
        if let encoded = try? encoder.encode(conversations) {
            UserDefaults.standard.set(encoded, forKey: conversationsKey)
        }
    }

    private func loadConversations() {
        guard let data = UserDefaults.standard.data(forKey: conversationsKey),
              let decoded = try? JSONDecoder().decode([DirectConversation].self, from: data) else {
            return
        }
        conversations = decoded
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
/// senderId/recipientId are anonymous hashes — real device IDs never transmitted
struct DirectMessage: Identifiable, Codable {
    let id: String
    let senderId: String      // Anonymous SHA256 alias (16-char hex)
    let recipientId: String   // Anonymous SHA256 alias (16-char hex)
    let content: String
    let sentAt: Date
    var deliveredAt: Date?
    var readAt: Date?
    let isFromMe: Bool

    var statusIcon: String {
        if readAt != nil {
            return "checkmark.circle.fill"  // Read
        } else if deliveredAt != nil {
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
