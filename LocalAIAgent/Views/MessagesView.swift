import SwiftUI

/// Main messages view showing all direct conversations
struct MessagesView: View {
    @StateObject private var messagingManager = MessagingManager.shared
    @StateObject private var friendsManager = FriendsManager.shared
    @State private var showingAddFriend = false
    @State private var showingFriendsList = false

    var body: some View {
        NavigationStack {
            ZStack {
                if messagingManager.conversations.isEmpty {
                    // Empty state
                    emptyStateView
                } else {
                    // Conversations list
                    conversationsListView
                }
            }
            .navigationTitle("Messages")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            showingAddFriend = true
                        } label: {
                            Label("Add Friend", systemImage: "person.badge.plus")
                        }

                        Button {
                            showingFriendsList = true
                        } label: {
                            Label("Friends List", systemImage: "person.2")
                        }
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                    }
                }
            }
            .sheet(isPresented: $showingAddFriend) {
                AddFriendView()
            }
            .sheet(isPresented: $showingFriendsList) {
                FriendsListView()
            }
        }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 80))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.blue, .purple],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Text("No Messages Yet")
                .font(.title2)
                .fontWeight(.bold)

            Text("Add friends to start chatting")
                .font(.subheadline)
                .foregroundColor(.secondary)

            Button {
                showingAddFriend = true
            } label: {
                Label("Add Friend", systemImage: "person.badge.plus")
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding()
                    .background(
                        LinearGradient(
                            colors: [.blue, .purple],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .cornerRadius(12)
            }
            .padding(.top, 10)
        }
        .padding()
    }

    // MARK: - Conversations List

    private var conversationsListView: some View {
        List {
            ForEach(messagingManager.conversations.sorted(by: { $0.lastMessageAt > $1.lastMessageAt })) { conversation in
                NavigationLink(destination: DirectChatView(conversation: conversation)) {
                    ConversationRow(conversation: conversation)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        messagingManager.deleteConversation(conversation)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
        .listStyle(.plain)
    }
}

/// Conversation row in the list
struct ConversationRow: View {
    let conversation: DirectConversation
    @StateObject private var friendsManager = FriendsManager.shared

    private var friend: Friend? {
        friendsManager.friends.first { $0.id == conversation.friendId }
    }

    var body: some View {
        HStack(spacing: 15) {
            // Avatar
            Circle()
                .fill(
                    LinearGradient(
                        colors: [.blue, .purple],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 56, height: 56)
                .overlay(
                    Text(String(conversation.friendName.prefix(1)))
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                )
                .overlay(
                    Circle()
                        .fill(friend?.isOnline == true ? Color.green : Color.gray)
                        .frame(width: 16, height: 16)
                        .offset(x: 20, y: 20)
                )

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(conversation.friendName)
                        .font(.headline)

                    Spacer()

                    Text(conversation.lastMessageAt, style: .relative)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                HStack {
                    Text(conversation.lastMessagePreview)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(1)

                    Spacer()

                    if conversation.unreadCount > 0 {
                        Text("\(conversation.unreadCount)")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.blue)
                            .cornerRadius(10)
                    }
                }
            }
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Add Friend View

struct AddFriendView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var friendsManager = FriendsManager.shared
    @State private var pairingCode = ""
    @State private var friendName = ""
    @State private var isAdding = false
    @State private var error: Error?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Pairing Code", text: $pairingCode)
                        .keyboardType(.numberPad)
                        .font(.system(.title3, design: .monospaced))

                    TextField("Friend Name (Optional)", text: $friendName)
                } header: {
                    Text("Add Friend")
                } footer: {
                    Text("Enter your friend's 4-digit pairing code from their server settings")
                }

                if let error = error {
                    Section {
                        Text(error.localizedDescription)
                            .foregroundColor(.red)
                    }
                }

                Section {
                    Button {
                        addFriend()
                    } label: {
                        if isAdding {
                            HStack {
                                ProgressView()
                                Text("Adding...")
                            }
                        } else {
                            Text("Add Friend")
                        }
                    }
                    .disabled(pairingCode.count != 4 || isAdding)
                }
            }
            .navigationTitle("Add Friend")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func addFriend() {
        isAdding = true
        error = nil

        Task {
            do {
                _ = try await friendsManager.addFriend(
                    pairingCode: pairingCode,
                    name: friendName.isEmpty ? nil : friendName
                )
                dismiss()
            } catch {
                self.error = error
            }
            isAdding = false
        }
    }
}

// MARK: - Friends List View

struct FriendsListView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var friendsManager = FriendsManager.shared
    @StateObject private var messagingManager = MessagingManager.shared

    var body: some View {
        NavigationStack {
            List {
                ForEach(friendsManager.friends) { friend in
                    NavigationLink(destination: DirectChatView(
                        conversation: messagingManager.getOrCreateConversation(with: friend)
                    )) {
                        FriendRow(friend: friend)
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            friendsManager.removeFriend(friend)
                        } label: {
                            Label("Remove", systemImage: "trash")
                        }
                    }
                }
            }
            .navigationTitle("Friends")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct FriendRow: View {
    let friend: Friend

    var body: some View {
        HStack(spacing: 15) {
            // Avatar
            Circle()
                .fill(
                    LinearGradient(
                        colors: [.green, .blue],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 44, height: 44)
                .overlay(
                    Text(String(friend.name.prefix(1)))
                        .font(.headline)
                        .foregroundColor(.white)
                )
                .overlay(
                    Circle()
                        .fill(friend.isOnline ? Color.green : Color.gray)
                        .frame(width: 14, height: 14)
                        .offset(x: 16, y: 16)
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(friend.displayName)
                    .font(.headline)

                Text(friend.statusText)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    MessagesView()
}
