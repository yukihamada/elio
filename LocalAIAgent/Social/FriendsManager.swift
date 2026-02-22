import Foundation
import SwiftUI

/// Manages friends list and trust relationships for P2P messaging
@MainActor
final class FriendsManager: ObservableObject {
    static let shared = FriendsManager()

    // MARK: - Published Properties

    @Published private(set) var friends: [Friend] = []
    @Published private(set) var friendRequests: [FriendRequest] = []
    @Published private(set) var onlineFriends: Set<String> = []  // Device IDs

    // MARK: - Private Properties

    private let friendsKey = "friends_list"
    private let requestsKey = "friend_requests"

    // MARK: - Initialization

    private init() {
        loadFriends()
        loadFriendRequests()
    }

    // MARK: - Friend Management

    /// Add a friend by pairing code
    func addFriend(pairingCode: String, name: String? = nil) async throws -> Friend {
        // Try to find device by pairing code from discovered P2P servers
        let matchedServer = ChatModeManager.shared.p2p?.availableServers.first {
            $0.pairingCode == pairingCode
        }
        let deviceId = matchedServer?.id ?? "device_\(pairingCode)"
        let friendName = name ?? matchedServer?.name ?? "Friend \(pairingCode)"

        let friend = Friend(
            id: UUID().uuidString,
            deviceId: deviceId,
            name: friendName,
            pairingCode: pairingCode,
            addedAt: Date(),
            lastSeen: nil,
            isOnline: false
        )

        friends.append(friend)
        saveFriends()

        return friend
    }

    /// Remove a friend
    func removeFriend(_ friend: Friend) {
        friends.removeAll { $0.id == friend.id }
        saveFriends()
    }

    /// Update friend's online status
    func updateFriendStatus(deviceId: String, isOnline: Bool, lastSeen: Date? = nil) {
        if isOnline {
            onlineFriends.insert(deviceId)
        } else {
            onlineFriends.remove(deviceId)
        }

        if let index = friends.firstIndex(where: { $0.deviceId == deviceId }) {
            friends[index].isOnline = isOnline
            if let lastSeen = lastSeen {
                friends[index].lastSeen = lastSeen
            }
            saveFriends()
        }
    }

    /// Update friend name
    func updateFriendName(_ friend: Friend, name: String) {
        if let index = friends.firstIndex(where: { $0.id == friend.id }) {
            friends[index].name = name
            saveFriends()
        }
    }

    // MARK: - Friend Requests

    /// Send friend request
    func sendFriendRequest(to deviceId: String, name: String) async throws {
        let request = FriendRequest(
            id: UUID().uuidString,
            fromDeviceId: DeviceIdentityManager.shared.deviceId,
            toDeviceId: deviceId,
            fromName: UIDevice.current.name,
            toName: name,
            sentAt: Date(),
            status: .pending
        )

        friendRequests.append(request)
        saveFriendRequests()

        // Send via P2P connection
        if let payload = try? JSONEncoder().encode(request) {
            try ChatModeManager.shared.p2p?.sendEnvelope(type: .friendRequest, payload: payload)
        }
    }

    /// Accept friend request
    func acceptFriendRequest(_ request: FriendRequest) async throws {
        // Create friend
        let friend = Friend(
            id: UUID().uuidString,
            deviceId: request.fromDeviceId,
            name: request.fromName,
            pairingCode: nil,
            addedAt: Date(),
            lastSeen: nil,
            isOnline: false
        )

        friends.append(friend)
        saveFriends()

        // Update request status
        if let index = friendRequests.firstIndex(where: { $0.id == request.id }) {
            friendRequests[index].status = .accepted
            saveFriendRequests()
        }

        // Send acceptance via P2P
        var acceptance = request
        acceptance.status = .accepted
        if let payload = try? JSONEncoder().encode(acceptance) {
            try ChatModeManager.shared.p2p?.sendEnvelope(type: .friendAcceptance, payload: payload)
        }
    }

    /// Reject friend request
    func rejectFriendRequest(_ request: FriendRequest) {
        if let index = friendRequests.firstIndex(where: { $0.id == request.id }) {
            friendRequests[index].status = .rejected
            saveFriendRequests()
        }
    }

    // MARK: - P2P Receive Handlers

    /// Handle incoming friend request from P2P
    @MainActor
    func receiveFriendRequest(_ request: FriendRequest) {
        // Avoid duplicates
        guard !friendRequests.contains(where: { $0.id == request.id }) else { return }
        friendRequests.append(request)
        saveFriendRequests()
        print("[Friends] Received friend request from \(request.fromName)")
    }

    /// Handle acceptance of a friend request we sent
    @MainActor
    func handleAcceptance(_ request: FriendRequest) {
        // Mark our outgoing request as accepted
        if let index = friendRequests.firstIndex(where: { $0.id == request.id }) {
            friendRequests[index].status = .accepted
            saveFriendRequests()
        }

        // Add as friend if not already
        guard !friends.contains(where: { $0.deviceId == request.fromDeviceId }) else { return }
        let friend = Friend(
            id: UUID().uuidString,
            deviceId: request.fromDeviceId,
            name: request.fromName,
            pairingCode: nil,
            addedAt: Date(),
            lastSeen: Date(),
            isOnline: true
        )
        friends.append(friend)
        saveFriends()
        print("[Friends] Friend request accepted by \(request.fromName)")
    }

    // MARK: - Helpers

    /// Check if device is a friend
    func isFriend(deviceId: String) -> Bool {
        return friends.contains { $0.deviceId == deviceId }
    }

    /// Get friend by device ID
    func getFriend(deviceId: String) -> Friend? {
        return friends.first { $0.deviceId == deviceId }
    }

    // MARK: - Persistence

    private func loadFriends() {
        guard let data = UserDefaults.standard.data(forKey: friendsKey),
              let decoded = try? JSONDecoder().decode([Friend].self, from: data) else {
            return
        }
        friends = decoded
    }

    private func saveFriends() {
        if let encoded = try? JSONEncoder().encode(friends) {
            UserDefaults.standard.set(encoded, forKey: friendsKey)
        }
    }

    private func loadFriendRequests() {
        guard let data = UserDefaults.standard.data(forKey: requestsKey),
              let decoded = try? JSONDecoder().decode([FriendRequest].self, from: data) else {
            return
        }
        friendRequests = decoded
    }

    private func saveFriendRequests() {
        if let encoded = try? JSONEncoder().encode(friendRequests) {
            UserDefaults.standard.set(encoded, forKey: requestsKey)
        }
    }
}

// MARK: - Models

/// Friend model
struct Friend: Identifiable, Codable {
    let id: String
    let deviceId: String
    var name: String
    let pairingCode: String?
    let addedAt: Date
    var lastSeen: Date?
    var isOnline: Bool

    var displayName: String {
        return name
    }

    var statusText: String {
        if isOnline {
            return "Online"
        } else if let lastSeen = lastSeen {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .short
            return "Last seen \(formatter.localizedString(for: lastSeen, relativeTo: Date()))"
        } else {
            return "Offline"
        }
    }
}

/// Friend request model
struct FriendRequest: Identifiable, Codable {
    let id: String
    let fromDeviceId: String
    let toDeviceId: String
    let fromName: String
    let toName: String
    let sentAt: Date
    var status: FriendRequestStatus
}

enum FriendRequestStatus: String, Codable {
    case pending
    case accepted
    case rejected
}
