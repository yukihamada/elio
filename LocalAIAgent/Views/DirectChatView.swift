import SwiftUI

/// Direct chat view for 1-on-1 messaging with a friend
/// Modern iMessage-style UI with bubbles, typing indicator, and smooth animations
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

    /// Group messages by date for section headers
    private var groupedMessages: [(date: String, messages: [DirectMessage])] {
        let formatter = DateFormatter()
        formatter.doesRelativeDateFormatting = true
        formatter.dateStyle = .medium
        formatter.timeStyle = .none

        let grouped = Dictionary(grouping: messages) { msg in
            formatter.string(from: msg.sentAt)
        }
        return grouped.sorted { lhs, rhs in
            (lhs.value.first?.sentAt ?? .distantPast) < (rhs.value.first?.sentAt ?? .distantPast)
        }.map { (date: $0.key, messages: $0.value) }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Messages
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 4) {
                        // Encryption badge
                        encryptionBadge
                            .padding(.top, 8)

                        ForEach(groupedMessages, id: \.date) { group in
                            // Date header
                            Text(group.date)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.secondary)
                                .padding(.vertical, 8)

                            ForEach(Array(group.messages.enumerated()), id: \.element.id) { index, message in
                                let showTail = index == group.messages.count - 1
                                    || group.messages[safe: index + 1]?.isFromMe != message.isFromMe
                                MessageBubbleView(message: message, showTail: showTail)
                                    .id(message.id)
                                    .transition(.asymmetric(
                                        insertion: .scale(scale: 0.9).combined(with: .opacity),
                                        removal: .opacity
                                    ))
                            }
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 8)
                }
                .scrollDismissesKeyboard(.interactively)
                .onAppear {
                    scrollProxy = proxy
                    scrollToBottom(animated: false)
                    markAsRead()
                    // Restore per-conversation draft
                    if messageText.isEmpty, let saved = UserDefaults.standard.string(forKey: "direct_chat_draft_\(conversation.id)"), !saved.isEmpty {
                        messageText = saved
                    }
                }
                .onChange(of: messages.count) { _, _ in
                    scrollToBottom(animated: true)
                }
                .onChange(of: messageText) { _, newValue in
                    let key = "direct_chat_draft_\(conversation.id)"
                    if newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        UserDefaults.standard.removeObject(forKey: key)
                    } else {
                        UserDefaults.standard.set(newValue, forKey: key)
                    }
                }
            }

            Divider()

            // Input bar
            messageInputBar
        }
        .background(Color(.systemGroupedBackground))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 1) {
                    Text(conversation.friendName)
                        .font(.system(size: 16, weight: .semibold))
                    if let friend = friend {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(friend.isOnline ? Color.green : Color.gray.opacity(0.5))
                                .frame(width: 7, height: 7)
                            Text(friend.isOnline ? "オンライン" : "オフライン")
                                .font(.system(size: 11))
                                .foregroundStyle(friend.isOnline ? .green : .secondary)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Encryption Badge

    private var encryptionBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: "lock.fill")
                .font(.system(size: 10))
            Text("P2P暗号化通信")
                .font(.system(size: 11, weight: .medium))
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            Capsule().fill(Color(.tertiarySystemFill))
        )
    }

    // MARK: - Input Bar

    private var messageInputBar: some View {
        HStack(alignment: .bottom, spacing: 8) {
            // Text field
            TextField("メッセージ", text: $messageText, axis: .vertical)
                .lineLimit(1...6)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color(.tertiarySystemFill))
                )
                .focused($isMessageFieldFocused)
                .onSubmit { sendMessage() }

            // Send button
            Button(action: sendMessage) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(
                        messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            ? AnyShapeStyle(Color.gray.opacity(0.4))
                            : AnyShapeStyle(LinearGradient(
                                colors: [.blue, .purple],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ))
                    )
            }
            .disabled(messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .scaleEffect(messageText.isEmpty ? 0.9 : 1.0)
            .animation(.spring(response: 0.3), value: messageText.isEmpty)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }

    // MARK: - Actions

    private func sendMessage() {
        let text = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let friend = friend else { return }

        // Haptic
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()

        messageText = ""
        UserDefaults.standard.removeObject(forKey: "direct_chat_draft_\(conversation.id)")

        Task {
            do {
                try await messagingManager.sendMessage(to: friend, content: text)
                scrollToBottom(animated: true)
            } catch {
                logError("DirectChat", "Failed to send: \(error.localizedDescription)")
            }
        }
    }

    private func scrollToBottom(animated: Bool) {
        guard let lastMessage = messages.last else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            if animated {
                withAnimation(.easeOut(duration: 0.2)) {
                    scrollProxy?.scrollTo(lastMessage.id, anchor: .bottom)
                }
            } else {
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
    var showTail: Bool = true

    var body: some View {
        HStack(alignment: .bottom, spacing: 4) {
            if message.isFromMe { Spacer(minLength: 60) }

            VStack(alignment: message.isFromMe ? .trailing : .leading, spacing: 2) {
                Text(message.content)
                    .font(.system(size: 16))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(bubbleBackground)
                    .foregroundStyle(message.isFromMe ? .white : .primary)
                    .clipShape(BubbleShape(isFromMe: message.isFromMe, showTail: showTail))

                // Timestamp + status
                HStack(spacing: 3) {
                    Text(message.sentAt, style: .time)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)

                    if message.isFromMe {
                        Image(systemName: message.statusIcon)
                            .font(.system(size: 9))
                            .foregroundStyle(message.readAt != nil ? Color.blue : Color.gray.opacity(0.5))
                    }
                }
                .padding(.horizontal, 4)
            }
            .frame(maxWidth: 280, alignment: message.isFromMe ? .trailing : .leading)

            if !message.isFromMe { Spacer(minLength: 60) }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, showTail ? 2 : 0)
    }

    @ViewBuilder
    private var bubbleBackground: some View {
        if message.isFromMe {
            LinearGradient(
                colors: [Color(red: 0.0, green: 0.48, blue: 1.0), Color(red: 0.35, green: 0.35, blue: 0.95)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        } else {
            Color(.systemGray5)
        }
    }
}

// MARK: - Bubble Shape (with tail)

struct BubbleShape: Shape {
    let isFromMe: Bool
    let showTail: Bool

    func path(in rect: CGRect) -> Path {
        let radius: CGFloat = 18
        let tailSize: CGFloat = showTail ? 6 : 0

        var path = Path()

        if isFromMe {
            // Rounded rect with optional tail on bottom-right
            path.addRoundedRect(in: CGRect(
                x: rect.minX,
                y: rect.minY,
                width: rect.width - tailSize,
                height: rect.height
            ), cornerSize: CGSize(width: radius, height: radius))

            if showTail {
                let tailX = rect.maxX - tailSize
                let tailY = rect.maxY - 8
                path.move(to: CGPoint(x: tailX, y: tailY))
                path.addQuadCurve(
                    to: CGPoint(x: rect.maxX, y: rect.maxY),
                    control: CGPoint(x: tailX + 4, y: tailY + 6)
                )
                path.addQuadCurve(
                    to: CGPoint(x: tailX, y: rect.maxY),
                    control: CGPoint(x: tailX + 2, y: rect.maxY)
                )
            }
        } else {
            // Rounded rect with optional tail on bottom-left
            path.addRoundedRect(in: CGRect(
                x: rect.minX + tailSize,
                y: rect.minY,
                width: rect.width - tailSize,
                height: rect.height
            ), cornerSize: CGSize(width: radius, height: radius))

            if showTail {
                let tailX = rect.minX + tailSize
                let tailY = rect.maxY - 8
                path.move(to: CGPoint(x: tailX, y: tailY))
                path.addQuadCurve(
                    to: CGPoint(x: rect.minX, y: rect.maxY),
                    control: CGPoint(x: tailX - 4, y: tailY + 6)
                )
                path.addQuadCurve(
                    to: CGPoint(x: tailX, y: rect.maxY),
                    control: CGPoint(x: tailX - 2, y: rect.maxY)
                )
            }
        }

        return path
    }
}

// MARK: - Safe Array Access

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
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
                        id: "1", senderId: "a", recipientId: "b",
                        content: "Hey! How are you?",
                        sentAt: Date().addingTimeInterval(-3600),
                        deliveredAt: Date().addingTimeInterval(-3500),
                        readAt: Date().addingTimeInterval(-3400),
                        isFromMe: false
                    ),
                    DirectMessage(
                        id: "2", senderId: "b", recipientId: "a",
                        content: "I'm good! Thanks for asking 😊",
                        sentAt: Date().addingTimeInterval(-3300),
                        deliveredAt: Date().addingTimeInterval(-3200),
                        readAt: nil,
                        isFromMe: true
                    ),
                    DirectMessage(
                        id: "3", senderId: "a", recipientId: "b",
                        content: "Want to grab coffee? There's a great place near the station",
                        sentAt: Date().addingTimeInterval(-120),
                        deliveredAt: nil, readAt: nil,
                        isFromMe: false
                    ),
                ],
                lastMessageAt: Date(),
                unreadCount: 0
            )
        )
    }
}
