import SwiftUI

/// Direct chat view for 1-on-1 messaging with a friend
struct DirectChatView: View {
    let conversation: DirectConversation

    @StateObject private var messagingManager = MessagingManager.shared
    @StateObject private var friendsManager = FriendsManager.shared
    @State private var messageText = ""
    @State private var scrollProxy: ScrollViewProxy?
    @FocusState private var isMessageFieldFocused: Bool

    private var friend: Friend? {
        friendsManager.friends.first { $0.id == conversation.friendId }
    }

    private var messages: [DirectMessage] {
        messagingManager.conversations.first { $0.id == conversation.id }?.messages ?? []
    }

    var body: some View {
        VStack(spacing: 0) {
            // Messages list
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(messages) { message in
                            MessageBubbleView(message: message)
                                .id(message.id)
                        }
                    }
                    .padding()
                }
                .onAppear {
                    scrollProxy = proxy
                    scrollToBottom()
                    markAsRead()
                }
                .onChange(of: messages.count) { _, _ in
                    scrollToBottom()
                }
            }

            // Input bar
            messageInputBar
        }
        .navigationTitle(conversation.friendName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 2) {
                    Text(conversation.friendName)
                        .font(.headline)
                    if let friend = friend {
                        Text(friend.isOnline ? "Online" : "Offline")
                            .font(.caption)
                            .foregroundColor(friend.isOnline ? .green : .secondary)
                    }
                }
            }
        }
    }

    // MARK: - Message Input Bar

    private var messageInputBar: some View {
        HStack(spacing: 12) {
            TextField("Message", text: $messageText, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...5)
                .focused($isMessageFieldFocused)

            Button {
                sendMessage()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
                    .foregroundStyle(
                        messageText.isEmpty ?
                            AnyShapeStyle(Color.gray) :
                            AnyShapeStyle(LinearGradient(
                                colors: [.blue, .purple],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ))
                    )
            }
            .disabled(messageText.isEmpty)
        }
        .padding()
        .background(Color(.systemBackground))
    }

    // MARK: - Actions

    private func sendMessage() {
        guard !messageText.isEmpty, let friend = friend else { return }

        let text = messageText
        messageText = ""

        Task {
            do {
                try await messagingManager.sendMessage(to: friend, content: text)
                scrollToBottom()
            } catch {
                print("[DirectChat] Failed to send message: \(error)")
            }
        }
    }

    private func scrollToBottom() {
        guard let lastMessage = messages.last else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            withAnimation {
                scrollProxy?.scrollTo(lastMessage.id, anchor: .bottom)
            }
        }
    }

    private func markAsRead() {
        messagingManager.markAsRead(conversation: conversation)
    }
}

// MARK: - Message Bubble

struct MessageBubbleView: View {
    let message: DirectMessage

    var body: some View {
        HStack {
            if message.isFromMe {
                Spacer()
            }

            VStack(alignment: message.isFromMe ? .trailing : .leading, spacing: 4) {
                Text(message.content)
                    .padding(12)
                    .background(
                        message.isFromMe ?
                            AnyShapeStyle(LinearGradient(
                                colors: [.blue, .purple],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )) :
                            AnyShapeStyle(Color(.systemGray5))
                    )
                    .foregroundColor(message.isFromMe ? .white : .primary)
                    .cornerRadius(16)

                HStack(spacing: 4) {
                    Text(message.sentAt, style: .time)
                        .font(.caption2)
                        .foregroundColor(.secondary)

                    if message.isFromMe {
                        Image(systemName: message.statusIcon)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .frame(maxWidth: 280, alignment: message.isFromMe ? .trailing : .leading)

            if !message.isFromMe {
                Spacer()
            }
        }
    }
}

#Preview {
    NavigationStack {
        DirectChatView(
            conversation: DirectConversation(
                id: "1",
                friendId: "friend1",
                friendName: "Alice",
                messages: [
                    DirectMessage(
                        id: "1",
                        senderId: "friend1",
                        recipientId: "me",
                        content: "Hey! How are you?",
                        sentAt: Date().addingTimeInterval(-3600),
                        deliveredAt: Date().addingTimeInterval(-3500),
                        readAt: Date().addingTimeInterval(-3400),
                        isFromMe: false
                    ),
                    DirectMessage(
                        id: "2",
                        senderId: "me",
                        recipientId: "friend1",
                        content: "I'm good! Thanks for asking",
                        sentAt: Date().addingTimeInterval(-3300),
                        deliveredAt: Date().addingTimeInterval(-3200),
                        readAt: nil,
                        isFromMe: true
                    )
                ],
                lastMessageAt: Date(),
                unreadCount: 0
            )
        )
    }
}
