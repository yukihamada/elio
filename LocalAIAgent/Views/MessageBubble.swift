import SwiftUI

struct MessageBubble: View {
    let message: Message
    var onFeedback: ((Message.FeedbackRating) -> Void)?
    @State private var isExpanded = false
    @State private var isThinkingExpanded = false
    @State private var showCopied = false

    private var isUser: Bool {
        message.role == .user
    }

    private var isAssistant: Bool {
        message.role == .assistant
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if isUser {
                Spacer(minLength: 60)
            } else {
                avatarView
            }

            VStack(alignment: isUser ? .trailing : .leading, spacing: 8) {
                // Thinking content (collapsible)
                if let thinking = message.thinkingContent, !thinking.isEmpty {
                    thinkingView(thinking)
                }

                // Main message content
                messageContent

                // Tool calls
                if let toolCalls = message.toolCalls, !toolCalls.isEmpty {
                    toolCallsView(toolCalls)
                }

                // Tool results
                if let toolResults = message.toolResults, !toolResults.isEmpty {
                    toolResultsView(toolResults)
                }

                // Timestamp and feedback buttons
                HStack(spacing: 12) {
                    timestampView

                    if isAssistant && onFeedback != nil {
                        Spacer()
                        feedbackButtons
                    }
                }
            }

            if isUser {
                // User avatar (optional)
                userAvatarView
            } else {
                Spacer(minLength: 60)
            }
        }
    }

    private func thinkingView(_ thinking: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: { withAnimation(.spring(response: 0.3)) { isThinkingExpanded.toggle() } }) {
                HStack(spacing: 8) {
                    ZStack {
                        Circle()
                            .fill(Color.purple.opacity(0.15))
                            .frame(width: 28, height: 28)

                        Image(systemName: "brain.head.profile")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.purple)
                    }

                    Text(String(localized: "onboarding.feature.thinking"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.purple)

                    Spacer()

                    Image(systemName: isThinkingExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.purple.opacity(0.7))
                }
            }
            .buttonStyle(.plain)

            if isThinkingExpanded {
                Text(thinking)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.purple.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.purple.opacity(0.2), lineWidth: 1)
                )
        )
    }

    private var avatarView: some View {
        ZStack {
            Circle()
                .fill(.linearGradient(
                    colors: [.purple, .blue],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
                .frame(width: 36, height: 36)
                .shadow(color: .purple.opacity(0.3), radius: 4, y: 2)

            Image(systemName: "sparkles")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.white)
        }
    }

    private var userAvatarView: some View {
        ZStack {
            Circle()
                .fill(Color.accentColor)
                .frame(width: 36, height: 36)

            Image(systemName: "person.fill")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.white)
        }
    }

    private var messageContent: some View {
        VStack(alignment: isUser ? .trailing : .leading, spacing: 8) {
            // Display attached image if present
            if let image = message.image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 240, maxHeight: 240)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .shadow(color: Color.black.opacity(0.1), radius: 4, y: 2)
            }

            // Text content
            if !message.content.isEmpty && message.content != String(localized: "chat.image.sent") {
                ZStack(alignment: isUser ? .bottomLeading : .bottomTrailing) {
                    markdownContentView
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(bubbleBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                        .shadow(color: isUser ? Color.accentColor.opacity(0.2) : Color.black.opacity(0.05), radius: 4, y: 2)

                    // Copy feedback
                    if showCopied {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark")
                                .font(.system(size: 10, weight: .bold))
                            Text(String(localized: "common.copied"))
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.green)
                        .clipShape(Capsule())
                        .offset(y: 24)
                        .transition(.scale.combined(with: .opacity))
                    }
                }
                .contextMenu {
                    Button(action: copyMessage) {
                        Label(String(localized: "common.copy"), systemImage: "doc.on.doc")
                    }
                }
            } else if message.content == String(localized: "chat.image.sent") && message.image == nil {
                // Show placeholder if image data couldn't be loaded
                Text(message.content)
                    .textSelection(.enabled)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(bubbleBackground)
                    .foregroundStyle(isUser ? .white : .primary)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .shadow(color: isUser ? Color.accentColor.opacity(0.2) : Color.black.opacity(0.05), radius: 4, y: 2)
            }
        }
    }

    private func copyMessage() {
        UIPasteboard.general.string = message.content
        withAnimation(.spring(response: 0.3)) {
            showCopied = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation {
                showCopied = false
            }
        }
    }

    private var bubbleBackground: some View {
        Group {
            if isUser {
                LinearGradient(
                    colors: [Color.accentColor, Color.accentColor.opacity(0.9)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            } else {
                Color(.secondarySystemBackground)
            }
        }
    }

    private func toolCallsView(_ toolCalls: [ToolCall]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(toolCalls) { toolCall in
                ToolCallRow(toolCall: toolCall)
            }
        }
    }

    private func toolResultsView(_ toolResults: [ToolResult]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(toolResults, id: \.id) { result in
                ToolResultRow(result: result, isExpanded: $isExpanded)
            }
        }
    }

    private var timestampView: some View {
        Text(formatTime(message.timestamp))
            .font(.system(size: 11))
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 4)
    }

    private var feedbackButtons: some View {
        HStack(spacing: 8) {
            Button(action: { onFeedback?(.good) }) {
                Image(systemName: message.feedbackRating == .good ? "hand.thumbsup.fill" : "hand.thumbsup")
                    .font(.system(size: 14))
                    .foregroundStyle(message.feedbackRating == .good ? .green : .secondary)
            }
            .buttonStyle(.plain)

            Button(action: { onFeedback?(.bad) }) {
                Image(systemName: message.feedbackRating == .bad ? "hand.thumbsdown.fill" : "hand.thumbsdown")
                    .font(.system(size: 14))
                    .foregroundStyle(message.feedbackRating == .bad ? .red : .secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 4)
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    private var markdownContentView: some View {
        Text(message.content)
            .textSelection(.enabled)
            .foregroundStyle(isUser ? .white : .primary)
    }
}

// MARK: - Tool Call Row

struct ToolCallRow: View {
    let toolCall: ToolCall

    var body: some View {
        HStack(spacing: 8) {
            iconView
            labelView
            Spacer()
            ProgressView()
                .scaleEffect(0.7)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(backgroundView)
    }

    private var iconView: some View {
        ZStack {
            Circle()
                .fill(Color.orange.opacity(0.15))
                .frame(width: 28, height: 28)

            Image(systemName: "wrench.and.screwdriver.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.orange)
        }
    }

    private var labelView: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(String(localized: "message.tool.running"))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)

            Text(toolCall.name)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)
        }
    }

    private var backgroundView: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(Color.orange.opacity(0.08))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.orange.opacity(0.2), lineWidth: 1)
            )
    }
}

// MARK: - Tool Result Row

struct ToolResultRow: View {
    let result: ToolResult
    @Binding var isExpanded: Bool

    private var statusColor: Color {
        result.isError ? .red : .green
    }

    private var statusIcon: String {
        result.isError ? "xmark" : "checkmark"
    }

    private var statusText: String {
        result.isError ? String(localized: "message.tool.error") : String(localized: "message.tool.completed")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            headerRow
            contentText
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.tertiarySystemBackground))
        )
    }

    private var headerRow: some View {
        HStack(spacing: 8) {
            statusBadge
            statusLabel
            Spacer()
            expandButton
        }
    }

    private var statusBadge: some View {
        ZStack {
            Circle()
                .fill(statusColor.opacity(0.15))
                .frame(width: 28, height: 28)

            Image(systemName: statusIcon)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(statusColor)
        }
    }

    private var statusLabel: some View {
        Text(statusText)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(statusColor)
    }

    @ViewBuilder
    private var expandButton: some View {
        if result.content.count > 100 {
            Button(action: { isExpanded.toggle() }) {
                Text(isExpanded ? String(localized: "common.close") : String(localized: "common.details"))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.accentColor)
            }
        }
    }

    private var contentText: some View {
        Text(result.content)
            .font(.system(size: 13))
            .foregroundStyle(.secondary)
            .lineLimit(isExpanded ? nil : 4)
    }
}

// MARK: - Code Block View

struct CodeBlockView: View {
    let code: String
    let language: String?

    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerView
            codeContent
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(.separator).opacity(0.3), lineWidth: 1)
        )
    }

    private var headerView: some View {
        HStack {
            if let language = language {
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 8, height: 8)
                    Text(language)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button(action: copyCode) {
                HStack(spacing: 4) {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 12))
                    Text(copied ? String(localized: "common.copied") : String(localized: "common.copy"))
                        .font(.system(size: 12))
                }
                .foregroundStyle(copied ? .green : .secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(.tertiarySystemBackground))
    }

    private var codeContent: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Text(code)
                .font(.system(size: 13, design: .monospaced))
                .padding(12)
                .textSelection(.enabled)
        }
        .background(Color(.secondarySystemBackground))
    }

    private func copyCode() {
        UIPasteboard.general.string = code
        withAnimation(.spring(response: 0.3)) {
            copied = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                copied = false
            }
        }
    }
}

#Preview {
    ScrollView {
        VStack(spacing: 16) {
            MessageBubble(message: Message(role: .user, content: "こんにちは！今日の予定を教えて"))
            MessageBubble(message: Message(role: .assistant, content: "こんにちは！今日の予定を確認しますね。\n\n**本日のスケジュール:**\n- 10:00 ミーティング\n- 14:00 プレゼン準備"))
            MessageBubble(message: Message(
                role: .assistant,
                content: "予定を確認しています...",
                toolCalls: [ToolCall(name: "calendar.list_events", arguments: [:])]
            ))
        }
        .padding()
    }
}
