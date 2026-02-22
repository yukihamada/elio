import SwiftUI

struct OnboardingView: View {
    @Binding var hasCompletedOnboarding: Bool
    @EnvironmentObject var appState: AppState
    @State private var currentPage = 0
    @State private var isDownloading = false
    @State private var downloadProgress: Double = 0
    @State private var downloadProgressInfo: DownloadProgressInfo?
    @State private var downloadError: String?
    @State private var downloadCompleted = false
    @State private var textModelDownloaded = false
    @State private var visionModelDownloaded = false
    @State private var currentDownloadingModel: String = ""
    @State private var isViewReady = false  // For initial loading state
    @State private var goroAnimation = false  // Goro mascot animation
    @State private var showContent = false  // Content fade-in animation
    @State private var showDownloadConfirmation = false  // App Store 4.2.3 compliance: explicit download confirmation
    @State private var showInsufficientStorageAlert = false
    @State private var insufficientStorageAvailable: Int64 = 0
    @State private var insufficientStorageRequired: Int64 = 0
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var modelLoader = ModelLoader.shared
    // TODO: Re-enable after adding KnowledgeBaseManager to Xcode project
    // @ObservedObject private var kbManager = KnowledgeBaseManager.shared
    @AppStorage("justCompletedOnboarding") private var justCompletedOnboarding = false

    // Knowledge Base download state (temporarily disabled)
    // @State private var kbDownloadProgress: [String: Double] = [:]
    // @State private var kbLanguages: [String] = []
    // @State private var kbDownloadCompleted = false

    // Check if running in test mode (Firebase Test Lab or UI Tests)
    private var isTestMode: Bool {
        ProcessInfo.processInfo.arguments.contains("-UITest") ||
        ProcessInfo.processInfo.environment["FIREBASE_TEST_LAB"] == "1" ||
        ProcessInfo.processInfo.arguments.contains("-TestMode")
    }

    // Check if running in skip download mode (for UI testing without model)
    private var isSkipDownloadMode: Bool {
        ProcessInfo.processInfo.arguments.contains("-SkipDownload")
    }

    // Models to download: ElioChat v3 (text) and Qwen3-VL 2B (vision)
    // In test mode, use smallest model (qwen3-0.6b) for faster testing
    private var textModel: ModelLoader.ModelInfo? {
        if isTestMode {
            // Use smallest model for testing
            return modelLoader.availableModels.first { $0.id == "qwen3-0.6b" }
        }
        // Prefer ElioChat v3 > Qwen3 1.7B as fallback
        return modelLoader.availableModels.first { $0.id == "eliochat-1.7b-v3" }
            ?? modelLoader.availableModels.first { $0.id == "qwen3-1.7b" }
    }

    private var visionModel: ModelLoader.ModelInfo? {
        modelLoader.availableModels.first { $0.id == "qwen3-vl-2b" }
    }

    // For backward compatibility
    private var recommendedModel: ModelLoader.ModelInfo? {
        textModel
    }

    var body: some View {
        ZStack {
            // Animated gradient background
            LinearGradient(
                colors: [
                    Color.purple.opacity(0.1),
                    Color.blue.opacity(0.05),
                    Color.chatBackgroundDynamic
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            if !isViewReady {
                // Beautiful loading state with Goro mascot
                VStack(spacing: 24) {
                    // Animated Goro mascot
                    AppLogo(isAnimating: true, size: 100)

                    Text("ElioChatを準備中...")
                        .font(.title3.weight(.medium))
                        .foregroundStyle(.primary)

                    ProgressView()
                        .scaleEffect(1.0)
                }
                .transition(.opacity)
            } else {
                VStack(spacing: 0) {
                    // Spacer for pages 0-2, reduced for page 3
                    if currentPage < 3 {
                        Spacer().frame(height: 20)
                    } else {
                        Spacer().frame(height: 8)
                    }

                    // Page content
                    TabView(selection: $currentPage) {
                        welcomePage
                            .tag(0)

                        featuresPage
                            .tag(1)

                        privacyPage
                            .tag(2)

                        getStartedPage
                            .tag(3)
                    }
                    .tabViewStyle(.page(indexDisplayMode: currentPage == 3 ? .never : .always))

                    // Bottom buttons (only show for pages 0-2, page 3 has its own buttons)
                    if currentPage < 3 {
                        VStack(spacing: 16) {
                            Button(action: {
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                    currentPage += 1
                                }
                            }) {
                                Text("次へ")
                                    .font(.headline)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 16)
                                    .background(
                                        LinearGradient(
                                            colors: [.purple, .blue],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .foregroundColor(.white)
                                    .cornerRadius(14)
                                    .shadow(color: .purple.opacity(0.3), radius: 8, y: 4)
                            }
                        }
                        .padding(.horizontal, 24)
                        .padding(.bottom, 40)
                        .opacity(showContent ? 1 : 0)
                    }
                }
                .opacity(showContent ? 1 : 0)
            }
        }
        .onAppear {
            // Skip download mode for UI testing - immediately complete onboarding
            if isSkipDownloadMode {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    justCompletedOnboarding = true
                    hasCompletedOnboarding = true
                    dismiss()
                }
                return
            }

            // NOTE: Do NOT start download automatically here.
            // Per App Store Guideline 4.2.3, we must disclose download size
            // and prompt the user before starting the download.
            // Download will start when user taps the button on getStartedPage.

            // Delay to let view initialize properly, then show with animation
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                withAnimation(.easeOut(duration: 0.3)) {
                    isViewReady = true
                }
                // Staggered content animation
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    withAnimation(.easeOut(duration: 0.4)) {
                        showContent = true
                    }
                }
            }
            // Start Goro animation
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                goroAnimation = true
            }
        }
    }

    /// Start model download in background without blocking UI
    private func startBackgroundDownload() {
        // Check if already downloading or completed
        guard !isDownloading && !downloadCompleted else { return }

        // Check if model is already downloaded
        if let text = textModel, modelLoader.isModelDownloaded(text.id) {
            textModelDownloaded = true
            downloadCompleted = true
            return
        }

        // Pre-check storage before starting background download
        if let text = textModel {
            switch StorageChecker.checkStorage(for: text.sizeBytes) {
            case .success:
                break
            case .failure(.insufficientStorage(let available, let required)):
                insufficientStorageAvailable = available
                insufficientStorageRequired = required
                showInsufficientStorageAlert = true
                return
            case .failure:
                break
            }
        }

        // Determine KB languages to download
        // TODO: Re-enable after adding KnowledgeBaseManager to Xcode project
        // kbLanguages = kbManager.determineLanguagesToDownload()

        // Start background download
        isDownloading = true
        downloadError = nil

        Task {
            do {
                // TODO: KB download temporarily disabled
                // Start KB download in parallel (when model reaches 50%)
                let kbDownloadTask = Task {
                    // Placeholder - KB download disabled
                    try? await Task.sleep(nanoseconds: 100_000_000)
                }
                /*
                let kbDownloadTask = Task {
                    // Wait for model to reach 50%
                    while !Task.isCancelled {
                        if downloadProgress >= 0.5 {
                            break
                        }
                        try? await Task.sleep(nanoseconds: 500_000_000)
                    }

                    // Start KB downloads
                    do {
                        try await kbManager.downloadKnowledgeBases(languages: kbLanguages)
                        await MainActor.run {
                            kbDownloadCompleted = true
                            print("[OnboardingView] KB downloads completed")
                        }
                    } catch {
                        print("[OnboardingView] KB download error: \(error)")
                    }
                }
                */

                if let text = textModel, !modelLoader.isModelDownloaded(text.id) {
                    await MainActor.run {
                        currentDownloadingModel = text.id
                        downloadProgress = 0
                        downloadProgressInfo = nil
                    }

                    print("[OnboardingView] Starting background download for model: \(text.id)")

                    // Poll progress in background
                    let progressTask = Task { @MainActor in
                        while !Task.isCancelled {
                            if let progress = modelLoader.downloadProgress[text.id] {
                                self.downloadProgress = progress
                            }
                            if let info = modelLoader.downloadProgressInfo[text.id] {
                                self.downloadProgressInfo = info
                            }
                            try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
                        }
                    }

                    try await modelLoader.downloadModel(text)
                    progressTask.cancel()

                    await MainActor.run {
                        textModelDownloaded = true
                        downloadProgress = 1.0
                        downloadProgressInfo = nil
                        currentDownloadingModel = ""
                        print("[OnboardingView] Model download completed")
                    }

                    // Wait for KB downloads to complete
                    await kbDownloadTask.value

                    await MainActor.run {
                        downloadCompleted = true
                        print("[OnboardingView] All downloads completed")
                    }
                }
            } catch {
                await MainActor.run {
                    if case ModelLoaderError.insufficientStorage(let available, let required) = error {
                        isDownloading = false
                        downloadCompleted = false
                        insufficientStorageAvailable = available
                        insufficientStorageRequired = required
                        showInsufficientStorageAlert = true
                    } else {
                        isDownloading = false
                        downloadCompleted = false
                        downloadError = "ダウンロードに失敗しました: \(error.localizedDescription)"
                        print("[OnboardingView] Background download failed: \(error)")
                    }
                }
            }
        }
    }

    private var welcomePage: some View {
        VStack(spacing: 20) {
            Spacer()

            // Animated Goro mascot
            AppLogo(isAnimating: goroAnimation, size: 140)
                .padding(.bottom, 8)

            Text(String(localized: "onboarding.welcome.title"))
                .font(.system(size: 34, weight: .bold))
                .multilineTextAlignment(.center)

            Text(String(localized: "onboarding.welcome.subtitle"))
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            // Feature badges
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    FeatureBadge(icon: "airplane", text: "オフライン", color: .green)
                    FeatureBadge(icon: "lock.shield.fill", text: "プライベート", color: .blue)
                }
                HStack(spacing: 12) {
                    FeatureBadge(icon: "sparkles", text: "日本語最適化", color: .purple)
                    FeatureBadge(icon: "bolt.fill", text: "高速", color: .orange)
                }
            }
            .padding(.top, 8)

            Spacer()
            Spacer()
        }
        .padding(.horizontal, 24)
    }

    private var featuresPage: some View {
        VStack(spacing: 24) {
            Spacer()

            // Goro with speech bubble
            HStack(alignment: .top, spacing: 12) {
                AppLogo(isAnimating: goroAnimation, size: 60)

                Text("私ができることを\n紹介しますね！")
                    .font(.subheadline)
                    .padding(12)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            Text(String(localized: "onboarding.features.title"))
                .font(.system(size: 26, weight: .bold))

            VStack(alignment: .leading, spacing: 16) {
                AnimatedFeatureRow(
                    icon: "airplane",
                    iconColor: .green,
                    title: String(localized: "onboarding.feature.offline"),
                    description: String(localized: "onboarding.feature.offline.desc")
                )
                AnimatedFeatureRow(
                    icon: "lock.shield.fill",
                    iconColor: .blue,
                    title: String(localized: "onboarding.feature.privacy"),
                    description: String(localized: "onboarding.feature.privacy.desc")
                )
                AnimatedFeatureRow(
                    icon: "cpu.fill",
                    iconColor: .purple,
                    title: "独自のAIモデル",
                    description: "日本語に最適化した専用モデル"
                )
                AnimatedFeatureRow(
                    icon: "slider.horizontal.3",
                    iconColor: .orange,
                    title: "複数モデル対応",
                    description: "用途に合わせてモデル切り替え"
                )
            }

            Spacer()
            Spacer()
        }
        .padding(.horizontal, 24)
    }

    private var privacyPage: some View {
        VStack(spacing: 24) {
            Spacer()

            // Goro with lock
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.green.opacity(0.2), .blue.opacity(0.1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 120, height: 120)

                AppLogo(isAnimating: goroAnimation, size: 80)

                // Lock badge
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.green)
                    .padding(8)
                    .background(Color(.systemBackground))
                    .clipShape(Circle())
                    .offset(x: 40, y: 35)
            }

            Text(String(localized: "onboarding.privacy.title"))
                .font(.system(size: 24, weight: .bold))
                .multilineTextAlignment(.center)

            VStack(alignment: .leading, spacing: 14) {
                AnimatedPrivacyItem(icon: "iphone", text: String(localized: "onboarding.privacy.item1"))
                AnimatedPrivacyItem(icon: "xmark.icloud.fill", text: String(localized: "onboarding.privacy.item2"))
                AnimatedPrivacyItem(icon: "hand.raised.fill", text: String(localized: "onboarding.privacy.item3"))
            }
            .padding(.horizontal, 16)

            // Trust badge
            HStack(spacing: 6) {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(.green)
                Text("100% ローカル処理")
                    .font(.footnote.weight(.medium))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color.green.opacity(0.1))
            .clipShape(Capsule())

            Spacer()
            Spacer()
        }
        .padding(.horizontal, 24)
    }

    private var getStartedPage: some View {
        VStack(spacing: 0) {
            if isDownloading || downloadCompleted {
                // Show interactive chat during download
                OnboardingChatView(
                    downloadProgress: $downloadProgress,
                    isDownloadComplete: $downloadCompleted,
                    downloadProgressInfo: downloadProgressInfo,
                    onComplete: {
                        completeOnboarding()
                    }
                )
            } else if textModel != nil || visionModel != nil {
                // Pre-download view
                VStack(spacing: 20) {
                    Spacer()

                    // Model download section
                    ZStack {
                        Circle()
                            .fill(Color.cyan.opacity(0.15))
                            .frame(width: 100, height: 100)

                        Image(systemName: "arrow.down.circle.fill")
                            .font(.system(size: 50))
                            .foregroundStyle(.cyan)
                    }

                    Text("AIモデルをダウンロード")
                        .font(.system(size: 24, weight: .bold))

                    // Device tier info
                    HStack(spacing: 8) {
                        Image(systemName: "iphone")
                            .foregroundStyle(.secondary)
                        Text("お使いのデバイス: \(DeviceTier.current.displayName)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    // Model info card
                    if let model = textModel {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Image(systemName: "cpu.fill")
                                    .foregroundStyle(.purple)
                                Text(model.name)
                                    .font(.headline)
                                Spacer()
                                Text(model.size)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }

                            Text(model.description)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                            HStack(spacing: 16) {
                                Label("日本語対応", systemImage: "globe.asia.australia.fill")
                                Label("オフライン可", systemImage: "airplane")
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                        .padding()
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                    }

                    // Download size disclosure (App Store Guideline 4.2.3)
                    if let model = textModel {
                        VStack(spacing: 8) {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.down.doc.fill")
                                    .foregroundStyle(.orange)
                                Text("ダウンロードサイズ: \(model.size)")
                                    .font(.subheadline.weight(.semibold))
                            }

                            HStack(spacing: 4) {
                                Image(systemName: "wifi")
                                    .foregroundStyle(.secondary)
                                Text("Wi-Fi接続での利用を推奨します")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 12)
                        .padding(.horizontal, 16)
                        .background(Color.orange.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }

                    Text("ダウンロード中にElioChatについて説明します")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    Spacer()

                    // Download button - shows confirmation alert (App Store Guideline 4.2.3)
                    Button(action: {
                        showDownloadConfirmation = true
                    }) {
                        HStack {
                            Image(systemName: "arrow.down.circle.fill")
                            if let model = textModel {
                                Text("ダウンロード (\(model.size))")
                            } else {
                                Text("ダウンロードを開始")
                            }
                        }
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            LinearGradient(
                                colors: [.purple, .blue],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                    // App Store Guideline 4.2.3: Explicit download confirmation with size disclosure
                    .alert("AIモデルをダウンロード", isPresented: $showDownloadConfirmation) {
                        Button("ダウンロード開始", role: nil) {
                            startModelDownload()
                        }
                        Button("キャンセル", role: .cancel) {}
                    } message: {
                        if let model = textModel {
                            Text("\(model.name)（\(model.size)）をダウンロードします。\n\nWi-Fi環境でのダウンロードを推奨します。\n\n今すぐダウンロードしますか？")
                        } else {
                            Text("AIモデルをダウンロードします。続行しますか？")
                        }
                    }
                    .alert(
                        "ストレージが不足しています",
                        isPresented: $showInsufficientStorageAlert
                    ) {
                        Button("不要なデータを削除する") {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        }
                        Button("ChatWeb.aiクラウドを使う（無料で始められます）") {
                            switchToChatWebAndComplete()
                        }
                        Button("キャンセル", role: .cancel) {}
                    } message: {
                        let availableStr = StorageChecker.formatGB(insufficientStorageAvailable)
                        let requiredStr = StorageChecker.formatGB(insufficientStorageRequired)
                        Text("ストレージが不足しています（残り: \(availableStr)、必要: \(requiredStr)）\n\nモデルをダウンロードしなくても、ChatWeb.aiのクラウドAIをすぐ使えます。一定量まで無料です。")
                    }
                }
                .padding(.horizontal, 32)
            } else {
                // Fallback if no model found
                VStack(spacing: 20) {
                    Spacer()

                    ZStack {
                        Circle()
                            .fill(Color.blue.opacity(0.15))
                            .frame(width: 100, height: 100)

                        Image(systemName: "hand.tap.fill")
                            .font(.system(size: 50))
                            .foregroundStyle(.blue)
                    }

                    Text(String(localized: "onboarding.getstarted.title"))
                        .font(.system(size: 24, weight: .bold))

                    Text(String(localized: "onboarding.getstarted.subtitle"))
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    Spacer()
                }
                .padding(.horizontal, 32)
            }
        }
        .onAppear {
            // Check if model is already downloaded
            if let text = textModel, modelLoader.isModelDownloaded(text.id) {
                textModelDownloaded = true
                downloadCompleted = true
            }
        }
        .onChange(of: modelLoader.downloadProgress) { _, newProgress in
            // Update local progress from shared ModelLoader
            print("[OnboardingView] downloadProgress onChange - keys: \(Array(newProgress.keys))")
            if let modelId = textModel?.id, let progress = newProgress[modelId] {
                print("[OnboardingView] downloadProgress onChange - Setting progress to \(Int(progress * 100))%")
                self.downloadProgress = progress
            }
        }
        .onChange(of: modelLoader.downloadProgressInfo) { _, newInfo in
            // Update local progress info from shared ModelLoader
            print("[OnboardingView] onChange triggered - keys: \(Array(newInfo.keys)), textModel?.id: \(textModel?.id ?? "nil")")
            if let modelId = textModel?.id, let info = newInfo[modelId] {
                print("[OnboardingView] onChange - Setting progress to \(Int(info.progress * 100))%")
                self.downloadProgressInfo = info
            }
        }
    }

    private func startModelDownload() {
        // Pre-check storage before starting download
        if let text = textModel {
            switch StorageChecker.checkStorage(for: text.sizeBytes) {
            case .success:
                break
            case .failure(.insufficientStorage(let available, let required)):
                insufficientStorageAvailable = available
                insufficientStorageRequired = required
                showInsufficientStorageAlert = true
                return
            case .failure:
                break // Other errors will be caught during download
            }
        }

        isDownloading = true
        downloadError = nil

        Task {
            do {
                // Download ElioChat model (or fallback text model)
                if let text = textModel, !modelLoader.isModelDownloaded(text.id) {
                    await MainActor.run {
                        currentDownloadingModel = text.id
                        downloadProgress = 0
                        downloadProgressInfo = nil
                    }

                    print("[OnboardingView] Starting download for model: \(text.id)")

                    // Poll progress more frequently (every 100ms)
                    let progressTask = Task { @MainActor in
                        print("[OnboardingView] Progress polling task started for: \(text.id)")
                        // Wait a moment for download to initialize
                        try? await Task.sleep(nanoseconds: 200_000_000) // 200ms
                        var logCounter = 0
                        while !Task.isCancelled {
                            let progress = modelLoader.downloadProgress[text.id]
                            let info = modelLoader.downloadProgressInfo[text.id]

                            // Debug log every 1 second (10 iterations at 100ms)
                            logCounter += 1
                            if logCounter % 10 == 0 {
                                print("[OnboardingView] Polling - modelId: \(text.id), progress: \(progress ?? -1), info: \(info != nil ? "\(Int((info?.progress ?? 0) * 100))%" : "nil")")
                                print("[OnboardingView] Available keys in downloadProgress: \(Array(modelLoader.downloadProgress.keys))")
                            }

                            if let progress = progress {
                                self.downloadProgress = progress
                            }
                            if let info = info {
                                self.downloadProgressInfo = info
                            }
                            try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
                        }
                    }

                    try await modelLoader.downloadModel(text)
                    progressTask.cancel()

                    await MainActor.run {
                        textModelDownloaded = true
                        downloadProgress = 1.0
                        downloadProgressInfo = nil
                    }
                }

                // Download complete - don't auto-load yet, wait for chat to finish
                await MainActor.run {
                    downloadCompleted = true
                    currentDownloadingModel = ""
                    // Keep isDownloading true until chat finishes (for UI state)
                }

            } catch {
                await MainActor.run {
                    // Handle insufficient storage error from within download flow
                    if case ModelLoaderError.insufficientStorage(let available, let required) = error {
                        isDownloading = false
                        downloadCompleted = false
                        insufficientStorageAvailable = available
                        insufficientStorageRequired = required
                        showInsufficientStorageAlert = true
                    } else {
                        isDownloading = false
                        downloadCompleted = false
                        downloadError = "ダウンロードに失敗しました: \(error.localizedDescription)"
                    }
                }
            }
        }
    }

    /// Switch to ChatWeb.ai cloud mode and complete onboarding without downloading any model
    private func switchToChatWebAndComplete() {
        let chatModeManager = ChatModeManager.shared
        chatModeManager.setMode(.chatweb)

        // Complete onboarding without a local model
        justCompletedOnboarding = true
        hasCompletedOnboarding = true
        dismiss()
    }

    private func completeOnboarding() {
        // Load the downloaded model before completing
        Task {
            if let text = textModel {
                do {
                    try await appState.loadModel(named: text.id)
                } catch {
                    print("Failed to load model: \(error)")
                }
            }

            await MainActor.run {
                isDownloading = false
                justCompletedOnboarding = true  // Prevent keyboard from auto-showing
                hasCompletedOnboarding = true
                dismiss()
            }
        }
    }
}

struct FeatureRow: View {
    let icon: String
    var iconColor: Color = .purple
    let title: String
    let description: String

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(iconColor.opacity(0.15))
                    .frame(width: 44, height: 44)

                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundStyle(iconColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct PrivacyItem: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(.green)
                .frame(width: 24)
            Text(text)
                .font(.subheadline)
        }
    }
}

struct SetupStepRow: View {
    let number: Int
    let text: String
    let isActive: Bool

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(isActive ? Color.blue : Color.gray.opacity(0.3))
                    .frame(width: 32, height: 32)

                Text("\(number)")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(isActive ? .white : .secondary)
            }

            Text(text)
                .font(.subheadline)
                .foregroundStyle(isActive ? .primary : .secondary)

            Spacer()

            if number == 3 {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
        }
    }
}

// MARK: - Model Download Card

struct ModelDownloadCard: View {
    let model: ModelLoader.ModelInfo
    let label: String
    let labelColor: Color
    let isDownloaded: Bool
    let isDownloading: Bool
    let progressInfo: DownloadProgressInfo?

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                // Status icon
                ZStack {
                    Circle()
                        .fill(isDownloaded ? Color.green.opacity(0.15) : labelColor.opacity(0.15))
                        .frame(width: 40, height: 40)

                    if isDownloaded {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else if isDownloading {
                        CircularProgressView(progress: progressInfo?.progress ?? 0)
                            .frame(width: 30, height: 30)
                    } else {
                        Image(systemName: "arrow.down.circle")
                            .foregroundStyle(labelColor)
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(model.name)
                            .font(.subheadline.weight(.medium))
                        Text(label)
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(labelColor.opacity(0.2))
                            .foregroundStyle(labelColor)
                            .cornerRadius(4)
                    }
                    Text(model.size)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if isDownloaded {
                    Text("完了")
                        .font(.caption)
                        .foregroundStyle(.green)
                } else if isDownloading, let info = progressInfo {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(Int(info.progress * 100))%")
                            .font(.caption.monospacedDigit())
                        if info.speed > 0 {
                            Text(info.speedFormatted)
                                .font(.caption2)
                        }
                    }
                    .foregroundStyle(.secondary)
                }
            }

            // Progress bar with ETA
            if isDownloading, let info = progressInfo {
                VStack(spacing: 4) {
                    ProgressView(value: info.progress)
                        .progressViewStyle(.linear)
                        .tint(labelColor)

                    if let eta = info.etaFormatted {
                        Text(eta)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(12)
        .background(Color(.systemGray6))
        .cornerRadius(10)
    }
}

// MARK: - Circular Progress View

struct CircularProgressView: View {
    let progress: Double

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.gray.opacity(0.3), lineWidth: 6)

            Circle()
                .trim(from: 0, to: progress)
                .stroke(Color.cyan, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.2), value: progress)

            Text("\(Int(progress * 100))%")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.cyan)
        }
    }
}

// MARK: - App Logo

struct AppLogo: View {
    var isAnimating: Bool = false
    var size: CGFloat = 80

    @State private var scale: CGFloat = 1.0

    var body: some View {
        ZStack {
            // Outer glow
            Circle()
                .fill(
                    RadialGradient(
                        colors: [.purple.opacity(0.3), .blue.opacity(0.1), .clear],
                        center: .center,
                        startRadius: size * 0.3,
                        endRadius: size * 0.6
                    )
                )
                .frame(width: size * 1.2, height: size * 1.2)
                .scaleEffect(isAnimating ? 1.1 : 1.0)

            // App Icon (uses AppLogo image asset which is a copy of AppIcon)
            if let uiImage = UIImage(named: "AppLogo") {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
                    .shadow(color: .purple.opacity(0.4), radius: 10, y: 5)
                    .scaleEffect(scale)
            } else {
                // Fallback if AppIcon not found
                RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.5, green: 0.3, blue: 0.9),
                                Color(red: 0.3, green: 0.4, blue: 0.95)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: size, height: size)
                    .shadow(color: .purple.opacity(0.4), radius: 10, y: 5)
                    .overlay(
                        Image(systemName: "brain.head.profile")
                            .font(.system(size: size * 0.5, weight: .medium))
                            .foregroundStyle(.white)
                    )
                    .scaleEffect(scale)
            }
        }
        .onAppear {
            if isAnimating {
                withAnimation(.easeInOut(duration: 2).repeatForever(autoreverses: true)) {
                    scale = 1.05
                }
            }
        }
    }
}

// MARK: - Feature Badge

struct FeatureBadge: View {
    let icon: String
    let text: String
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(color)
            Text(text)
                .font(.caption.weight(.medium))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(color.opacity(0.12))
        .clipShape(Capsule())
    }
}

// MARK: - Animated Feature Row

struct AnimatedFeatureRow: View {
    let icon: String
    var iconColor: Color = .purple
    let title: String
    let description: String

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(iconColor.opacity(0.15))
                    .frame(width: 44, height: 44)

                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundStyle(iconColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Animated Privacy Item

struct AnimatedPrivacyItem: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.system(size: 18))
            Text(text)
                .font(.subheadline)
            Spacer()
        }
    }
}

#Preview {
    OnboardingView(hasCompletedOnboarding: .constant(false))
        .environmentObject(AppState())
}
