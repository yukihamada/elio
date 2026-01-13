import SwiftUI
import AVFoundation
import PhotosUI
import PDFKit
import UniformTypeIdentifiers

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
    @State private var attachedImages: [UIImage] = []
    @State private var showingVisionModelAlert = false
    @State private var showingDownloadVisionModel = false
    @State private var isSwitchingToVisionModel = false
    @State private var showingModelSettings = false
    @StateObject private var whisperManager = WhisperManager.shared
    @State private var showingWhisperDownload = false
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

    var body: some View {
        ZStack {
            // Background
            Color.chatBackgroundDynamic
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                headerView

                if appState.isInitialLoading && !AppState.isScreenshotMode {
                    skeletonView
                } else if !appState.isModelLoaded && !AppState.isScreenshotMode {
                    modelNotLoadedView
                } else {
                    chatContent
                }

                inputBar
            }

            // Processing overlay - prevents white screen during CPU-heavy operations
            if isGenerating {
                Color.black.opacity(0.02)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
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
                handleImageAttachment()
            }
            Button(String(localized: "attachment.camera")) {
                handleCameraAttachment()
            }
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
        .fullScreenCover(isPresented: $showingCamera) {
            CameraPicker(onImageCaptured: { image in
                // Create thumbnail to reduce memory usage
                attachedImages.append(createThumbnail(image))
            })
        }
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
        .alert(String(localized: "whisper.download.title"), isPresented: $showingWhisperDownload) {
            Button(String(localized: "whisper.download.action")) {
                downloadWhisperModel()
            }
            Button(String(localized: "common.cancel"), role: .cancel) {}
        } message: {
            Text(String(localized: "whisper.download.message"))
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
            // Whisper download progress
            if whisperManager.isDownloading {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                VStack(spacing: 12) {
                    ProgressView(value: whisperManager.downloadProgress)
                        .progressViewStyle(.linear)
                        .frame(width: 200)
                    Text(String(localized: "whisper.downloading"))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white)
                    Text("\(Int(whisperManager.downloadProgress * 100))%")
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
        // Handle pending quick question from widget and restore draft
        .onAppear {
            // Screenshot mode: Load mock data
            if AppState.isScreenshotMode {
                appState.currentConversation = ScreenshotMockData.getMockConversation()
                appState.conversations = ScreenshotMockData.getMockConversations()
                appState.currentModelName = ScreenshotMockData.getMockModelName()
                return
            }

            // Restore draft input from crash recovery
            if inputText.isEmpty, let savedDraft = UserDefaults.standard.string(forKey: "chat_draft_input"), !savedDraft.isEmpty {
                inputText = savedDraft
            }

            // Handle widget quick question
            if let question = appState.pendingQuickQuestion {
                inputText = question
                appState.pendingQuickQuestion = nil
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
                    let text = try await whisperManager.stopRecording()
                    if !text.isEmpty {
                        inputText = text
                    }
                } catch {
                    print("Transcription error: \(error)")
                }
            }
        } else {
            // Check if model is downloaded
            if whisperManager.isModelDownloaded {
                // Start recording
                startVoiceRecording()
            } else {
                // Show download prompt
                showingWhisperDownload = true
            }
        }
    }

    private func startVoiceRecording() {
        Task {
            do {
                try await whisperManager.startRecording()
                isVoiceRecording = true
            } catch {
                print("Recording error: \(error)")
            }
        }
    }

    private func downloadWhisperModel() {
        Task {
            do {
                try await whisperManager.downloadModelIfNeeded()
                // After download, start recording
                startVoiceRecording()
            } catch {
                print("Download error: \(error)")
            }
        }
    }

    // MARK: - Computed Properties

    private var truncatedModelName: String {
        guard let modelName = appState.currentModelName else {
            return "Elio"
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

            // Quick settings button (for model parameters)
            if appState.isModelLoaded || AppState.isScreenshotMode {
                Button(action: { showingModelSettings = true }) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }

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

                SuggestionChip(text: String(localized: "chat.suggestion.weather"), icon: "cloud.sun") {
                    inputText = String(localized: "chat.suggestion.weather")
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

            // Loading indicator when model is loading (not during initial startup)
            if appState.isLoading && !appState.isInitialLoading {
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
                // Attachment button - always enabled, handles vision model switching
                Button(action: handleAttachmentTap) {
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

                // Text input - allow input even during generation
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

                        // Template button for quick prompts
                    Button(action: { showingTemplates = true }) {
                        Image(systemName: "text.badge.star")
                            .font(.system(size: 18))
                            .foregroundStyle(.secondary)
                    }
                    .disabled(isGenerating)

                    // Microphone button for voice input
                    Button(action: handleMicrophoneTap) {
                        Image(systemName: isVoiceRecording ? "stop.circle.fill" : "mic.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(isVoiceRecording ? .red : .secondary)
                    }
                    .disabled(isGenerating || whisperManager.isTranscribing)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.chatInputBackgroundDynamic)
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(isVoiceRecording ? Color.red : Color.chatBorderDynamic, lineWidth: isVoiceRecording ? 2 : 1)
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
        .animation(nil, value: isInputFocused)
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

        // Force keyboard dismissal immediately
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
        // Update title for first message
        if appState.currentConversation?.messages.count == 1 {
            let titleText = trimmedText.isEmpty ? (savedWebContent?.title ?? savedPDFName ?? "Untitled") : trimmedText
            appState.currentConversation?.title = String(titleText.prefix(30)) + (titleText.count > 30 ? "..." : "")
        }

        isGenerating = true
        streamingResponse = ""
        displayedResponse = ""

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

            // 会話完了を記録（レビュー促進用）
            ReviewManager.shared.recordConversationCompleted()
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
                // ポジティブフィードバック時にレビュー促進をトリガー
                if type == .positive {
                    Task { @MainActor in
                        ReviewManager.shared.recordPositiveRating()
                    }
                }
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
            .navigationBarTitleDisplayMode(.inline)
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

#Preview {
    ChatView()
        .environmentObject(AppState())
        .environmentObject(ThemeManager())
}
