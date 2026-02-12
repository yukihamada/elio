import SwiftUI
import AVFoundation
import PhotosUI
import PDFKit
import UniformTypeIdentifiers
import Combine
import UIKit

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
    @State private var lastSentText: String = ""  // For restoring on cancel
    @State private var showingAttachmentOptions = false
    @State private var showingImagePicker = false
    @State private var showingCamera = false
    @State private var attachedImages: [UIImage] = []
    @State private var showingVisionModelAlert = false
    @State private var showingDownloadVisionModel = false
    @State private var isSwitchingToVisionModel = false
    @State private var showingModelSettings = false
    @StateObject private var speechManager = ReazonSpeechManager.shared
    @State private var showingSpeechDownload = false
    @State private var isVoiceRecording = false
    @State private var showingDocumentPicker = false
    @State private var attachedPDFText: String?
    @State private var attachedPDFName: String?
    @State private var attachedPDFImages: [UIImage] = []
    @State private var attachedPDFPageCount: Int = 0
    @State private var showingURLInput = false
    @State private var urlInputText = ""
    @State private var attachedWebContent: WebContent?
    @State private var isLoadingWebContent = false
    @State private var webContentError: String?
    @State private var showingTemplates = false
    @StateObject private var templateManager = PromptTemplateManager.shared
    @FocusState private var isInputFocused: Bool
    @State private var isViewReady = false  // Tracks when view is fully rendered
    @State private var hasTriggeredResponseHaptic = false  // Track haptic for AI response
    @AppStorage("justCompletedOnboarding") private var justCompletedOnboarding = false
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    // Web search
    @State private var showingSearchPrivacyAlert = false
    @State private var pendingSearchQuery: String = ""
    @AppStorage("hasShownSearchPrivacyInfo") private var hasShownSearchPrivacyInfo = false
    @AppStorage("webSearchEnabled") private var webSearchEnabled = true  // Default ON
    @State private var showingPlusMenu = false  // For + button menu
    // Thinking mode
    @AppStorage("thinkingEnabled") private var thinkingEnabled = true  // Default ON
    @StateObject private var settingsManager = ModelSettingsManager.shared
    // TTS Manager (separate from voice recognition speechManager)
    @StateObject private var ttsManager = SpeechManager.shared
    // Voice conversation mode (interactive voice chat like ChatGPT)
    @State private var isVoiceConversationMode = false
    @State private var voiceConversationState: VoiceConversationState = .idle
    // Expanded text input (fullscreen editor)
    @State private var showingExpandedInput = false
    // TTS download alert (local state to prevent view refresh dismissing alert)
    @State private var showingTTSDownloadAlert = false
    // Emergency mode
    @State private var isEmergencyLongPressing = false
    // ChatWeb.ai & Peer connection
    @State private var showingChatWebConnect = false
    @State private var showingPeerConnect = false

    // Calculate number of lines in input text
    private var inputLineCount: Int {
        let lines = inputText.components(separatedBy: "\n").count
        // Also estimate wrapped lines based on character count per line (~30 chars)
        let estimatedWrappedLines = inputText.count / 30
        return max(lines, estimatedWrappedLines)
    }

    var body: some View {
        ZStack {
            // Background
            Color.chatBackgroundDynamic
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                headerView

                // Emergency mode banner and quick actions
                if appState.isEmergencyMode {
                    EmergencyModeBanner()

                    EmergencyQuickActionsView { message in
                        inputText = message
                        // Auto-send the emergency message
                        sendMessage()
                    }
                }

                // Always show chat content for faster perceived startup
                // Model loading happens in background
                chatContent

                inputBar
            }

            // Processing overlay - prevents white screen during CPU-heavy operations
            if isGenerating && !isVoiceConversationMode {
                Color.black.opacity(0.02)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }

            // Voice conversation mode overlay
            if isVoiceConversationMode {
                VoiceConversationOverlay(
                    state: $voiceConversationState,
                    audioLevel: speechManager.audioLevel,
                    onClose: { exitVoiceConversationMode() }
                )
                .transition(.opacity)
            }
        }
        .sheet(isPresented: $showingConversationList) {
            ConversationListView()
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
        #if targetEnvironment(macCatalyst)
        .keyboardShortcut(.return, modifiers: .command) // Cmd+Enter: send
        .onAppear {
            // Cmd+N: new chat, Cmd+,: settings
        }
        .background {
            Button("") { appState.newConversation() }
                .keyboardShortcut("n", modifiers: .command)
                .hidden()
            Button("") { showingSettings = true }
                .keyboardShortcut(",", modifiers: .command)
                .hidden()
        }
        #endif
        .confirmationDialog(String(localized: "attachment.title"), isPresented: $showingAttachmentOptions) {
            Button(String(localized: "attachment.photo.library")) {
                handleImageAttachment()
            }
            #if !targetEnvironment(macCatalyst)
            Button(String(localized: "attachment.camera")) {
                handleCameraAttachment()
            }
            #endif
            Button(String(localized: "attachment.pdf")) {
                showingDocumentPicker = true
            }
            Button(String(localized: "attachment.url")) {
                showingURLInput = true
            }
            Button(String(localized: "common.cancel"), role: .cancel) {}
        }
        .alert(String(localized: "attachment.url.title"), isPresented: $showingURLInput) {
            TextField(String(localized: "attachment.url.placeholder"), text: $urlInputText)
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)
            Button(String(localized: "common.cancel"), role: .cancel) {
                urlInputText = ""
            }
            Button(String(localized: "attachment.url.fetch")) {
                fetchWebContent()
            }
        } message: {
            Text(String(localized: "attachment.url.message"))
        }
        .sheet(isPresented: $showingImagePicker) {
            ImagePicker(maxSelection: 5, onImagesSelected: { images in
                // Create thumbnails to reduce memory usage
                let thumbnails = images.map { createThumbnail($0) }
                attachedImages.append(contentsOf: thumbnails)
            })
        }
        #if !targetEnvironment(macCatalyst)
        .fullScreenCover(isPresented: $showingCamera) {
            CameraPicker(onImageCaptured: { image in
                // Create thumbnail to reduce memory usage
                attachedImages.append(createThumbnail(image))
            })
        }
        #endif
        .sheet(isPresented: $showingDocumentPicker) {
            DocumentPicker(onDocumentSelected: { content in
                attachedPDFName = content.url.lastPathComponent
                attachedPDFText = content.text
                attachedPDFImages = content.pageImages
                attachedPDFPageCount = content.pageCount
            })
        }
        .alert(String(localized: "vision.model.required.title"), isPresented: $showingVisionModelAlert) {
            if appState.hasDownloadedVisionModel {
                // Has a downloaded vision model - offer to switch
                Button(String(localized: "vision.model.switch")) {
                    switchToVisionModel()
                }
                Button(String(localized: "common.cancel"), role: .cancel) {}
            } else {
                // No downloaded vision model - offer to download
                Button(String(localized: "vision.model.download")) {
                    showingDownloadVisionModel = true
                }
                Button(String(localized: "common.cancel"), role: .cancel) {}
            }
        } message: {
            if appState.hasDownloadedVisionModel {
                if let visionModel = appState.downloadedVisionModels.first {
                    Text(String(localized: "vision.model.switch.message \(visionModel.name)"))
                }
            } else {
                if let recommended = appState.recommendedVisionModel {
                    Text(String(localized: "vision.model.download.message \(recommended.name) \(recommended.size)"))
                } else {
                    Text(String(localized: "vision.model.not.available"))
                }
            }
        }
        .sheet(isPresented: $showingDownloadVisionModel) {
            VisionModelDownloadView()
        }
        .sheet(isPresented: $showingModelSettings) {
            if let modelId = appState.currentModelId, let modelName = appState.currentModelName {
                ModelSettingsView(modelId: modelId, modelName: modelName)
            }
        }
        .alert(String(localized: "speech.download.title"), isPresented: $showingSpeechDownload) {
            Button(String(localized: "speech.download.action")) {
                downloadSpeechModel()
            }
            Button(String(localized: "common.cancel"), role: .cancel) {}
        } message: {
            Text(String(localized: "speech.download.message"))
        }
        // Kokoro TTS download prompt (using local state to prevent view refresh dismissal)
        .onChange(of: ttsManager.showTTSDownloadPrompt) { _, newValue in
            if newValue {
                showingTTSDownloadAlert = true
                ttsManager.showTTSDownloadPrompt = false // Reset ttsManager state, use local state for alert
            }
        }
        .alert(String(localized: "tts.download.title", defaultValue: "高品質音声合成"),
               isPresented: $showingTTSDownloadAlert) {
            Button(String(localized: "tts.download.action", defaultValue: "ダウンロード")) {
                Task {
                    await ttsManager.downloadKokoroTTS()
                }
            }
            Button(String(localized: "tts.download.use_system", defaultValue: "システム音声を使用")) {
                ttsManager.useKokoroTTS = false
                // Use system TTS immediately
                if ttsManager.currentMessageId != nil {
                    ttsManager.speakWithSystemTTSPublic(ttsManager.pendingText ?? "")
                }
            }
            Button(String(localized: "common.cancel"), role: .cancel) {
                ttsManager.currentMessageId = nil
            }
        } message: {
            Text(String(localized: "tts.download.message", defaultValue: "Kokoro TTSモデル（約87MB）をダウンロードすると、より自然な日本語音声で読み上げができます。"))
        }
        .alert("URL読み込みエラー", isPresented: Binding(
            get: { webContentError != nil },
            set: { if !$0 { webContentError = nil } }
        )) {
            Button("OK", role: .cancel) {
                webContentError = nil
            }
        } message: {
            if let error = webContentError {
                Text(error)
            }
        }
        .overlay {
            // Speech model download progress
            if speechManager.isDownloading {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                VStack(spacing: 12) {
                    ProgressView(value: speechManager.downloadProgress)
                        .progressViewStyle(.linear)
                        .frame(width: 200)
                    Text(String(localized: "speech.downloading"))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white)
                    Text("\(Int(speechManager.downloadProgress * 100))%")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.8))
                }
                .padding(24)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color(.systemBackground).opacity(0.95))
                )
            }
        }
        .overlay {
            // TTS model download progress
            if ttsManager.isDownloadingTTS {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                VStack(spacing: 12) {
                    ProgressView(value: ttsManager.ttsDownloadProgress)
                        .progressViewStyle(.linear)
                        .frame(width: 200)
                    Text(String(localized: "tts.downloading", defaultValue: "音声合成モデルをダウンロード中..."))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.primary)
                    Text("\(Int(ttsManager.ttsDownloadProgress * 100))%")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .padding(24)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color(.systemBackground).opacity(0.95))
                )
            }
        }
        .overlay {
            if isSwitchingToVisionModel {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                VStack(spacing: 12) {
                    ProgressView()
                        .scaleEffect(1.2)
                    Text(String(localized: "vision.model.switching"))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white)
                }
                .padding(24)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color(.systemBackground).opacity(0.95))
                )
            }
        }
        .sheet(isPresented: $showingTemplates) {
            PromptTemplatesView(onSelectTemplate: { template in
                inputText = template.content
                isInputFocused = true
            })
        }
        // ChatWeb.ai quick connect
        .sheet(isPresented: $showingChatWebConnect) {
            ChatWebConnectView(
                chatModeManager: ChatModeManager.shared,
                syncManager: nil
            )
        }
        // Peer device connection
        .sheet(isPresented: $showingPeerConnect) {
            PeerConnectionView(chatModeManager: ChatModeManager.shared)
        }
        // Expanded text input (fullscreen editor)
        .sheet(isPresented: $showingExpandedInput) {
            ExpandedInputView(text: $inputText, onSend: {
                showingExpandedInput = false
                if canSend {
                    sendMessage()
                }
            })
        }
        // Web search privacy explanation alert
        .alert(String(localized: "search.privacy.title", defaultValue: "プライバシー保護検索"), isPresented: $showingSearchPrivacyAlert) {
            Button(String(localized: "search.privacy.proceed", defaultValue: "検索する")) {
                executeWebSearch(query: pendingSearchQuery)
            }
            Button(String(localized: "common.cancel"), role: .cancel) {
                pendingSearchQuery = ""
            }
        } message: {
            Text(String(localized: "search.privacy.message", defaultValue: """
            ElioChat の Web 検索はプライバシーを保護します：

            🔒 DuckDuckGo 経由で検索
            🚫 追跡・トラッキングなし
            🔐 検索履歴は保存されません
            📱 デバイス外にデータを保存しません

            検索クエリのみがDuckDuckGoに送信され、結果はデバイス上で処理されます。
            """))
        }
        // Handle pending quick question from widget and restore draft
        .onAppear {
            // Screenshot mode: Load mock data
            if AppState.isScreenshotMode {
                appState.currentConversation = ScreenshotMockData.getMockConversation()
                appState.conversations = ScreenshotMockData.getMockConversations()
                appState.currentModelName = ScreenshotMockData.getMockModelName()
                return
            }

            // Check for pending message from crash (user message without response)
            checkForPendingMessage()

            // Restore draft input from crash recovery
            if inputText.isEmpty, let savedDraft = UserDefaults.standard.string(forKey: "chat_draft_input"), !savedDraft.isEmpty {
                inputText = savedDraft
            }

            // Handle widget quick question
            if let question = appState.pendingQuickQuestion {
                inputText = question
                appState.pendingQuickQuestion = nil
            }
        }
        // Use task modifier for keyboard focus - runs after view appears
        .task {
            // Wait for view layout to complete
            try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
            await MainActor.run {
                isViewReady = true
                // Don't auto-focus keyboard during onboarding
                // The onChange handler will focus after onboarding completes
                if !hasCompletedOnboarding {
                    return
                }
                // Clear the justCompletedOnboarding flag if it was set
                if justCompletedOnboarding {
                    justCompletedOnboarding = false
                    // Keyboard will be focused by onChange handler
                    return
                }
                // Normal app launch after onboarding - focus keyboard for quick input
                isInputFocused = true
            }
        }
        .onChange(of: appState.pendingQuickQuestion) { _, newValue in
            if let question = newValue {
                inputText = question
                appState.pendingQuickQuestion = nil
                isInputFocused = true
            }
        }
        // Focus keyboard when onboarding completes
        .onChange(of: hasCompletedOnboarding) { oldValue, newValue in
            if !oldValue && newValue {
                // Onboarding just completed - focus keyboard after a short delay
                // to allow the fullScreenCover to dismiss
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 300_000_000) // 300ms
                    isInputFocused = true
                }
            }
        }
        // Handle showConversationList from widget deep link
        .onChange(of: appState.showConversationList) { _, newValue in
            if newValue {
                showingConversationList = true
                appState.showConversationList = false
            }
        }
        // Save draft input for crash recovery
        .onChange(of: inputText) { _, newValue in
            if !newValue.isEmpty {
                UserDefaults.standard.set(newValue, forKey: "chat_draft_input")
            }
        }
        // Sync web search toggle with MCP servers
        .onChange(of: webSearchEnabled) { _, newValue in
            if newValue {
                appState.enabledMCPServers.insert("websearch")
            } else {
                appState.enabledMCPServers.remove("websearch")
            }
        }
        // Sync thinking toggle with model settings
        .onChange(of: thinkingEnabled) { _, newValue in
            if let modelId = appState.currentModelId {
                var settings = settingsManager.settings(for: modelId)
                settings.enableThinking = newValue  // Direct mapping: UI "on" = enable thinking
                settingsManager.updateSettings(for: modelId, settings: settings)
            }
        }
        .onAppear {
            // Sync web search toggle state with MCP servers on appear
            webSearchEnabled = appState.enabledMCPServers.contains("websearch")
            // Sync thinking toggle with model settings on appear
            if let modelId = appState.currentModelId {
                let settings = settingsManager.settings(for: modelId)
                thinkingEnabled = settings.enableThinking
            }
        }
        // Also sync when model is loaded (currentModelId changes from nil to a value)
        .onChange(of: appState.currentModelId) { _, newModelId in
            if let modelId = newModelId {
                // Get current settings for this model
                let settings = settingsManager.settings(for: modelId)
                // Sync UI toggle with model settings
                thinkingEnabled = settings.enableThinking
                // IMPORTANT: Ensure settings are saved if they don't exist yet
                // This fixes the first-launch issue where defaults aren't persisted
                if !settingsManager.hasCustomSettings(for: modelId) {
                    var newSettings = settings
                    newSettings.enableThinking = thinkingEnabled
                    settingsManager.updateSettings(for: modelId, settings: newSettings)
                }
            }
        }
        // Sync when app becomes active (in case settings changed elsewhere)
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            if let modelId = appState.currentModelId {
                let settings = settingsManager.settings(for: modelId)
                thinkingEnabled = settings.enableThinking
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .voiceConversationTapToSend)) { _ in
            stopVoiceConversationListeningAndSend()
        }
    }

    private func handleAttachmentTap() {
        // Always show attachment options - PDF works without vision model
        showingAttachmentOptions = true
    }

    private func handleImageAttachment() {
        if appState.currentModelSupportsVision {
            showingImagePicker = true
        } else if appState.hasDownloadedVisionModel {
            showingVisionModelAlert = true
        } else {
            showingVisionModelAlert = true
        }
    }

    private func handleCameraAttachment() {
        if appState.currentModelSupportsVision {
            showingCamera = true
        } else if appState.hasDownloadedVisionModel {
            showingVisionModelAlert = true
        } else {
            showingVisionModelAlert = true
        }
    }

    private func switchToVisionModel() {
        isSwitchingToVisionModel = true
        Task {
            let success = await appState.switchToVisionModel()
            isSwitchingToVisionModel = false
            if success {
                // After switching, show attachment options
                showingAttachmentOptions = true
            }
        }
    }

    private func handleMicrophoneTap() {
        if isVoiceRecording {
            // Stop recording and transcribe
            isVoiceRecording = false
            Task {
                do {
                    let text = try await speechManager.stopRecording()
                    if !text.isEmpty {
                        inputText = text
                    }
                } catch {
                    print("Transcription error: \(error)")
                }
            }
        } else {
            // Check if model is downloaded
            if speechManager.isModelDownloaded {
                // Start recording
                startVoiceRecording()
            } else {
                // Show download prompt
                showingSpeechDownload = true
            }
        }
    }

    private func startVoiceRecording() {
        Task {
            do {
                try await speechManager.startRecording()
                isVoiceRecording = true
            } catch {
                print("Recording error: \(error)")
            }
        }
    }

    private func downloadSpeechModel() {
        print("[ChatView] downloadSpeechModel called")
        Task {
            print("[ChatView] Task started, calling downloadModelIfNeeded")
            do {
                try await speechManager.downloadModelIfNeeded()
                print("[ChatView] Download completed successfully")
                // After download, start recording
                startVoiceRecording()
            } catch {
                print("[ChatView] Download error: \(error)")
            }
        }
    }

    // MARK: - Voice Conversation Mode

    private func enterVoiceConversationMode() {
        // Check if speech model is downloaded
        if !speechManager.isModelDownloaded {
            showingSpeechDownload = true
            return
        }

        withAnimation(.easeInOut(duration: 0.3)) {
            isVoiceConversationMode = true
            voiceConversationState = .listening
        }

        // Setup TTS callback for auto-listen after AI speaks
        ttsManager.onSpeechFinished = { [self] in
            if isVoiceConversationMode && voiceConversationState == .aiSpeaking {
                // AI finished speaking, start listening again
                Task {
                    try? await Task.sleep(nanoseconds: 300_000_000) // Brief pause
                    await MainActor.run {
                        if isVoiceConversationMode {
                            startVoiceConversationListening()
                        }
                    }
                }
            }
        }

        // Start listening
        startVoiceConversationListening()
    }

    private func exitVoiceConversationMode() {
        // Stop everything
        speechManager.cancelRecording()
        ttsManager.stop()
        ttsManager.onSpeechFinished = nil

        withAnimation(.easeInOut(duration: 0.3)) {
            isVoiceConversationMode = false
            voiceConversationState = .idle
            isVoiceRecording = false
        }
    }

    private func startVoiceConversationListening() {
        guard isVoiceConversationMode else { return }

        voiceConversationState = .listening
        Task {
            do {
                try await speechManager.startRecording()
                isVoiceRecording = true
            } catch {
                print("[VoiceConversation] Recording error: \(error)")
            }
        }
    }

    private func stopVoiceConversationListeningAndSend() {
        guard isVoiceConversationMode && isVoiceRecording else { return }

        voiceConversationState = .processing
        Task {
            do {
                isVoiceRecording = false
                let text = try await speechManager.stopRecording()
                if !text.isEmpty {
                    voiceConversationState = .aiThinking
                    // Send message and get response
                    await sendVoiceConversationMessage(text)
                } else {
                    // No speech detected, go back to listening
                    startVoiceConversationListening()
                }
            } catch {
                print("[VoiceConversation] Transcription error: \(error)")
                startVoiceConversationListening()
            }
        }
    }

    private func sendVoiceConversationMessage(_ text: String) async {
        guard isVoiceConversationMode else { return }

        // Create conversation if needed
        if appState.currentConversation == nil {
            appState.currentConversation = Conversation()
            appState.conversations.insert(appState.currentConversation!, at: 0)
        }

        // Add user message
        let userMessage = Message(role: .user, content: text)
        appState.currentConversation?.messages.append(userMessage)

        // Update title for first message
        if appState.currentConversation?.messages.count == 1 {
            appState.currentConversation?.title = String(text.prefix(30)) + (text.count > 30 ? "..." : "")
        }

        isGenerating = true
        var fullResponse = ""

        // Generate response
        _ = await appState.sendMessageWithStreamingNoUserMessage(text, imageData: nil) { token in
            guard !Task.isCancelled else { return }
            fullResponse += token
        }

        isGenerating = false

        // Speak the response
        if isVoiceConversationMode && !fullResponse.isEmpty {
            voiceConversationState = .aiSpeaking
            // Remove thinking tags for TTS
            let cleanResponse = Message.parseThinkingContent(fullResponse).content
            if !cleanResponse.isEmpty {
                ttsManager.speak(cleanResponse, messageId: UUID())
            } else {
                // No content to speak, go back to listening
                startVoiceConversationListening()
            }
        }
    }

    /// Get the previous user message for feedback context
    private func getPreviousUserMessage(messages: [Message], currentIndex: Int) -> String? {
        // Look backwards from current message to find the most recent user message
        guard currentIndex > 0 else { return nil }

        for i in stride(from: currentIndex - 1, through: 0, by: -1) {
            if messages[i].role == .user {
                return messages[i].content
            }
        }
        return nil
    }

    // MARK: - Computed Properties

    private var truncatedModelName: String {
        guard let modelName = appState.currentModelName else {
            return "ElioChat"
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
            .accessibilityIdentifier("menuButton")

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
            .accessibilityIdentifier("settingsButton")
            .foregroundStyle(.primary)

            // Quick settings button (for model parameters)
            if appState.isModelLoaded || AppState.isScreenshotMode {
                Button(action: { showingModelSettings = true }) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }

            // SOS Emergency Mode button (long press to toggle)
            Button(action: {}) {
                Image(systemName: appState.isEmergencyMode ? "sos.circle.fill" : "sos.circle")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(appState.isEmergencyMode ? .white : .red)
                    .frame(width: 32, height: 32)
                    .background(appState.isEmergencyMode ? Color.red : Color.clear)
                    .clipShape(Circle())
                    .scaleEffect(isEmergencyLongPressing ? 1.2 : 1.0)
                    .animation(.easeInOut(duration: 0.3), value: isEmergencyLongPressing)
            }
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 1.0)
                    .onChanged { _ in
                        isEmergencyLongPressing = true
                    }
                    .onEnded { _ in
                        isEmergencyLongPressing = false
                        appState.toggleEmergencyMode()
                        let generator = UINotificationFeedbackGenerator()
                        generator.notificationOccurred(appState.isEmergencyMode ? .warning : .success)
                    }
            )
            .accessibilityLabel(String(localized: "emergency.sos.button"))

            // Offline badge - shows when not connected
            if !networkMonitor.isConnected {
                Image(systemName: "wifi.slash")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(
                        LinearGradient(
                            colors: [.orange, .red],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .clipShape(Circle())
                    .shadow(color: .orange.opacity(0.4), radius: 4, y: 2)
            }

            Spacer()

            // Action buttons
            HStack(spacing: 16) {
                // ChatWeb.ai quick connect
                Button(action: { showingChatWebConnect = true }) {
                    Image(systemName: "cloud.fill")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.indigo)
                }

                // Peer device connect
                Button(action: { showingPeerConnect = true }) {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.secondary)
                }

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

    // MARK: - Skeleton Loading View

    private var skeletonView: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 16) {
                    // Skeleton welcome message
                    VStack(spacing: 12) {
                        SkeletonCircle(size: 60)
                        SkeletonRectangle(width: 120, height: 24)
                        SkeletonRectangle(width: 200, height: 16)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 60)
                    .padding(.bottom, 40)

                    // Skeleton suggestion chips
                    HStack(spacing: 12) {
                        SkeletonRectangle(width: 100, height: 36, cornerRadius: 18)
                        SkeletonRectangle(width: 80, height: 36, cornerRadius: 18)
                        SkeletonRectangle(width: 90, height: 36, cornerRadius: 18)
                    }
                    .padding(.horizontal, 16)
                }
            }
            .scrollDisabled(true)
        }
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
                    if (appState.currentConversation?.messages.isEmpty ?? true) && !isGenerating {
                        welcomeView
                    } else {
                        let messages = appState.currentConversation?.messages ?? []
                        ForEach(Array(messages.enumerated()), id: \.element.id) { index, message in
                            ChatMessageRow(
                                message: message,
                                previousUserMessage: getPreviousUserMessage(messages: messages, currentIndex: index),
                                conversationId: appState.currentConversation?.id.uuidString,
                                modelId: appState.currentModelId
                            )
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
            .scrollDismissesKeyboard(.immediately)
            .scrollIndicators(.hidden)
            .onChange(of: appState.currentConversation?.messages.count) { _, _ in
                // Scroll immediately to new message - no animation for instant feedback
                proxy.scrollTo(appState.currentConversation?.messages.last?.id, anchor: .bottom)
            }
            .onChange(of: isGenerating) { _, newValue in
                // Scroll to typing indicator immediately when generation starts
                if newValue {
                    proxy.scrollTo("typing", anchor: .bottom)
                }
            }
            .onChange(of: displayedResponse) { _, _ in
                // Scroll every 50 characters or on newline for smooth streaming
                if displayedResponse.count % 50 == 0 || displayedResponse.hasSuffix("\n") {
                    proxy.scrollTo("streaming", anchor: .bottom)
                }
            }
        }
    }

    // MARK: - Welcome View

    private var welcomeView: some View {
        VStack(spacing: 24) {
            Spacer()

            if appState.isLoading || !appState.isModelLoaded {
                // Loading state - animated and engaging
                ModelLoadingView(progress: appState.loadingProgress, isLoading: appState.isLoading)
            } else {
                // Ready state - welcoming and inviting
                ReadyWelcomeView()
            }

            Spacer()
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        VStack(spacing: 0) {
            // Attached images preview (multiple)
            if !attachedImages.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(attachedImages.enumerated()), id: \.offset) { index, image in
                            ZStack(alignment: .topTrailing) {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 70, height: 70)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))

                                Button(action: {
                                    attachedImages.remove(at: index)
                                }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 18))
                                        .foregroundStyle(.white)
                                        .background(Color.black.opacity(0.6))
                                        .clipShape(Circle())
                                }
                                .offset(x: 6, y: -6)
                            }
                        }

                        // Add more images button (if under limit)
                        if attachedImages.count < 5 {
                            Button(action: { showingImagePicker = true }) {
                                VStack(spacing: 4) {
                                    Image(systemName: "plus")
                                        .font(.system(size: 20, weight: .medium))
                                    Text("\(attachedImages.count)/5")
                                        .font(.system(size: 10))
                                }
                                .foregroundStyle(.secondary)
                                .frame(width: 70, height: 70)
                                .background(Color(.secondarySystemBackground))
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .padding(.bottom, 8)
            }

            // Attached PDF preview
            if let pdfName = attachedPDFName {
                HStack(spacing: 12) {
                    // Show first page thumbnail if available, otherwise icon
                    if let firstImage = attachedPDFImages.first {
                        Image(uiImage: firstImage)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 60, height: 60)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                            )
                    } else {
                        ZStack {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.red.opacity(0.1))
                                .frame(width: 60, height: 60)
                            Image(systemName: "doc.fill")
                                .font(.system(size: 28))
                                .foregroundStyle(.red)
                        }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(pdfName)
                            .font(.system(size: 14, weight: .medium))
                            .lineLimit(1)

                        // Show page count and character count
                        HStack(spacing: 8) {
                            if attachedPDFPageCount > 0 {
                                Text(String(format: NSLocalizedString("attachment.pdf.pages", comment: ""), attachedPDFPageCount))
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                            }
                            if let text = attachedPDFText, !text.isEmpty {
                                Text(String(format: NSLocalizedString("attachment.pdf.chars", comment: ""), text.count))
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                            }
                        }

                        // Vision mode indicator
                        if !attachedPDFImages.isEmpty {
                            if appState.currentModelSupportsVision {
                                Label(String(localized: "attachment.pdf.vision.enabled"), systemImage: "eye.fill")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.green)
                            } else {
                                Label(String(localized: "attachment.pdf.text.only"), systemImage: "doc.text")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.orange)
                            }
                        }
                    }

                    Spacer()

                    Button(action: {
                        attachedPDFName = nil
                        attachedPDFText = nil
                        attachedPDFImages = []
                        attachedPDFPageCount = 0
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.secondarySystemBackground))
                )
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }

            // Web content preview
            if let webContent = attachedWebContent {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.blue.opacity(0.1))
                            .frame(width: 60, height: 60)
                        Image(systemName: "globe")
                            .font(.system(size: 28))
                            .foregroundStyle(.blue)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(webContent.title)
                            .font(.system(size: 14, weight: .medium))
                            .lineLimit(1)

                        Text(webContent.url.host ?? "")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)

                        Text(String(format: NSLocalizedString("attachment.pdf.chars", comment: ""), webContent.text.count))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button(action: {
                        attachedWebContent = nil
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.secondarySystemBackground))
                )
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }

            // Loading web content indicator
            if isLoadingWebContent {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text(String(localized: "attachment.url.loading"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.bottom, 8)
            }

            // Web search and thinking toggle row
            HStack(spacing: 8) {
                // Thinking toggle (settings updated via onChange handler)
                Button(action: {
                    thinkingEnabled.toggle()
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: thinkingEnabled ? "brain.head.profile.fill" : "brain.head.profile")
                            .font(.system(size: 12))
                        Text(thinkingEnabled ? String(localized: "chat.thinking.on") : String(localized: "chat.thinking.off"))
                            .font(.caption)
                    }
                    .foregroundStyle(thinkingEnabled ? Color.purple : .secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        Capsule()
                            .fill(thinkingEnabled ? Color.purple.opacity(0.15) : Color.secondary.opacity(0.1))
                    )
                }

                // Web search toggle
                Button(action: {
                    if !hasShownSearchPrivacyInfo {
                        showingSearchPrivacyAlert = true
                    } else {
                        webSearchEnabled.toggle()
                    }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: webSearchEnabled && networkMonitor.isConnected ? "globe" : "globe.badge.chevron.backward")
                            .font(.system(size: 12))
                        Text(webSearchEnabled ? String(localized: "chat.websearch.on") : String(localized: "chat.websearch.off"))
                            .font(.caption)
                    }
                    .foregroundStyle(webSearchEnabled && networkMonitor.isConnected ? Color.blue : .secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        Capsule()
                            .fill(webSearchEnabled && networkMonitor.isConnected ? Color.blue.opacity(0.15) : Color.secondary.opacity(0.1))
                    )
                }
                .disabled(!networkMonitor.isConnected)

                if !networkMonitor.isConnected {
                    Text(String(localized: "chat.offline"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 4)

            HStack(alignment: .bottom, spacing: 12) {
                // Plus menu button - hidden during voice recording/transcribing
                if !isVoiceRecording && !speechManager.isTranscribing {
                    Menu {
                        // Camera/Photo
                        Button(action: handleAttachmentTap) {
                            Label(String(localized: "attachment.photo"), systemImage: "camera.fill")
                        }

                        // Templates
                        Button(action: { showingTemplates = true }) {
                            Label(String(localized: "chat.templates"), systemImage: "text.badge.star")
                        }

                        // Document
                        Button(action: { showingDocumentPicker = true }) {
                            Label(String(localized: "attachment.document"), systemImage: "doc.fill")
                        }

                        // URL
                        Button(action: { showingURLInput = true }) {
                            Label(String(localized: "attachment.url"), systemImage: "link")
                        }
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(Color.primary)
                            .frame(width: 36, height: 36)
                            .background(Color.chatInputBackgroundDynamic)
                            .clipShape(Circle())
                            .overlay(
                                // Show camera badge - blue if vision ready, gray otherwise
                                Image(systemName: "camera.fill")
                                    .font(.system(size: 8))
                                    .foregroundStyle(.white)
                                    .padding(3)
                                    .background(appState.currentModelSupportsVision ? Color.blue : Color.gray)
                                    .clipShape(Circle())
                                    .offset(x: 10, y: -10)
                            )
                    }
                    .disabled(isGenerating)
                }

                if isVoiceRecording {
                    // ChatGPT-style voice recording UI - unified pill with no gaps
                    HStack(spacing: 0) {
                        // Stop button (left) - stops and transcribes
                        Button(action: {
                            // Stop recording and start transcription
                            Task {
                                isVoiceRecording = false
                                do {
                                    let text = try await speechManager.stopRecording()
                                    if !text.isEmpty {
                                        inputText = text
                                    }
                                } catch {
                                    print("Transcription error: \(error)")
                                }
                            }
                        }) {
                            Image(systemName: "stop.fill")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.primary)
                                .frame(width: 44, height: 44)
                        }

                        // Waveform visualization (center) - fills available space
                        VoiceWaveformView(audioLevel: speechManager.audioLevel)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)

                        // Send button (right) - stops recording and sends immediately
                        Button(action: {
                            // Stop recording, transcribe, and send
                            Task {
                                isVoiceRecording = false
                                do {
                                    let text = try await speechManager.stopRecording()
                                    if !text.isEmpty {
                                        inputText = text
                                        // Small delay to let UI update, then send
                                        try? await Task.sleep(nanoseconds: 100_000_000)
                                        sendMessage()
                                    }
                                } catch {
                                    print("Transcription error: \(error)")
                                }
                            }
                        }) {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(.white)
                                .frame(width: 36, height: 36)
                                .background(Color.blue)
                                .clipShape(Circle())
                        }
                        .padding(.trailing, 4)
                    }
                    .background(Color(.systemGray5))
                    .clipShape(RoundedRectangle(cornerRadius: 22))
                } else if speechManager.isTranscribing {
                    // Show transcribing placeholder
                    HStack {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text(String(localized: "chat.transcribing"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color.chatInputBackgroundDynamic)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                } else {
                    // Normal text input with microphone
                    ZStack(alignment: .topTrailing) {
                        HStack(alignment: .bottom, spacing: 8) {
                            TextField(String(localized: "chat.placeholder"), text: $inputText, axis: .vertical)
                                .textFieldStyle(.plain)
                                .lineLimit(1...6)
                                .autocorrectionDisabled()
                                .focused($isInputFocused)
                                .submitLabel(.send)
                                .onSubmit {
                                    if canSend { sendMessage() }
                                }
                                .disabled(!appState.isModelLoaded && !AppState.isScreenshotMode)
                                .padding(.trailing, inputLineCount >= 3 ? 24 : 0) // Make room for expand button

                            // Microphone button for voice input
                            Button(action: handleMicrophoneTap) {
                                Image(systemName: "mic.fill")
                                    .font(.system(size: 18))
                                    .foregroundStyle(.secondary)
                            }
                            .disabled(isGenerating || speechManager.isTranscribing)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color.chatInputBackgroundDynamic)
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(Color.chatBorderDynamic, lineWidth: 1)
                        )

                        // Expand button (top-right corner) - only show when 3+ lines
                        if inputLineCount >= 3 {
                            Button(action: {
                                showingExpandedInput = true
                            }) {
                                Image(systemName: "arrow.up.left.and.arrow.down.right")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(.secondary)
                                    .padding(6)
                            }
                            .padding(.top, 6)
                            .padding(.trailing, 44) // Position before mic button
                        }
                    }

                    // Send button or Interactive button
                    if inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && attachedImages.isEmpty && attachedPDFText == nil && attachedWebContent == nil && !isGenerating {
                        // Interactive voice mode button (when no text)
                        Button(action: {
                            // Turn off thinking for interactive mode (onChange handles settings update)
                            if thinkingEnabled {
                                thinkingEnabled = false
                            }
                            // Enter voice conversation mode
                            enterVoiceConversationMode()
                        }) {
                            Image(systemName: "waveform.circle.fill")
                                .font(.system(size: 28))
                                .foregroundColor(.blue)
                                .symbolRenderingMode(.hierarchical)
                        }
                        .frame(width: 36, height: 36)
                        .disabled(!appState.isModelLoaded && !AppState.isScreenshotMode)
                    } else {
                        // Send button (when has text or attachments)
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
                }  // end of non-recording else
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .animation(nil, value: isInputFocused)
        .alert(String(localized: "chat.websearch.privacy.title"), isPresented: $showingSearchPrivacyAlert) {
            Button(String(localized: "chat.websearch.privacy.enable")) {
                hasShownSearchPrivacyInfo = true
                webSearchEnabled = true
            }
            Button(String(localized: "chat.websearch.privacy.disable")) {
                hasShownSearchPrivacyInfo = true
                webSearchEnabled = false
            }
        } message: {
            Text(String(localized: "chat.websearch.privacy.message"))
        }
    }

    private var canSend: Bool {
        (!inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachedImages.isEmpty || attachedPDFText != nil || attachedWebContent != nil) &&
        !isGenerating &&
        (appState.isModelLoaded || AppState.isScreenshotMode)
    }

    private func sendMessage() {
        let trimmedText = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasImages = !attachedImages.isEmpty
        let hasPDF = attachedPDFText != nil
        let hasWeb = attachedWebContent != nil
        guard !trimmedText.isEmpty || hasImages || hasPDF || hasWeb else { return }

        // Capture values BEFORE clearing
        let savedImages = attachedImages
        let savedPDFText = attachedPDFText
        let savedPDFName = attachedPDFName
        let savedPDFImages = attachedPDFImages
        let savedWebContent = attachedWebContent

        // Save text for potential cancel/restore
        lastSentText = trimmedText

        // Set isGenerating IMMEDIATELY so cancel button activates right away
        isGenerating = true
        streamingResponse = ""
        displayedResponse = ""
        hasTriggeredResponseHaptic = false  // Reset for new response

        // IMMEDIATELY clear UI and hide keyboard - before any processing
        inputText = ""
        UserDefaults.standard.removeObject(forKey: "chat_draft_input")  // Clear saved draft
        attachedImages = []
        attachedPDFText = nil
        attachedPDFName = nil
        attachedPDFImages = []
        attachedPDFPageCount = 0
        attachedWebContent = nil
        isInputFocused = false

        // Force keyboard dismissal and input clearing
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)

        // Add user message IMMEDIATELY (before async processing) for instant UI feedback
        let displayContent = trimmedText.isEmpty
            ? (savedWebContent != nil ? String(localized: "chat.web.analyzing") :
               savedPDFName != nil ? String(format: NSLocalizedString("chat.pdf.sent", comment: ""), savedPDFName!) :
               String(localized: "chat.image.sent"))
            : trimmedText

        if appState.currentConversation == nil {
            appState.currentConversation = Conversation()
            appState.conversations.insert(appState.currentConversation!, at: 0)
        }
        let userMessage = Message(role: .user, content: displayContent, imageData: savedImages.first?.jpegData(compressionQuality: 0.6))
        appState.currentConversation?.messages.append(userMessage)

        // Save pending message for crash recovery
        savePendingMessage(trimmedText)

        // Update title for first message
        if appState.currentConversation?.messages.count == 1 {
            let titleText = trimmedText.isEmpty ? (savedWebContent?.title ?? savedPDFName ?? "Untitled") : trimmedText
            appState.currentConversation?.title = String(titleText.prefix(30)) + (titleText.count > 30 ? "..." : "")
        }

        // Start generation after a short delay to allow keyboard animation to complete
        // This ensures smooth UI transition before heavy inference starts
        Task {
            try? await Task.sleep(nanoseconds: 150_000_000) // 150ms for keyboard animation
            await MainActor.run {
                startGeneration(
                    trimmedText: trimmedText,
                    savedImages: savedImages,
                    savedPDFText: savedPDFText,
                    savedPDFName: savedPDFName,
                    savedPDFImages: savedPDFImages,
                    savedWebContent: savedWebContent
                )
            }
        }
    }

    private func savePendingMessage(_ text: String) {
        UserDefaults.standard.set(text, forKey: "pending_message")
        UserDefaults.standard.set(appState.currentConversation?.id.uuidString, forKey: "pending_conversation_id")
    }

    private func clearPendingMessage() {
        UserDefaults.standard.removeObject(forKey: "pending_message")
        UserDefaults.standard.removeObject(forKey: "pending_conversation_id")
    }

    private func checkForPendingMessage() {
        guard let pendingText = UserDefaults.standard.string(forKey: "pending_message"),
              !pendingText.isEmpty else { return }

        // Check if the last message in conversation has no response
        if let conversation = appState.currentConversation,
           let lastMessage = conversation.messages.last,
           lastMessage.role == .user {
            // Last message was user's and no response - offer to retry
            inputText = pendingText
        }
        clearPendingMessage()
    }

    private func startGeneration(
        trimmedText: String,
        savedImages: [UIImage],
        savedPDFText: String?,
        savedPDFName: String?,
        savedPDFImages: [UIImage],
        savedWebContent: WebContent?
    ) {
        // isGenerating is already set in sendMessage() for immediate cancel button activation
        // Start timer for streaming updates
        startUpdateTimer()

        // All heavy processing in background Task
        generationTask = Task {
            // JPEG conversion (heavy) - now in background for full quality
            var imageData: Data? = savedImages.first?.jpegData(compressionQuality: 0.8)
            let pdfImageData: Data? = appState.currentModelSupportsVision && !savedPDFImages.isEmpty
                ? savedPDFImages.first?.jpegData(compressionQuality: 0.8)
                : nil

            // Use saved values
            let pdfText = savedPDFText
            let pdfName = savedPDFName
            let webContent = savedWebContent

            // Build message content
            var fullContent: String

            if let pdfName = pdfName {
                let hasVisionAnalysis = pdfImageData != nil
                if hasVisionAnalysis {
                    if let pdfText = pdfText, !pdfText.isEmpty {
                        let pdfContext = String(format: NSLocalizedString("chat.pdf.context.vision", comment: ""), pdfName, pdfText)
                        fullContent = trimmedText.isEmpty ? pdfContext : "\(pdfContext)\n\n\(trimmedText)"
                    } else {
                        fullContent = trimmedText.isEmpty
                            ? String(format: NSLocalizedString("chat.pdf.analyze", comment: ""), pdfName)
                            : trimmedText
                    }
                    imageData = pdfImageData
                } else if let pdfText = pdfText {
                    let pdfContext = String(format: NSLocalizedString("chat.pdf.context", comment: ""), pdfName, pdfText)
                    fullContent = trimmedText.isEmpty ? pdfContext : "\(pdfContext)\n\n\(trimmedText)"
                } else {
                    fullContent = trimmedText
                }
            } else if let webContent = webContent {
                let webContext = String(format: NSLocalizedString("chat.url.context", comment: ""), webContent.title, webContent.url.absoluteString, webContent.text)
                fullContent = trimmedText.isEmpty ? webContext : "\(webContext)\n\n\(trimmedText)"
            } else {
                fullContent = trimmedText
            }

            // Generate response (user message already added before Task)
            _ = await appState.sendMessageWithStreamingNoUserMessage(fullContent, imageData: imageData) { token in
                guard !Task.isCancelled else { return }

                // Haptic feedback when AI starts responding (first token)
                if !hasTriggeredResponseHaptic {
                    hasTriggeredResponseHaptic = true
                    Task { @MainActor in
                        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                        impactFeedback.impactOccurred()
                    }
                }

                streamingResponse += token
            }

            // Final update
            stopUpdateTimer()
            displayedResponse = streamingResponse

            // Clear pending message on successful generation
            clearPendingMessage()

            // Small delay then clear
            try? await Task.sleep(nanoseconds: 50_000_000)
            isGenerating = false
            streamingResponse = ""
            displayedResponse = ""
            generationTask = nil

            // 会話完了を記録（レビュー促進用）
            ReviewManager.shared.recordConversationCompleted()
        }
    }

    private func stopGeneration() {
        // Cancel immediately for instant UI response
        generationTask?.cancel()
        generationTask = nil
        stopUpdateTimer()

        // Set flag to stop LLM generation in AppState
        appState.shouldStopGeneration = true

        // Check if we have any generated content to keep
        let hasGeneratedContent = !streamingResponse.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        if hasGeneratedContent {
            // Keep the partial response - save it as an assistant message
            let partialResponse = streamingResponse.trimmingCharacters(in: .whitespacesAndNewlines)

            // Parse and clean the response (remove thinking tags, tool call artifacts)
            let parsed = Message.parseThinkingContent(partialResponse)
            let cleanContent = parsed.content.isEmpty ? partialResponse : parsed.content

            // Only save if there's actual content (not just thinking or tool calls)
            if !cleanContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let assistantMessage = Message(
                    role: .assistant,
                    content: cleanContent,
                    thinkingContent: parsed.thinking
                )
                appState.currentConversation?.messages.append(assistantMessage)
            }

            // Clear generation state but keep the conversation
            isGenerating = false
            streamingResponse = ""
            displayedResponse = ""
            lastSentText = ""
        } else {
            // No content generated - restore previous state
            // Remove the user message that was just added
            if let lastMessage = appState.currentConversation?.messages.last,
               lastMessage.role == .user {
                appState.currentConversation?.messages.removeLast()
            }

            // Restore text to input field so user can edit and resend
            inputText = lastSentText
            isInputFocused = true

            // Clear all generation state
            isGenerating = false
            streamingResponse = ""
            displayedResponse = ""
            lastSentText = ""
        }

        // Reset stop flag after a short delay
        Task {
            try? await Task.sleep(nanoseconds: 100_000_000)
            appState.shouldStopGeneration = false
        }
    }

    private func startUpdateTimer() {
        updateTimer?.invalidate()
        // Update display every 150ms (~6fps) for efficient streaming
        // This reduces CPU usage while maintaining readable text flow
        updateTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { _ in
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

    /// Creates a thumbnail of the image to reduce memory usage
    /// Max width is 800px which is sufficient for display while saving memory
    private func createThumbnail(_ image: UIImage, maxWidth: CGFloat = 800) -> UIImage {
        let originalSize = image.size
        guard originalSize.width > maxWidth else { return image }

        let scale = maxWidth / originalSize.width
        let newSize = CGSize(width: maxWidth, height: originalSize.height * scale)

        return UIGraphicsImageRenderer(size: newSize).image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }

    private func fetchWebContent() {
        guard !urlInputText.isEmpty else { return }

        var urlString = urlInputText.trimmingCharacters(in: .whitespacesAndNewlines)
        // Add https:// if no scheme
        if !urlString.hasPrefix("http://") && !urlString.hasPrefix("https://") {
            urlString = "https://" + urlString
        }

        isLoadingWebContent = true
        urlInputText = ""

        Task {
            do {
                let content = try await WebContentExtractor.shared.extractContent(from: urlString)
                await MainActor.run {
                    attachedWebContent = content
                    isLoadingWebContent = false
                }
            } catch {
                await MainActor.run {
                    isLoadingWebContent = false
                    webContentError = error.localizedDescription
                }
            }
        }
    }

    // MARK: - Web Search

    /// Execute web search and send as new message
    private func executeWebSearch(query: String) {
        hasShownSearchPrivacyInfo = true
        pendingSearchQuery = ""

        // Send a search request message
        let searchMessage = "「\(query)」を検索して"
        inputText = searchMessage
        sendMessage()
    }
}

// MARK: - Chat Message Row

struct ChatMessageRow: View {
    let message: Message
    var previousUserMessage: String? = nil
    var conversationId: String? = nil
    var modelId: String? = nil

    @State private var isThinkingExpanded = true  // Default expanded so thinking doesn't "disappear"
    @State private var showCopiedFeedback = false
    @State private var feedbackGiven: FeedbackType? = nil
    @State private var showingFeedbackConsent = false
    @State private var pendingFeedbackType: FeedbackType? = nil
    @StateObject private var speechManager = SpeechManager.shared
    @StateObject private var feedbackService = FeedbackService.shared

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
                        .textSelection(.enabled)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(Color.chatUserBubbleDynamic)
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                        .contextMenu {
                            Button(action: {
                                UIPasteboard.general.string = message.content
                            }) {
                                Label("コピー", systemImage: "doc.on.doc")
                            }
                        }
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
                        .contextMenu {
                            Button(action: {
                                UIPasteboard.general.string = message.content
                            }) {
                                Label("コピー", systemImage: "doc.on.doc")
                            }
                            Button(action: {
                                shareContent()
                            }) {
                                Label("共有", systemImage: "square.and.arrow.up")
                            }
                        }

                    // Action buttons
                    actionButtons
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
        }
        .sheet(isPresented: $showingFeedbackConsent) {
            if let feedbackType = pendingFeedbackType {
                FeedbackConsentView(
                    feedbackType: feedbackType,
                    aiResponse: message.content,
                    userMessage: previousUserMessage,
                    conversationId: conversationId,
                    modelId: modelId,
                    onSubmit: { rememberChoice, comment in
                        if rememberChoice {
                            feedbackService.hasConsented = true
                            feedbackService.askEveryTime = false
                        }
                        submitFeedback(type: feedbackType, comment: comment)
                    },
                    onCancel: {
                        pendingFeedbackType = nil
                    }
                )
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
                ScrollView {
                    Text(thinking)
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 200)  // Limit height to prevent overflow
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
        print("[ChatMessageRow] toggleSpeech called, isSpeaking: \(isSpeaking)")
        if isSpeaking {
            speechManager.stop()
        } else {
            print("[ChatMessageRow] Calling speechManager.speak with text length: \(message.content.count)")
            speechManager.speak(message.content, messageId: message.id)
        }
    }

    private func giveFeedback(_ type: FeedbackType) {
        print("[ChatMessageRow] giveFeedback called with type: \(type)")

        // If already selected, toggle off
        if feedbackGiven == type {
            withAnimation(.spring(response: 0.3)) {
                feedbackGiven = nil
            }
            // Haptic feedback
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()
            print("[ChatMessageRow] Toggled off feedback")
            return
        }

        // Haptic feedback
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()

        print("[ChatMessageRow] hasConsented: \(feedbackService.hasConsented), askEveryTime: \(feedbackService.askEveryTime)")

        // Check if we need to show consent dialog
        if feedbackService.hasConsented && !feedbackService.askEveryTime {
            // User has already consented, submit directly
            print("[ChatMessageRow] Submitting feedback directly")
            submitFeedback(type: type, comment: nil)
        } else {
            // Show consent dialog
            print("[ChatMessageRow] Showing consent dialog")
            pendingFeedbackType = type
            showingFeedbackConsent = true
        }
    }

    private func submitFeedback(type: FeedbackType, comment: String?) {
        withAnimation(.spring(response: 0.3)) {
            feedbackGiven = type
        }

        // Trigger review prompt on positive feedback
        if type == .positive {
            Task { @MainActor in
                ReviewManager.shared.recordPositiveRating()
            }
        }

        // Submit to server
        Task {
            await feedbackService.submitFeedback(
                type: type,
                aiResponse: message.content,
                userMessage: previousUserMessage,
                conversationId: conversationId,
                modelId: modelId,
                comment: comment
            )
        }
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
            // Use full markdown interpretation for headers, lists, code blocks, etc.
            var options = AttributedString.MarkdownParsingOptions()
            options.interpretedSyntax = .full
            let result = try AttributedString(markdown: text, options: options)

            // Ensure line breaks are preserved (AttributedString sometimes strips them)
            // This is a workaround for SwiftUI's markdown handling
            return result
        } catch {
            // Fallback: preserve whitespace with inline-only parsing
            do {
                var options = AttributedString.MarkdownParsingOptions()
                options.interpretedSyntax = .inlineOnlyPreservingWhitespace
                return try AttributedString(markdown: text, options: options)
            } catch {
                return AttributedString(text)
            }
        }
    }
}

// MARK: - Streaming Message Row

struct StreamingMessageRow: View {
    let text: String
    @State private var isThinkingExpanded = true

    private var parsedContent: (thinking: String?, content: String, isThinking: Bool) {
        let raw = text

        // Case 1: <think> is in the text (model generated it)
        if raw.contains("<think>") && !raw.contains("</think>") {
            if let startRange = raw.range(of: "<think>") {
                let thinkContent = String(raw[startRange.upperBound...])
                return (thinkContent, "", true)
            }
        }

        // Case 2: <think> was in prompt, so text starts with thinking content
        // If no </think> yet, everything is thinking content (in progress)
        if !raw.contains("</think>") && !raw.contains("<think>") {
            // Check if this looks like thinking content (not tool call or regular response)
            // Thinking is in progress if we haven't seen </think> yet
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty && !trimmed.hasPrefix("<tool_call>") {
                return (raw, "", true)
            }
        }

        // Case 3: Thinking completed (</think> found) or no thinking
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
                    Text(parseStreamingMarkdown(parsedContent.content))
                        .textSelection(.enabled)

                    // Cursor
                    Rectangle()
                        .fill(Color.primary)
                        .frame(width: 2, height: 18)
                        .opacity(0.6)

                    Spacer()
                }
            } else if !parsedContent.isThinking {
                // Show cursor when waiting for content
                HStack {
                    Rectangle()
                        .fill(Color.primary)
                        .frame(width: 2, height: 18)
                        .opacity(0.6)
                    Spacer()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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

                Text(String(localized: "chat.thinking"))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.purple)

                Spacer()
            }

            // Show abbreviated thinking content during streaming (max 100 chars)
            if let thinking = parsedContent.thinking, !thinking.isEmpty {
                let displayText = thinking.count > 100
                    ? String(thinking.prefix(100)) + "..."
                    : thinking
                Text(displayText)
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Color.purple.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
                ScrollView {
                    Text(thinking)
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 200)  // Limit height to prevent overflow
                .padding(12)
                .background(Color.purple.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private func parseStreamingMarkdown(_ text: String) -> AttributedString {
        // Use lightweight markdown parsing during streaming
        // .inlineOnlyPreservingWhitespace is faster than .full but preserves linebreaks
        do {
            var options = AttributedString.MarkdownParsingOptions()
            options.interpretedSyntax = .inlineOnlyPreservingWhitespace
            return try AttributedString(markdown: text, options: options)
        } catch {
            return AttributedString(text)
        }
    }
}

// MARK: - Typing Indicator Row

struct TypingIndicatorRow: View {
    @State private var isBreathing = false

    var body: some View {
        HStack {
            // Single breathing dot (ChatGPT style)
            Circle()
                .fill(Color(.systemGray4))
                .frame(width: 20, height: 20)
                .scaleEffect(isBreathing ? 1.15 : 0.85)
                .opacity(isBreathing ? 1.0 : 0.6)
                .animation(
                    .easeInOut(duration: 1.0)
                    .repeatForever(autoreverses: true),
                    value: isBreathing
                )

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .onAppear {
            isBreathing = true
        }
    }
}

// MARK: - Voice Conversation State

enum VoiceConversationState {
    case idle
    case listening
    case processing
    case aiThinking
    case aiSpeaking

    var statusText: String {
        switch self {
        case .idle: return ""
        case .listening: return String(localized: "voice.listening")
        case .processing: return String(localized: "voice.processing")
        case .aiThinking: return String(localized: "voice.thinking")
        case .aiSpeaking: return String(localized: "voice.speaking")
        }
    }
}

// MARK: - Voice Conversation Overlay

struct VoiceConversationOverlay: View {
    @Binding var state: VoiceConversationState
    var audioLevel: Float
    var onClose: () -> Void

    @State private var pulseScale: CGFloat = 1.0
    @State private var innerPulseScale: CGFloat = 1.0

    var body: some View {
        ZStack {
            // Dark background
            Color.black.opacity(0.95)
                .ignoresSafeArea()

            VStack(spacing: 40) {
                Spacer()

                // Status text
                Text(state.statusText)
                    .font(.title2)
                    .fontWeight(.medium)
                    .foregroundColor(.white.opacity(0.8))

                // Animated circle indicator
                ZStack {
                    // Outer pulse ring
                    Circle()
                        .stroke(pulseColor.opacity(0.3), lineWidth: 2)
                        .frame(width: 200, height: 200)
                        .scaleEffect(pulseScale)

                    // Inner pulse ring
                    Circle()
                        .stroke(pulseColor.opacity(0.5), lineWidth: 3)
                        .frame(width: 150, height: 150)
                        .scaleEffect(innerPulseScale)

                    // Main circle - responds to audio level when listening
                    Circle()
                        .fill(
                            RadialGradient(
                                gradient: Gradient(colors: [pulseColor, pulseColor.opacity(0.6)]),
                                center: .center,
                                startRadius: 0,
                                endRadius: 60
                            )
                        )
                        .frame(width: circleSize, height: circleSize)
                        .shadow(color: pulseColor.opacity(0.5), radius: 20)

                    // Icon in center
                    Image(systemName: stateIcon)
                        .font(.system(size: 40, weight: .medium))
                        .foregroundColor(.white)
                }
                .frame(width: 220, height: 220)

                Spacer()

                // Tap instruction
                if state == .listening {
                    Text(String(localized: "voice.tap.to.send"))
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.6))
                }

                // Close button
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(.white)
                        .frame(width: 60, height: 60)
                        .background(Color.white.opacity(0.15))
                        .clipShape(Circle())
                }
                .padding(.bottom, 40)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if state == .listening {
                // Stop listening and send
                NotificationCenter.default.post(name: .voiceConversationTapToSend, object: nil)
            }
        }
        .onAppear {
            startPulseAnimation()
        }
        .onChange(of: state) { _, _ in
            startPulseAnimation()
        }
    }

    private var pulseColor: Color {
        switch state {
        case .idle: return .gray
        case .listening: return .blue
        case .processing: return .orange
        case .aiThinking: return .purple
        case .aiSpeaking: return .green
        }
    }

    private var stateIcon: String {
        switch state {
        case .idle: return "mic.slash"
        case .listening: return "waveform"
        case .processing: return "ellipsis"
        case .aiThinking: return "brain.head.profile"
        case .aiSpeaking: return "speaker.wave.2"
        }
    }

    private var circleSize: CGFloat {
        if state == .listening {
            // Respond to audio level
            return 100 + CGFloat(audioLevel) * 40
        }
        return 100
    }

    private func startPulseAnimation() {
        withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
            pulseScale = state == .listening ? 1.3 : 1.1
        }
        withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
            innerPulseScale = state == .listening ? 1.2 : 1.05
        }
    }
}

// Notification for tap-to-send in voice conversation
extension Notification.Name {
    static let voiceConversationTapToSend = Notification.Name("voiceConversationTapToSend")
}

// MARK: - Voice Waveform View

struct VoiceWaveformView: View {
    var audioLevel: Float = 0
    @State private var levels: [CGFloat] = Array(repeating: 0.2, count: 30)

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<levels.count, id: \.self) { index in
                Capsule()
                    .fill(Color(.systemGray3))
                    .frame(width: 3, height: max(4, levels[index] * 30))
                    .animation(
                        .easeOut(duration: 0.08),
                        value: levels[index]
                    )
            }
        }
        .onChange(of: audioLevel) { _, newLevel in
            // Shift levels to the left (flow from right)
            withAnimation(.easeOut(duration: 0.08)) {
                levels.removeFirst()
                // Add new level based on audio with some randomness for natural look
                let baseLevel = CGFloat(newLevel)
                let variation = CGFloat.random(in: -0.1...0.1)
                let newLevelValue = max(0.15, min(1.0, baseLevel + variation))
                levels.append(newLevelValue)
            }
        }
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
    @State private var showingExportOptions = false
    @State private var conversationToExport: Conversation?
    @State private var isExporting = false
    @State private var showingShareSheet = false
    @State private var exportedFileURL: URL?
    @State private var searchText = ""

    /// 検索でフィルタされた会話リスト
    private var filteredConversations: [Conversation] {
        if searchText.isEmpty {
            return appState.conversations
        }
        let query = searchText.lowercased()
        return appState.conversations.filter { conversation in
            // タイトルで検索
            if conversation.title.lowercased().contains(query) {
                return true
            }
            // メッセージ内容で検索
            return conversation.messages.contains { message in
                message.content.lowercased().contains(query)
            }
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if appState.conversations.isEmpty {
                    emptyState
                } else if filteredConversations.isEmpty && !searchText.isEmpty {
                    noSearchResultsView
                } else {
                    conversationList
                }
            }
            .navigationTitle(String(localized: "conversations.title"))
            #if !targetEnvironment(macCatalyst)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .searchable(text: $searchText, prompt: String(localized: "conversations.search.placeholder"))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(String(localized: "common.done")) { dismiss() }
                        .fontWeight(.semibold)
                }
            }
            .background(Color.chatBackgroundDynamic)
        }
    }

    private var noSearchResultsView: some View {
        VStack(spacing: 16) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 50))
                .foregroundStyle(.secondary)

            Text(String(localized: "conversations.search.no_results"))
                .font(.headline)
                .foregroundStyle(.secondary)
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
            ForEach(filteredConversations) { conversation in
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
                .swipeActions(edge: .leading, allowsFullSwipe: false) {
                    Button {
                        conversationToExport = conversation
                        showingExportOptions = true
                    } label: {
                        Label(String(localized: "common.share"), systemImage: "square.and.arrow.up")
                    }
                    .tint(.blue)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        if appState.currentConversation?.id == conversation.id {
                            appState.currentConversation = nil
                        }
                        appState.conversations.removeAll { $0.id == conversation.id }
                    } label: {
                        Label(String(localized: "common.delete"), systemImage: "trash")
                    }
                }
            }
        }
        .listStyle(.plain)
        .confirmationDialog(String(localized: "export.title"), isPresented: $showingExportOptions) {
            Button(String(localized: "export.format.markdown")) {
                exportConversation(format: .markdown)
            }
            Button(String(localized: "export.format.pdf")) {
                exportConversation(format: .pdf)
            }
            Button(String(localized: "export.format.text")) {
                exportConversation(format: .plainText)
            }
            Button(String(localized: "common.cancel"), role: .cancel) {}
        }
        .sheet(isPresented: $showingShareSheet) {
            if let url = exportedFileURL {
                ShareSheet(items: [url])
            }
        }
    }

    private func exportConversation(format: ConversationExporter.ExportFormat) {
        guard let conversation = conversationToExport else { return }

        isExporting = true
        Task {
            do {
                let result = try await ConversationExporter.shared.export(conversation, format: format)
                await MainActor.run {
                    exportedFileURL = result.url
                    showingShareSheet = true
                    isExporting = false
                }
            } catch {
                await MainActor.run {
                    isExporting = false
                    print("Export error: \(error)")
                }
            }
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Image Picker (Multiple Selection)

struct ImagePicker: UIViewControllerRepresentable {
    let maxSelection: Int
    let onImagesSelected: ([UIImage]) -> Void
    @Environment(\.dismiss) private var dismiss

    init(maxSelection: Int = 5, onImagesSelected: @escaping ([UIImage]) -> Void) {
        self.maxSelection = maxSelection
        self.onImagesSelected = onImagesSelected
    }

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .images
        config.selectionLimit = maxSelection
        config.selection = .ordered  // Preserve selection order
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

            guard !results.isEmpty else { return }

            var loadedImages: [UIImage] = []
            let dispatchGroup = DispatchGroup()

            for result in results {
                dispatchGroup.enter()
                result.itemProvider.loadObject(ofClass: UIImage.self) { object, error in
                    if let image = object as? UIImage {
                        loadedImages.append(image)
                    }
                    dispatchGroup.leave()
                }
            }

            dispatchGroup.notify(queue: .main) {
                self.parent.onImagesSelected(loadedImages)
            }
        }
    }
}

// MARK: - Camera Picker

#if !targetEnvironment(macCatalyst)
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
#endif

// MARK: - Speech Manager (Singleton with Kokoro TTS support)

@MainActor
class SpeechManager: NSObject, ObservableObject {
    static let shared = SpeechManager()

    // Legacy AVSpeechSynthesizer (fallback)
    private var synthesizer: AVSpeechSynthesizer?

    // Published state
    @Published var isSpeaking = false
    @Published var currentMessageId: UUID?
    @Published var showTTSDownloadPrompt = false
    @Published var isDownloadingTTS = false
    @Published var ttsDownloadProgress: Double = 0

    // Use Kokoro TTS when available (default ON - use high quality voice when downloaded)
    @Published var useKokoroTTS = true

    // Pending text for deferred playback after download prompt
    var pendingText: String?

    // Callback when speech finishes (for voice conversation mode)
    var onSpeechFinished: (() -> Void)?

    private var kokoroTTS: KokoroTTSManager { KokoroTTSManager.shared }

    override init() {
        super.init()
        setupSynthesizer()
    }

    private func setupSynthesizer() {
        synthesizer = AVSpeechSynthesizer()
        synthesizer?.delegate = self
    }

    /// Check if Kokoro TTS model is downloaded
    var isKokoroReady: Bool {
        kokoroTTS.isModelDownloaded
    }

    /// Speak text - uses Kokoro TTS if available, falls back to system TTS
    func speak(_ text: String, messageId: UUID) {
        print("[SpeechManager] speak() called, useKokoroTTS: \(useKokoroTTS), isKokoroReady: \(isKokoroReady)")

        if isSpeaking {
            print("[SpeechManager] Already speaking, stopping first then playing new speech")
            stop()
            // Continue to play new speech instead of returning
        }

        currentMessageId = messageId
        pendingText = text

        // Check if Kokoro TTS is ready
        if useKokoroTTS && isKokoroReady {
            // Use Kokoro TTS
            print("[SpeechManager] Using Kokoro TTS")
            isSpeaking = true
            Task {
                await kokoroTTS.speak(text, messageId: messageId)
                // Kokoro handles its own state, but sync our state
                await MainActor.run {
                    self.isSpeaking = kokoroTTS.isSpeaking
                    if !kokoroTTS.isSpeaking {
                        self.currentMessageId = nil
                        self.onSpeechFinished?()
                    }
                }
            }
        } else if useKokoroTTS && !isKokoroReady {
            // Prompt to download Kokoro TTS
            print("[SpeechManager] Prompting to download Kokoro TTS")
            showTTSDownloadPrompt = true
        } else {
            // Use system TTS (immediate, no download required)
            print("[SpeechManager] Using system TTS")
            speakWithSystemTTS(text)
        }
    }

    /// Speak using system AVSpeechSynthesizer (private)
    private func speakWithSystemTTS(_ text: String) {
        print("[SpeechManager] speakWithSystemTTS called with text length: \(text.count)")

        guard !text.isEmpty else {
            print("[SpeechManager] Empty text, skipping")
            return
        }

        // Configure audio session for playback
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback, mode: .default, options: [.duckOthers])
            try audioSession.setActive(true)
            print("[SpeechManager] Audio session configured for speech")
        } catch {
            print("[SpeechManager] Failed to configure audio session: \(error)")
        }

        let utterance = AVSpeechUtterance(string: text)

        // Select voice based on device language, with fallback
        let preferredLang = Bundle.main.preferredLocalizations.first ?? "en"
        let langCode: String
        switch preferredLang {
        case "ja":
            langCode = "ja-JP"
        case "zh-Hans", "zh-Hant", "zh":
            langCode = "zh-CN"
        default:
            langCode = "en-US"
        }

        // Try preferred language first, fallback to default if not available
        if let voice = AVSpeechSynthesisVoice(language: langCode) {
            utterance.voice = voice
            print("[SpeechManager] Using voice: \(langCode)")
        } else if let defaultVoice = AVSpeechSynthesisVoice(language: "en-US") {
            utterance.voice = defaultVoice
            print("[SpeechManager] Fallback to en-US voice")
        }

        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        isSpeaking = true

        if let synth = synthesizer {
            synth.speak(utterance)
            print("[SpeechManager] Started speaking with system TTS")
        } else {
            print("[SpeechManager] ERROR: synthesizer is nil, reinitializing...")
            setupSynthesizer()
            if let synth = synthesizer {
                synth.speak(utterance)
                print("[SpeechManager] Started speaking after reinitialization")
            } else {
                print("[SpeechManager] ERROR: Failed to reinitialize synthesizer")
                isSpeaking = false
            }
        }
    }

    /// Public method to speak with system TTS (called from alert action)
    func speakWithSystemTTSPublic(_ text: String) {
        speakWithSystemTTS(text)
    }

    /// Download Kokoro TTS model
    func downloadKokoroTTS() async {
        isDownloadingTTS = true
        showTTSDownloadPrompt = false

        print("[SpeechManager] Starting Kokoro TTS download...")

        do {
            // Observe download progress
            let observation = kokoroTTS.$downloadProgress.sink { [weak self] progress in
                Task { @MainActor in
                    self?.ttsDownloadProgress = progress
                    print("[SpeechManager] TTS download progress: \(Int(progress * 100))%")
                }
            }

            try await kokoroTTS.downloadModelIfNeeded()

            observation.cancel()
            isDownloadingTTS = false
            ttsDownloadProgress = 1.0

            print("[SpeechManager] Kokoro TTS download completed successfully")

            // Play the pending text after successful download
            if let text = pendingText, let messageId = currentMessageId {
                print("[SpeechManager] Playing pending text after download")
                isSpeaking = true
                await kokoroTTS.speak(text, messageId: messageId)
                await MainActor.run {
                    self.isSpeaking = kokoroTTS.isSpeaking
                    if !kokoroTTS.isSpeaking {
                        self.currentMessageId = nil
                        self.pendingText = nil
                        self.onSpeechFinished?()
                    }
                }
            }
        } catch {
            isDownloadingTTS = false
            print("[SpeechManager] TTS download failed: \(error)")
            // Fallback to system TTS on download failure
            if let text = pendingText {
                print("[SpeechManager] Falling back to system TTS")
                speakWithSystemTTS(text)
            }
        }
    }

    func stop() {
        // Stop Kokoro TTS
        kokoroTTS.stop()

        // Stop system TTS
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
            self.onSpeechFinished?()
        }
    }
}

// MARK: - Skeleton Components

struct SkeletonRectangle: View {
    let width: CGFloat
    let height: CGFloat
    var cornerRadius: CGFloat = 8

    @State private var isAnimating = false

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(Color.gray.opacity(0.15))
            .frame(width: width, height: height)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.clear,
                                Color.white.opacity(0.3),
                                Color.clear
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .offset(x: isAnimating ? width : -width)
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .onAppear {
                withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                    isAnimating = true
                }
            }
    }
}

struct SkeletonCircle: View {
    let size: CGFloat

    @State private var isAnimating = false

    var body: some View {
        Circle()
            .fill(Color.gray.opacity(0.15))
            .frame(width: size, height: size)
            .overlay(
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.clear,
                                Color.white.opacity(0.3),
                                Color.clear
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .offset(x: isAnimating ? size : -size)
            )
            .clipShape(Circle())
            .onAppear {
                withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                    isAnimating = true
                }
            }
    }
}

// MARK: - Share Sheet

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Model Loading View

struct ModelLoadingView: View {
    let progress: Double
    let isLoading: Bool
    @State private var pulseAnimation = false
    @State private var displayProgress: Double = 0
    @State private var progressTimer: Timer?

    private var loadingPhase: String {
        if displayProgress < 0.2 {
            return String(localized: "loading.phase.initializing")
        } else if displayProgress < 0.5 {
            return String(localized: "loading.phase.loading")
        } else if displayProgress < 0.85 {
            return String(localized: "loading.phase.preparing")
        } else {
            return String(localized: "loading.phase.almost")
        }
    }

    var body: some View {
        VStack(spacing: 28) {
            // Animated icon
            ZStack {
                // Outer ring
                Circle()
                    .stroke(
                        LinearGradient(
                            colors: [.blue.opacity(0.3), .purple.opacity(0.3)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 3
                    )
                    .frame(width: 80, height: 80)

                // Progress ring - smooth animated
                Circle()
                    .trim(from: 0, to: displayProgress)
                    .stroke(
                        LinearGradient(
                            colors: [.blue, .purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        style: StrokeStyle(lineWidth: 3, lineCap: .round)
                    )
                    .frame(width: 80, height: 80)
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 0.3), value: displayProgress)

                // CPU icon with pulse
                Image(systemName: "cpu.fill")
                    .font(.system(size: 32, weight: .medium))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.blue, .purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .scaleEffect(pulseAnimation ? 1.05 : 0.95)
            }

            VStack(spacing: 8) {
                Text("ElioChat")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.primary, .primary.opacity(0.8)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )

                Text(loadingPhase)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            // Progress indicator
            VStack(spacing: 6) {
                // Custom progress bar
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        // Background
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.gray.opacity(0.2))

                        // Progress - smooth animated
                        RoundedRectangle(cornerRadius: 4)
                            .fill(
                                LinearGradient(
                                    colors: [.blue, .purple],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: max(0, geometry.size.width * displayProgress))
                            .animation(.easeOut(duration: 0.3), value: displayProgress)
                    }
                }
                .frame(width: 160, height: 6)

                Text("\(Int(displayProgress * 100))%")
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                pulseAnimation = true
            }
            startProgressAnimation()
        }
        .onDisappear {
            progressTimer?.invalidate()
        }
        .onChange(of: progress) { _, newValue in
            // When actual progress jumps to 100%, animate to completion
            if newValue >= 1.0 {
                withAnimation(.easeOut(duration: 0.5)) {
                    displayProgress = 1.0
                }
            }
        }
    }

    private func startProgressAnimation() {
        // Animate progress slowly from 0 to ~90% over time
        // This gives visual feedback even when actual progress doesn't update
        displayProgress = 0.05
        var elapsed: Double = 0

        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { timer in
            elapsed += 0.1

            // Slow logarithmic progress - approaches 90% but never reaches it
            // Fast at first, then slows down
            let targetProgress = min(0.9, 0.05 + (0.85 * (1 - exp(-elapsed / 8))))

            if progress >= 1.0 {
                // Actual loading complete
                displayProgress = 1.0
                timer.invalidate()
            } else {
                displayProgress = targetProgress
            }
        }
    }
}

// MARK: - Ready Welcome View

struct ReadyWelcomeView: View {
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 16) {
            // App icon and greeting
            Image(systemName: "bubble.left.and.bubble.right.fill")
                .font(.system(size: 48))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.blue, .purple],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .scaleEffect(appeared ? 1 : 0.5)
                .opacity(appeared ? 1 : 0)

            VStack(spacing: 6) {
                Text(String(localized: "welcome.greeting"))
                    .font(.system(size: 22, weight: .semibold))

                Text(String(localized: "welcome.subtitle"))
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
            }
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 10)
        }
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                appeared = true
            }
        }
    }
}

// MARK: - Expanded Input View (Fullscreen Text Editor)

struct ExpandedInputView: View {
    @Binding var text: String
    let onSend: () -> Void
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isFocused: Bool

    var body: some View {
        NavigationStack {
            ZStack {
                Color.chatBackgroundDynamic
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    // Text editor
                    TextEditor(text: $text)
                        .font(.body)
                        .focused($isFocused)
                        .scrollContentBackground(.hidden)
                        .background(Color.clear)
                        .padding(.horizontal, 16)
                        .padding(.top, 8)

                    // Bottom bar with send button
                    HStack {
                        Spacer()

                        Button(action: onSend) {
                            HStack(spacing: 6) {
                                Text(String(localized: "common.send", defaultValue: "送信"))
                                    .font(.system(size: 16, weight: .semibold))
                                Image(systemName: "arrow.up.circle.fill")
                                    .font(.system(size: 20))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.gray : Color.blue)
                            .clipShape(Capsule())
                        }
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color.chatInputBackgroundDynamic)
                }
            }
            .navigationTitle(String(localized: "chat.expanded.title", defaultValue: "メッセージを編集"))
            #if !targetEnvironment(macCatalyst)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                }

                ToolbarItem(placement: .primaryAction) {
                    Button(action: {
                        dismiss()
                    }) {
                        Image(systemName: "arrow.down.right.and.arrow.up.left")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .onAppear {
            isFocused = true
        }
    }
}

#Preview {
    ChatView()
        .environmentObject(AppState())
        .environmentObject(ThemeManager())
}
