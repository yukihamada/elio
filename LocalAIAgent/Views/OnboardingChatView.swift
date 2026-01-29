import SwiftUI

/// Interactive chat-style onboarding that explains ElioChat during model download
struct OnboardingChatView: View {
    @Binding var downloadProgress: Double
    @Binding var isDownloadComplete: Bool
    var downloadProgressInfo: DownloadProgressInfo?
    let onComplete: () -> Void

    @State private var messages: [OnboardingMessage] = []
    @State private var isTyping = false
    @State private var isChatFinished = false

    // Chat messages with auto-progression
    private let chatScript: [ChatScriptItem] = [
        // Introduction
        ChatScriptItem(
            sender: .elio,
            text: "こんにちは！ElioChatへようこそ 🎉",
            delay: 0.5
        ),
        ChatScriptItem(
            sender: .elio,
            text: "私はあなたのiPhoneで動くAIアシスタントです。",
            delay: 1.8
        ),
        ChatScriptItem(
            sender: .user,
            text: "どんなことができるの？",
            delay: 2.0,
            isAutoResponse: true
        ),

        // What ElioChat can do
        ChatScriptItem(
            sender: .elio,
            text: "✨ 日本語での会話・質問への回答\n✨ 文章作成・要約・翻訳\n✨ 画像の認識・分析\n✨ プログラミング支援",
            delay: 2.5
        ),
        ChatScriptItem(
            sender: .user,
            text: "オフラインでも使える？",
            delay: 2.0,
            isAutoResponse: true
        ),

        // Offline + Online capabilities
        ChatScriptItem(
            sender: .elio,
            text: "もちろん！✈️機内モードでも動作します。",
            delay: 1.5
        ),
        ChatScriptItem(
            sender: .elio,
            text: "ネット接続時は🔍Web検索で最新情報も調べられます。",
            delay: 2.0
        ),
        ChatScriptItem(
            sender: .user,
            text: "他のモデルも使えるの？",
            delay: 2.0,
            isAutoResponse: true
        ),

        // Models
        ChatScriptItem(
            sender: .elio,
            text: "はい！ElioChatには日本語に特化した独自のAIモデルがあります。",
            delay: 2.0
        ),
        ChatScriptItem(
            sender: .elio,
            text: "🧠 ElioChat独自モデル（日本語最適化）\n🖼️ 画像認識モデル\n🎤 音声認識モデル\n\n設定から好みのモデルに切り替えできます！",
            delay: 2.5
        ),

        // Privacy
        ChatScriptItem(
            sender: .user,
            text: "プライバシーは大丈夫？",
            delay: 2.0,
            isAutoResponse: true
        ),
        ChatScriptItem(
            sender: .elio,
            text: "🔒 すべての処理はiPhone内で完結\n🔒 会話データは外部送信なし\n\nあなただけのプライベートAIです！",
            delay: 2.0
        ),

        // Ready
        ChatScriptItem(
            sender: .elio,
            text: "準備完了！何でも聞いてくださいね 😊",
            delay: 1.5
        ),
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Progress bar at top (hide when download complete)
            if !isDownloadComplete {
                VStack(spacing: 8) {
                    HStack {
                        Text("モデルをダウンロード中...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        // Show progress info: percentage if available, otherwise bytes
                        if let info = downloadProgressInfo {
                            if info.progress > 0 {
                                Text("\(Int(info.progress * 100))%")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            } else if info.bytesDownloaded > 0 {
                                Text("\(formatBytes(info.bytesDownloaded))")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            } else {
                                ProgressView()
                                    .scaleEffect(0.7)
                            }
                        } else if downloadProgress > 0 {
                            Text("\(Int(downloadProgress * 100))%")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        } else {
                            ProgressView()
                                .scaleEffect(0.7)
                        }
                    }

                    // Show detailed progress info if available
                    if let info = downloadProgressInfo, info.speed > 0 {
                        HStack {
                            Text("\(formatBytes(info.bytesDownloaded)) / \(formatBytes(info.totalBytes))")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.tertiary)
                            Spacer()
                            Text(info.speedFormatted)
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.tertiary)
                        }
                    }

                    if downloadProgress > 0 || (downloadProgressInfo?.progress ?? 0) > 0 {
                        ProgressView(value: downloadProgressInfo?.progress ?? downloadProgress)
                            .progressViewStyle(.linear)
                            .tint(.purple)
                    } else {
                        // Indeterminate progress when no percentage available
                        ProgressView()
                            .progressViewStyle(.linear)
                            .tint(.purple)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 8)
            } else {
                // Download complete - show success message
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("ダウンロード完了")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.green)
                }
                .padding(.top, 16)
                .padding(.bottom, 8)
            }

            // Chat messages
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(messages) { message in
                            OnboardingMessageBubble(message: message)
                                .id(message.id)
                                .transition(.asymmetric(
                                    insertion: .opacity.combined(with: .move(edge: .bottom)),
                                    removal: .opacity
                                ))
                        }

                        if isTyping {
                            TypingIndicator()
                                .id("typing")
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                .onChange(of: messages.count) { _, _ in
                    withAnimation {
                        proxy.scrollTo(messages.last?.id ?? "typing", anchor: .bottom)
                    }
                }
                .onChange(of: isTyping) { _, _ in
                    withAnimation {
                        proxy.scrollTo("typing", anchor: .bottom)
                    }
                }
            }

            // Show loading indicator if chat finished but download still in progress
            if isChatFinished && !isDownloadComplete {
                HStack(spacing: 12) {
                    ProgressView()
                        .scaleEffect(0.9)
                    Text("ダウンロード完了を待っています...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.bottom, 20)
            }
        }
        .onAppear {
            startChat()
            // Check if already complete on appear
            if isDownloadComplete && isChatFinished {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    onComplete()
                }
            }
        }
        .onChange(of: isChatFinished) { _, finished in
            if finished && isDownloadComplete {
                // Both chat and download complete - auto start
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    onComplete()
                }
            }
        }
        .onChange(of: isDownloadComplete) { _, complete in
            if complete && isChatFinished {
                // Both chat and download complete - auto start
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    onComplete()
                }
            }
        }
    }

    private func startChat() {
        // Start displaying messages with delays
        Task {
            for item in chatScript {
                // Wait for delay
                try? await Task.sleep(nanoseconds: UInt64(item.delay * 1_000_000_000))

                // Show typing indicator before AI messages
                if item.sender == .elio {
                    await MainActor.run {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            isTyping = true
                        }
                    }

                    // Typing duration based on message length
                    let typingDuration = min(Double(item.text.count) * 0.02, 1.5)
                    try? await Task.sleep(nanoseconds: UInt64(typingDuration * 1_000_000_000))

                    await MainActor.run {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            isTyping = false
                        }
                    }
                }

                // Add message
                await MainActor.run {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        messages.append(OnboardingMessage(
                            id: UUID().uuidString,
                            sender: item.sender,
                            text: item.text
                        ))
                    }
                }
            }

            // Chat finished - mark as complete
            await MainActor.run {
                isChatFinished = true
            }
        }
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let mb = Double(bytes) / 1_000_000
        if mb >= 1000 {
            return String(format: "%.1f GB", mb / 1000)
        } else {
            return String(format: "%.0f MB", mb)
        }
    }
}

// MARK: - Supporting Types

struct OnboardingMessage: Identifiable {
    let id: String
    let sender: MessageSender
    let text: String

    enum MessageSender {
        case elio
        case user
    }
}

struct ChatScriptItem {
    let sender: OnboardingMessage.MessageSender
    let text: String
    let delay: Double
    var isAutoResponse: Bool = false
}

// MARK: - Message Bubble

struct OnboardingMessageBubble: View {
    let message: OnboardingMessage

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if message.sender == .elio {
                // ElioChat avatar
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [.purple.opacity(0.2), .blue.opacity(0.2)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 36, height: 36)

                    Image(systemName: "cpu.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.purple, .blue],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("ElioChat")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(message.text)
                        .font(.body)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }

                Spacer(minLength: 40)
            } else {
                Spacer(minLength: 40)

                Text(message.text)
                    .font(.body)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        LinearGradient(
                            colors: [.purple, .blue],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            }
        }
    }
}

// MARK: - Typing Indicator

struct TypingIndicator: View {
    @State private var animationOffset: CGFloat = 0

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            // ElioChat avatar
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.purple.opacity(0.2), .blue.opacity(0.2)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 36, height: 36)

                Image(systemName: "cpu.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.purple, .blue],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }

            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(Color.secondary)
                        .frame(width: 8, height: 8)
                        .offset(y: animationOffset(for: index))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16))

            Spacer()
        }
        .onAppear {
            withAnimation(
                .easeInOut(duration: 0.5)
                .repeatForever(autoreverses: true)
            ) {
                animationOffset = -5
            }
        }
    }

    private func animationOffset(for index: Int) -> CGFloat {
        return animationOffset * sin(Double(index) * .pi / 3)
    }
}

// MARK: - Preview

#Preview {
    OnboardingChatView(
        downloadProgress: .constant(0.45),
        isDownloadComplete: .constant(false),
        downloadProgressInfo: DownloadProgressInfo(
            progress: 0.45,
            bytesDownloaded: 500_000_000,
            totalBytes: 1_260_000_000,
            speed: 10_000_000,
            estimatedTimeRemaining: 76
        ),
        onComplete: {}
    )
}
