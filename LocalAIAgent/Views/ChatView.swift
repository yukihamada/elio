import SwiftUI
import AVFoundation
import PhotosUI

struct ChatView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var themeManager: ThemeManager
    @StateObject private var networkMonitor = NetworkMonitor.shared
    @State private var inputText = ""
    @State private var isGenerating = false
    @State private var showingConversationList = false
    @State private var showingSettings = false
    @State private var streamingResponse = ""
    @State private var displayedResponse = ""  // Batched display for smoother UI
    @State private var updateTimer: Timer?
    @State private var generationTask: Task<Void, Never>?
    @State private var showingAttachmentOptions = false
    @State private var showingImagePicker = false
    @State private var showingCamera = false
    @FocusState private var isInputFocused: Bool

    var body: some View {
        ZStack {
            // Background
            Color.chatBackgroundDynamic
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                headerView

                if !appState.isModelLoaded {
                    modelNotLoadedView
                } else {
                    chatContent
                }

                inputBar
            }
        }
        .sheet(isPresented: $showingConversationList) {
            ConversationListView()
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
        .confirmationDialog(String(localized: "attachment.title"), isPresented: $showingAttachmentOptions) {
            Button(String(localized: "attachment.photo.library")) {
                showingImagePicker = true
            }
            Button(String(localized: "attachment.camera")) {
                showingCamera = true
            }
            Button(String(localized: "common.cancel"), role: .cancel) {}
        }
        .sheet(isPresented: $showingImagePicker) {
            ImagePicker(onImageSelected: { image in
                // TODO: Handle image attachment
            })
        }
        .fullScreenCover(isPresented: $showingCamera) {
            CameraPicker(onImageCaptured: { image in
                // TODO: Handle captured image
            })
        }
    }

    // MARK: - Computed Properties

    private var truncatedModelName: String {
        guard let modelName = appState.currentModelName else {
            return "elio"
        }
        // Truncate to max 15 characters
        if modelName.count > 15 {
            return String(modelName.prefix(12)) + "..."
        }
        return modelName
    }

    // MARK: - Header

    private var headerView: some View {
        HStack(spacing: 16) {
            // Menu button
            Button(action: { showingConversationList = true }) {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(.primary)
            }

            // Model name (truncated if too long)
            Button(action: { showingSettings = true }) {
                HStack(spacing: 4) {
                    Text(truncatedModelName)
                        .font(.system(size: 17, weight: .semibold))
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .foregroundStyle(.primary)

            // Offline badge - shows when not connected
            if !networkMonitor.isConnected {
                HStack(spacing: 4) {
                    Image(systemName: "airplane")
                        .font(.system(size: 11, weight: .semibold))
                    Text("Offline")
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.green)
                .clipShape(Capsule())
            }

            Spacer()

            // Action buttons
            HStack(spacing: 16) {
                Button(action: { appState.newConversation() }) {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(.primary)
                }

                Button(action: { showingSettings = true }) {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(.primary)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Model Not Loaded View

    private var modelNotLoadedView: some View {
        VStack(spacing: 24) {
            Spacer()

            VStack(spacing: 16) {
                Image(systemName: "cpu")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)

                Text(String(localized: "chat.model.not.loaded"))
                    .font(.system(size: 20, weight: .semibold))

                Text(String(localized: "chat.model.not.loaded.description"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Button(action: { showingSettings = true }) {
                Text(String(localized: "chat.go.to.settings"))
                    .font(.system(size: 16, weight: .semibold))
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(Color.primary.opacity(0.1))
                    .clipShape(Capsule())
            }

            Spacer()
        }
    }

    // MARK: - Chat Content

    private var chatContent: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    if appState.currentConversation?.messages.isEmpty ?? true {
                        welcomeView
                    } else {
                        ForEach(appState.currentConversation?.messages ?? []) { message in
                            ChatMessageRow(message: message)
                                .id(message.id)
                        }
                    }

                    if isGenerating {
                        if !displayedResponse.isEmpty {
                            StreamingMessageRow(text: displayedResponse)
                                .id("streaming")
                        } else {
                            TypingIndicatorRow()
                                .id("typing")
                        }
                    }
                }
                .padding(.vertical, 16)
            }
            .scrollDismissesKeyboard(.interactively)
            .scrollIndicators(.hidden)
            .onChange(of: appState.currentConversation?.messages.count) { _, _ in
                // Use immediate scroll without animation for new messages
                proxy.scrollTo(appState.currentConversation?.messages.last?.id, anchor: .bottom)
            }
            .onChange(of: displayedResponse) { _, _ in
                // Scroll every 30 characters or on newline for smooth streaming
                if displayedResponse.count % 30 == 0 || displayedResponse.hasSuffix("\n") {
                    proxy.scrollTo("streaming", anchor: .bottom)
                }
            }
        }
    }

    // MARK: - Welcome View

    private var welcomeView: some View {
        VStack(spacing: 32) {
            Spacer()
                .frame(height: 60)

            Text(String(localized: "chat.welcome"))
                .font(.system(size: 24, weight: .semibold))
                .multilineTextAlignment(.center)

            VStack(spacing: 12) {
                SuggestionChip(text: String(localized: "chat.suggestion.schedule"), icon: "calendar") {
                    inputText = String(localized: "chat.suggestion.schedule")
                    sendMessage()
                }

                SuggestionChip(text: String(localized: "chat.suggestion.reminder"), icon: "checklist") {
                    inputText = String(localized: "chat.suggestion.reminder")
                    sendMessage()
                }

                SuggestionChip(text: String(localized: "chat.suggestion.help"), icon: "questionmark.circle") {
                    inputText = String(localized: "chat.suggestion.help")
                    sendMessage()
                }
            }

            Spacer()
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        VStack(spacing: 0) {
            // Loading indicator when model is loading
            if appState.isLoading {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text(String(localized: "model.status.loading") + " \(Int(appState.loadingProgress * 100))%")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.bottom, 8)
            }

            HStack(alignment: .bottom, spacing: 12) {
                // Attachment button (only enabled for vision models)
                Button(action: { showingAttachmentOptions = true }) {
                    Image(systemName: appState.currentModelSupportsVision ? "plus" : "plus")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(appState.currentModelSupportsVision ? Color.primary : Color.secondary.opacity(0.5))
                        .frame(width: 36, height: 36)
                        .background(Color.chatInputBackgroundDynamic)
                        .clipShape(Circle())
                        .overlay(
                            // Show camera badge for vision models
                            Group {
                                if appState.currentModelSupportsVision {
                                    Image(systemName: "camera.fill")
                                        .font(.system(size: 8))
                                        .foregroundStyle(.white)
                                        .padding(3)
                                        .background(Color.blue)
                                        .clipShape(Circle())
                                        .offset(x: 10, y: -10)
                                }
                            }
                        )
                }
                .disabled(isGenerating || !appState.currentModelSupportsVision)

                // Text input - allow input even during generation
                HStack(alignment: .bottom, spacing: 8) {
                    TextField(String(localized: "chat.placeholder"), text: $inputText, axis: .vertical)
                        .textFieldStyle(.plain)
                        .lineLimit(1...6)
                        .focused($isInputFocused)
                        .submitLabel(.send)
                        .onSubmit {
                            if canSend { sendMessage() }
                        }
                        .disabled(!appState.isModelLoaded)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.chatInputBackgroundDynamic)
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(Color.chatBorderDynamic, lineWidth: 1)
                )

                // Send button - always visible
                Button(action: {
                    if isGenerating {
                        stopGeneration()
                    } else {
                        sendMessage()
                    }
                }) {
                    ZStack {
                        if isGenerating {
                            // Stop button when generating
                            Image(systemName: "stop.fill")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.white)
                        } else {
                            // Send arrow
                            Image(systemName: "arrow.up")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(.white)
                        }
                    }
                    .frame(width: 36, height: 36)
                    .background(
                        canSend ? Color.blue :
                        isGenerating ? Color.red :
                        Color.gray.opacity(0.4)
                    )
                    .clipShape(Circle())
                }
                .disabled(!canSend && !isGenerating)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }

    private var canSend: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !isGenerating &&
        appState.isModelLoaded
    }

    private func sendMessage() {
        let trimmedText = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return }

        inputText = ""
        isInputFocused = false
        isGenerating = true
        streamingResponse = ""
        displayedResponse = ""

        // Start UI update timer for batched updates (smoother scrolling)
        startUpdateTimer()

        generationTask = Task {
            _ = await appState.sendMessageWithStreaming(trimmedText) { token in
                guard !Task.isCancelled else { return }
                streamingResponse += token
            }
            // Final update
            stopUpdateTimer()
            displayedResponse = streamingResponse

            // Small delay then clear
            try? await Task.sleep(nanoseconds: 50_000_000)
            isGenerating = false
            streamingResponse = ""
            displayedResponse = ""
            generationTask = nil
        }
    }

    private func stopGeneration() {
        generationTask?.cancel()
        generationTask = nil
        stopUpdateTimer()

        // Keep what we have so far
        if !streamingResponse.isEmpty {
            displayedResponse = streamingResponse + String(localized: "chat.generation.stopped")
        }

        isGenerating = false
        streamingResponse = ""
    }

    private func startUpdateTimer() {
        updateTimer?.invalidate()
        // Update display every 33ms (~30fps) for smooth UI without overwhelming SwiftUI
        // Using shorter interval reduces perceived latency while maintaining smoothness
        updateTimer = Timer.scheduledTimer(withTimeInterval: 0.033, repeats: true) { _ in
            if displayedResponse != streamingResponse {
                // Use transaction to reduce animation overhead during rapid updates
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    displayedResponse = streamingResponse
                }
            }
        }
    }

    private func stopUpdateTimer() {
        updateTimer?.invalidate()
        updateTimer = nil
    }
}

// MARK: - Chat Message Row

struct ChatMessageRow: View {
    let message: Message
    @State private var isThinkingExpanded = false
    @State private var showCopiedFeedback = false
    @State private var feedbackGiven: FeedbackType? = nil
    @StateObject private var speechManager = SpeechManager.shared

    enum FeedbackType {
        case positive, negative
    }

    private var isUser: Bool {
        message.role == .user
    }

    private var isSpeaking: Bool {
        speechManager.isSpeaking && speechManager.currentMessageId == message.id
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if isUser {
                // User message - right aligned with bubble
                HStack {
                    Spacer(minLength: 60)
                    Text(message.content)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(Color.chatUserBubbleDynamic)
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            } else {
                // Assistant message - left aligned, no bubble
                VStack(alignment: .leading, spacing: 12) {
                    // Thinking section
                    if let thinking = message.thinkingContent, !thinking.isEmpty {
                        thinkingSection(thinking)
                    }

                    // Main content
                    Text(parseMarkdown(message.content))
                        .textSelection(.enabled)

                    // Action buttons
                    actionButtons
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
        }
    }

    private func thinkingSection(_ thinking: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: { withAnimation(.spring(response: 0.3)) { isThinkingExpanded.toggle() } }) {
                HStack(spacing: 6) {
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 14))
                        .foregroundStyle(.purple)

                    Text(String(localized: "onboarding.feature.thinking"))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.purple)

                    Image(systemName: isThinkingExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.purple.opacity(0.7))

                    Spacer()
                }
            }
            .buttonStyle(.plain)

            if isThinkingExpanded {
                Text(thinking)
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .padding(12)
                    .background(Color.purple.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private var actionButtons: some View {
        HStack(spacing: 16) {
            // Copy button
            Button(action: copyToClipboard) {
                HStack(spacing: 4) {
                    Image(systemName: showCopiedFeedback ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 16))
                    if showCopiedFeedback {
                        Text(String(localized: "common.copied"))
                            .font(.system(size: 12))
                    }
                }
                .foregroundStyle(showCopiedFeedback ? .green : Color.chatSecondaryText)
            }

            // Speech button
            Button(action: toggleSpeech) {
                Image(systemName: isSpeaking ? "stop.fill" : "speaker.wave.2")
                    .font(.system(size: 16))
                    .foregroundStyle(isSpeaking ? .blue : Color.chatSecondaryText)
            }

            // Thumbs up
            Button(action: { giveFeedback(.positive) }) {
                Image(systemName: feedbackGiven == .positive ? "hand.thumbsup.fill" : "hand.thumbsup")
                    .font(.system(size: 16))
                    .foregroundStyle(feedbackGiven == .positive ? .green : Color.chatSecondaryText)
            }

            // Thumbs down
            Button(action: { giveFeedback(.negative) }) {
                Image(systemName: feedbackGiven == .negative ? "hand.thumbsdown.fill" : "hand.thumbsdown")
                    .font(.system(size: 16))
                    .foregroundStyle(feedbackGiven == .negative ? .red : Color.chatSecondaryText)
            }

            // Share button
            Button(action: shareContent) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 16))
                    .foregroundStyle(Color.chatSecondaryText)
            }

            Spacer()
        }
        .padding(.top, 4)
    }

    private func copyToClipboard() {
        UIPasteboard.general.string = message.content
        withAnimation {
            showCopiedFeedback = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                showCopiedFeedback = false
            }
        }
    }

    private func toggleSpeech() {
        if isSpeaking {
            speechManager.stop()
        } else {
            speechManager.speak(message.content, messageId: message.id)
        }
    }

    private func giveFeedback(_ type: FeedbackType) {
        withAnimation(.spring(response: 0.3)) {
            if feedbackGiven == type {
                feedbackGiven = nil
            } else {
                feedbackGiven = type
            }
        }
        // Haptic feedback
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
    }

    private func shareContent() {
        let activityVC = UIActivityViewController(
            activityItems: [message.content],
            applicationActivities: nil
        )
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first,
           let rootVC = window.rootViewController {
            rootVC.present(activityVC, animated: true)
        }
    }

    private func parseMarkdown(_ text: String) -> AttributedString {
        do {
            return try AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))
        } catch {
            return AttributedString(text)
        }
    }
}

// MARK: - Streaming Message Row

struct StreamingMessageRow: View {
    let text: String
    @State private var isThinkingExpanded = true

    private var parsedContent: (thinking: String?, content: String, isThinking: Bool) {
        let raw = text

        if raw.contains("<think>") && !raw.contains("</think>") {
            if let startRange = raw.range(of: "<think>") {
                let thinkContent = String(raw[startRange.upperBound...])
                return (thinkContent, "", true)
            }
        }

        let parsed = Message.parseThinkingContent(raw)
        return (parsed.thinking, parsed.content, false)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Thinking in progress
            if parsedContent.isThinking {
                thinkingInProgress
            }

            // Completed thinking
            if let thinking = parsedContent.thinking, !thinking.isEmpty, !parsedContent.isThinking {
                completedThinking(thinking)
            }

            // Main content
            if !parsedContent.content.isEmpty {
                HStack(alignment: .bottom, spacing: 0) {
                    Text(parsedContent.content)
                        .textSelection(.enabled)

                    // Cursor
                    Rectangle()
                        .fill(Color.primary)
                        .frame(width: 2, height: 18)
                        .opacity(0.6)
                }
            } else if !parsedContent.isThinking {
                // Show cursor when waiting for content
                Rectangle()
                    .fill(Color.primary)
                    .frame(width: 2, height: 18)
                    .opacity(0.6)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var thinkingInProgress: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 14))
                    .foregroundStyle(.purple)
                    .symbolEffect(.pulse)

                Text(String(localized: "chat.thinking", defaultValue: "Thinking..."))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.purple)

                Spacer()
            }

            if let thinking = parsedContent.thinking, !thinking.isEmpty {
                Text(thinking)
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .lineLimit(5)
                    .padding(12)
                    .background(Color.purple.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private func completedThinking(_ thinking: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: { withAnimation(.spring(response: 0.3)) { isThinkingExpanded.toggle() } }) {
                HStack(spacing: 6) {
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 14))
                        .foregroundStyle(.purple)

                    Text(String(localized: "onboarding.feature.thinking"))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.purple)

                    Image(systemName: isThinkingExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.purple.opacity(0.7))

                    Spacer()
                }
            }
            .buttonStyle(.plain)

            if isThinkingExpanded {
                Text(thinking)
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .padding(12)
                    .background(Color.purple.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }
}

// MARK: - Typing Indicator Row

struct TypingIndicatorRow: View {
    @State private var animating = false

    var body: some View {
        HStack(spacing: 8) {
            // Animated dots
            HStack(spacing: 4) {
                ForEach(0..<3) { index in
                    Circle()
                        .fill(Color.blue)
                        .frame(width: 8, height: 8)
                        .scaleEffect(animating ? 1.0 : 0.5)
                        .animation(
                            .easeInOut(duration: 0.5)
                            .repeatForever()
                            .delay(Double(index) * 0.15),
                            value: animating
                        )
                }
            }

            Text(String(localized: "chat.generating", defaultValue: "Generating response..."))
                .font(.system(size: 14))
                .foregroundStyle(.secondary)

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .onAppear { animating = true }
    }
}

// MARK: - Suggestion Chip

struct SuggestionChip: View {
    let text: String
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)

                Text(text)
                    .font(.system(size: 15))

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(Color.chatInputBackgroundDynamic)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.chatBorderDynamic, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Conversation List View

struct ConversationListView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if appState.conversations.isEmpty {
                    emptyState
                } else {
                    conversationList
                }
            }
            .navigationTitle(String(localized: "conversations.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(String(localized: "common.done")) { dismiss() }
                        .fontWeight(.semibold)
                }
            }
            .background(Color.chatBackgroundDynamic)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 50))
                .foregroundStyle(.secondary)

            Text(String(localized: "conversations.empty"))
                .font(.headline)
                .foregroundStyle(.secondary)
        }
    }

    private var conversationList: some View {
        List {
            ForEach(appState.conversations) { conversation in
                Button(action: {
                    appState.currentConversation = conversation
                    dismiss()
                }) {
                    HStack(spacing: 12) {
                        Image(systemName: "bubble.left.fill")
                            .foregroundStyle(.secondary)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(conversation.title)
                                .font(.system(size: 16, weight: .medium))
                                .lineLimit(1)

                            Text(formatDate(conversation.updatedAt))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()
                    }
                    .padding(.vertical, 4)
                }
                .foregroundStyle(.primary)
            }
            .onDelete { indexSet in
                for index in indexSet {
                    let conversation = appState.conversations[index]
                    if appState.currentConversation?.id == conversation.id {
                        appState.currentConversation = nil
                    }
                }
                appState.conversations.remove(atOffsets: indexSet)
            }
        }
        .listStyle(.plain)
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Image Picker

struct ImagePicker: UIViewControllerRepresentable {
    let onImageSelected: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .images
        config.selectionLimit = 1
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: ImagePicker

        init(_ parent: ImagePicker) {
            self.parent = parent
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            parent.dismiss()

            guard let result = results.first else { return }

            result.itemProvider.loadObject(ofClass: UIImage.self) { object, error in
                if let image = object as? UIImage {
                    DispatchQueue.main.async {
                        self.parent.onImageSelected(image)
                    }
                }
            }
        }
    }
}

// MARK: - Camera Picker

struct CameraPicker: UIViewControllerRepresentable {
    let onImageCaptured: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker

        init(_ parent: CameraPicker) {
            self.parent = parent
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            parent.dismiss()

            if let image = info[.originalImage] as? UIImage {
                parent.onImageCaptured(image)
            }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

// MARK: - Speech Manager (Singleton for proper state management)

@MainActor
class SpeechManager: NSObject, ObservableObject {
    static let shared = SpeechManager()
    private var synthesizer: AVSpeechSynthesizer?
    @Published var isSpeaking = false
    @Published var currentMessageId: UUID?

    override init() {
        super.init()
        setupSynthesizer()
    }

    private func setupSynthesizer() {
        synthesizer = AVSpeechSynthesizer()
        synthesizer?.delegate = self
    }

    func speak(_ text: String, messageId: UUID) {
        if isSpeaking {
            stop()
            return
        }

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "ja-JP")
        utterance.rate = 0.5
        currentMessageId = messageId
        isSpeaking = true
        synthesizer?.speak(utterance)
    }

    func stop() {
        synthesizer?.stopSpeaking(at: .immediate)
        isSpeaking = false
        currentMessageId = nil
    }
}

extension SpeechManager: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.isSpeaking = false
            self.currentMessageId = nil
        }
    }
}

#Preview {
    ChatView()
        .environmentObject(AppState())
        .environmentObject(ThemeManager())
}
