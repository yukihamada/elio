import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var themeManager: ThemeManager
    @StateObject private var modelLoader = ModelLoader()
    @StateObject private var languageManager = LanguageManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var loadingModelId: String?
    @State private var showMoreModels = false
    @State private var showLanguageChangeAlert = false
    @State private var showingPromptEditor = false
    @AppStorage("custom_system_prompt") private var customSystemPrompt: String = ""

    // Models grouped by category
    private func modelsForCategory(_ category: ModelCategory) -> [ModelLoader.ModelInfo] {
        modelLoader.availableModels.filter { model in
            model.category == category && !model.isTooHeavy(for: modelLoader.deviceTier)
        }
    }

    // Categories to show (excluding empty ones)
    private var visibleCategories: [ModelCategory] {
        ModelCategory.allCases.filter { !modelsForCategory($0).isEmpty }
    }

    // Main categories (always expanded)
    private var mainCategories: [ModelCategory] {
        [.recommended, .japanese, .efficient, .vision]
    }

    // Total downloaded size
    private var totalDownloadedSizeText: String {
        let totalBytes = modelLoader.totalDownloadedSize()
        return ModelLoader.formatSize(totalBytes)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                // Background
                Color.chatBackgroundDynamic
                    .ignoresSafeArea()

                ScrollView(.vertical, showsIndicators: true) {
                    VStack(spacing: 24) {
                        // Header
                        headerView
                            .padding(.top, 8)

                        // Model Section
                        modelSection

                        // Inference Mode Section
                        inferenceModeSection

                        // Appearance Section
                        appearanceSection

                        // Language Section
                        languageSection

                        // System Prompt Section
                        systemPromptSection

                        // MCP Server Section
                        mcpSection

                        // About Section
                        aboutSection

                        // Feedback Section
                        feedbackSection

                        // Privacy Badge
                        privacyBadge
                            .padding(.bottom, 20)
                    }
                    .padding(.horizontal, 20)
                    .frame(maxWidth: .infinity)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
            .navigationTitle(String(localized: "settings.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(String(localized: "common.done")) { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
    }

    // MARK: - Header

    private var headerView: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(.linearGradient(
                        colors: [.purple.opacity(0.2), .blue.opacity(0.2)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .frame(width: 80, height: 80)

                Image(systemName: "cpu.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(.linearGradient(
                        colors: [.purple, .blue],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
            }

            VStack(spacing: 4) {
                Text("Elio")
                    .font(.system(size: 22, weight: .bold, design: .rounded))

                if appState.isModelLoaded, let modelName = appState.currentModelName {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(.green)
                            .frame(width: 8, height: 8)
                        Text(modelName)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text(String(localized: "chat.model.not.loaded"))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Model Section

    private var modelSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header with device tier and total size
            HStack {
                SectionHeader(title: String(localized: "settings.model.section"), icon: "brain.head.profile", color: .purple)

                Spacer()

                // Total downloaded size badge
                if modelLoader.totalDownloadedSize() > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "internaldrive.fill")
                            .font(.system(size: 10))
                        Text(totalDownloadedSizeText)
                    }
                    .font(.system(size: 11, weight: .medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.purple.opacity(0.1))
                    .foregroundStyle(.purple)
                    .clipShape(Capsule())
                }
            }

            // Device tier indicator
            HStack(spacing: 6) {
                Image(systemName: "cpu")
                    .font(.system(size: 11))
                Text(modelLoader.deviceTier.displayName)
                Text("•")
                Text("推奨: \(modelLoader.deviceTier.recommendedModelSize)")
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.leading, 4)

            // Main categories (always shown)
            ForEach(mainCategories, id: \.self) { category in
                let models = modelsForCategory(category)
                if !models.isEmpty {
                    categorySection(category: category, models: models)
                }
            }

            // Others section (collapsible)
            let othersModels = modelsForCategory(.others)
            if !othersModels.isEmpty {
                VStack(spacing: 10) {
                    Button(action: {
                        withAnimation(.spring(response: 0.3)) {
                            showMoreModels.toggle()
                        }
                    }) {
                        HStack(spacing: 8) {
                            Image(systemName: showMoreModels ? "chevron.up" : "chevron.down")
                                .font(.system(size: 12, weight: .semibold))
                            Text(showMoreModels
                                 ? String(localized: "settings.model.show.less")
                                 : "その他 (\(othersModels.count))")
                                .font(.system(size: 14, weight: .medium))
                        }
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color(.tertiarySystemBackground))
                        )
                    }

                    if showMoreModels {
                        ForEach(othersModels) { model in
                            modelCard(for: model)
                                .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
                }
            }

            Text(String(localized: "settings.model.local.execution"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
        }
    }

    // Category section with header
    private func categorySection(category: ModelCategory, models: [ModelLoader.ModelInfo]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Category header
            HStack(spacing: 6) {
                Image(systemName: categoryIcon(for: category))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(categoryColor(for: category))
                Text(category.displayName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.leading, 4)

            ForEach(models) { model in
                modelCard(for: model)
            }
        }
    }

    private func categoryIcon(for category: ModelCategory) -> String {
        switch category {
        case .recommended: return "star.fill"
        case .japanese: return "character.ja"
        case .vision: return "camera.fill"
        case .efficient: return "bolt.fill"
        case .others: return "ellipsis.circle"
        }
    }

    private func categoryColor(for category: ModelCategory) -> Color {
        switch category {
        case .recommended: return .orange
        case .japanese: return .red
        case .vision: return .blue
        case .efficient: return .green
        case .others: return .gray
        }
    }

    private func modelCard(for model: ModelLoader.ModelInfo) -> some View {
        SettingsModelCard(
            model: model,
            isDownloaded: modelLoader.isModelDownloaded(model.id),
            isLoaded: appState.currentModelName == model.name,
            isRecommended: model.isRecommended(for: modelLoader.deviceTier),
            isTooHeavy: false, // Already filtered out
            downloadProgress: modelLoader.downloadProgress[model.id],
            loadingProgress: loadingModelId == model.id ? appState.loadingProgress : nil,
            onDownload: {
                Task.detached {
                    try? await modelLoader.downloadModel(model)
                }
            },
            onLoad: {
                loadingModelId = model.id
                Task {
                    do {
                        try await appState.loadModel(named: model.id)
                        loadingModelId = nil
                        dismiss()
                    } catch {
                        loadingModelId = nil
                        print("Failed to load model: \(error)")
                    }
                }
            },
            onDelete: {
                if appState.currentModelName == model.name {
                    appState.unloadModel()
                }
                try? modelLoader.deleteModel(model.id)
            }
        )
    }

    // MARK: - Inference Mode Section

    private var inferenceModeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: String(localized: "inference.mode.title"), icon: "bolt.fill", color: .yellow)

            VStack(spacing: 0) {
                ForEach(Array(InferenceMode.allCases.enumerated()), id: \.element) { index, mode in
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            appState.setInferenceMode(mode)
                        }
                    }) {
                        HStack(spacing: 12) {
                            Image(systemName: mode.icon)
                                .font(.system(size: 18))
                                .foregroundStyle(mode == appState.inferenceMode ? .primary : .secondary)
                                .frame(width: 28)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(mode.displayName)
                                    .font(.system(size: 15))
                                    .foregroundStyle(.primary)

                                Text(mode.description)
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            if mode == appState.inferenceMode {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(.blue)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }
                    .buttonStyle(.plain)

                    if index < InferenceMode.allCases.count - 1 {
                        Divider()
                            .padding(.leading, 56)
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.chatInputBackgroundDynamic)
            )
        }
    }

    // MARK: - Appearance Section

    private var appearanceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: String(localized: "settings.appearance.section"), icon: "paintbrush", color: .indigo)

            VStack(spacing: 0) {
                ForEach(Array(AppTheme.allCases.enumerated()), id: \.element) { index, theme in
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            themeManager.currentTheme = theme
                        }
                    }) {
                        HStack(spacing: 12) {
                            Image(systemName: theme.icon)
                                .font(.system(size: 18))
                                .foregroundStyle(theme == themeManager.currentTheme ? .primary : .secondary)
                                .frame(width: 28)

                            Text(theme.displayName)
                                .font(.system(size: 15))
                                .foregroundStyle(.primary)

                            Spacer()

                            if theme == themeManager.currentTheme {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(.blue)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                    }
                    .buttonStyle(.plain)

                    if index < AppTheme.allCases.count - 1 {
                        Divider()
                            .padding(.leading, 56)
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.chatInputBackgroundDynamic)
            )
        }
    }

    // MARK: - Language Section

    private var languageSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: String(localized: "settings.language.section"), icon: "globe", color: .cyan)

            VStack(spacing: 0) {
                ForEach(Array(AppLanguage.allCases.enumerated()), id: \.element) { index, language in
                    Button(action: {
                        if language != languageManager.currentLanguage {
                            languageManager.currentLanguage = language
                            showLanguageChangeAlert = true
                        }
                    }) {
                        HStack(spacing: 12) {
                            Image(systemName: language.icon)
                                .font(.system(size: 18))
                                .foregroundStyle(language == languageManager.currentLanguage ? .primary : .secondary)
                                .frame(width: 28)

                            Text(language.displayName)
                                .font(.system(size: 15))
                                .foregroundStyle(.primary)

                            Spacer()

                            if language == languageManager.currentLanguage {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(.blue)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                    }
                    .buttonStyle(.plain)

                    if index < AppLanguage.allCases.count - 1 {
                        Divider()
                            .padding(.leading, 56)
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.chatInputBackgroundDynamic)
            )

            Text(String(localized: "settings.language.restart.hint"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
        }
        .alert(String(localized: "settings.language.changed.title"), isPresented: $showLanguageChangeAlert) {
            Button(String(localized: "common.ok")) {}
        } message: {
            Text(String(localized: "settings.language.changed.message"))
        }
    }

    // MARK: - System Prompt Section

    private var systemPromptSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: String(localized: "settings.prompt.section"), icon: "text.bubble", color: .purple)

            Button(action: { showingPromptEditor = true }) {
                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.purple.opacity(0.1))
                            .frame(width: 44, height: 44)
                        Image(systemName: "pencil.and.outline")
                            .font(.system(size: 18))
                            .foregroundStyle(.purple)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(localized: "settings.prompt.edit"))
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.primary)
                        Text(customSystemPrompt.isEmpty ? String(localized: "settings.prompt.default") : String(localized: "settings.prompt.custom"))
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.chatInputBackgroundDynamic)
                )
            }
            .buttonStyle(.plain)

            Text(String(localized: "settings.prompt.hint"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
        }
        .sheet(isPresented: $showingPromptEditor) {
            SystemPromptEditorView(customPrompt: $customSystemPrompt)
        }
    }

    // MARK: - MCP Section (Smart Features)

    private var mcpSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: String(localized: "settings.tools.section"), icon: "puzzlepiece.extension", color: .orange)

            NavigationLink(destination: MCPServerListView()) {
                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.orange.opacity(0.1))
                            .frame(width: 44, height: 44)

                        Image(systemName: "calendar.badge.clock")
                            .font(.system(size: 20))
                            .foregroundStyle(.orange)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(localized: "settings.mcp.servers"))
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.primary)

                        Text(String(localized: "settings.mcp.servers.description"))
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    HStack(spacing: 8) {
                        Text("\(appState.enabledMCPServers.count)" + String(localized: "settings.mcp.enabled.count.suffix", defaultValue: " enabled"))
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.secondary)

                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color(.secondarySystemBackground))
                )
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - About Section

    @State private var showingAbout = false
    @State private var feedbackOptIn = FeedbackManager.shared.isOptedIn

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: String(localized: "settings.about.section"), icon: "info.circle", color: .blue)

            VStack(spacing: 0) {
                AboutRow(title: String(localized: "settings.version"), value: "1.0.0", icon: "number")

                Divider()
                    .padding(.leading, 52)

                // About app link
                Button(action: { showingAbout = true }) {
                    HStack(spacing: 12) {
                        Image(systemName: "info.circle")
                            .font(.system(size: 16))
                            .foregroundStyle(.secondary)
                            .frame(width: 28)

                        Text(String(localized: "settings.about.app"))
                            .font(.system(size: 15))
                            .foregroundStyle(.primary)

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                }

                Divider()
                    .padding(.leading, 52)

                AboutLinkRow(title: String(localized: "settings.about.mcp"), icon: "link", url: "https://modelcontextprotocol.io")
            }
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.secondarySystemBackground))
            )
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .sheet(isPresented: $showingAbout) {
            AboutView()
        }
    }

    // MARK: - Feedback Section

    private var feedbackSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: String(localized: "settings.feedback.section"), icon: "hand.thumbsup", color: .pink)

            VStack(spacing: 0) {
                Toggle(isOn: $feedbackOptIn) {
                    HStack(spacing: 12) {
                        Image(systemName: "chart.bar.xaxis")
                            .font(.system(size: 16))
                            .foregroundStyle(.secondary)
                            .frame(width: 28)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(String(localized: "settings.feedback.toggle"))
                                .font(.system(size: 15))
                                .foregroundStyle(.primary)
                        }
                    }
                }
                .toggleStyle(.switch)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .onChange(of: feedbackOptIn) { _, newValue in
                    FeedbackManager.shared.isOptedIn = newValue
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.chatInputBackgroundDynamic)
            )

            Text(String(localized: "settings.feedback.description"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
        }
    }

    // MARK: - Privacy Badge

    private var privacyBadge: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.15))
                    .frame(width: 44, height: 44)

                Image(systemName: "airplane")
                    .font(.system(size: 20))
                    .foregroundStyle(.green)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "settings.privacy.badge"))
                    .font(.system(size: 14, weight: .semibold))

                Text(String(localized: "settings.privacy.description"))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Checkmark indicating this is a feature
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 22))
                .foregroundStyle(.green)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.green.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.green.opacity(0.2), lineWidth: 1)
                )
        )
    }
}

// MARK: - Section Header

struct SectionHeader: View {
    let title: String
    let icon: String
    let color: Color

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(color)

            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.primary)
        }
        .padding(.leading, 4)
    }
}

// MARK: - Settings Model Card

struct SettingsModelCard: View {
    let model: ModelLoader.ModelInfo
    let isDownloaded: Bool
    let isLoaded: Bool
    let isRecommended: Bool
    let isTooHeavy: Bool
    let downloadProgress: Double?
    let loadingProgress: Double?
    let onDownload: () -> Void
    let onLoad: () -> Void
    let onDelete: () -> Void

    @State private var showingDeleteAlert = false
    @State private var showingSettings = false

    // Category-based colors
    private var categoryColors: [Color] {
        switch model.category {
        case .recommended: return [.orange.opacity(0.15), .yellow.opacity(0.15)]
        case .japanese: return [.red.opacity(0.15), .pink.opacity(0.15)]
        case .vision: return [.blue.opacity(0.15), .cyan.opacity(0.15)]
        case .efficient: return [.green.opacity(0.15), .mint.opacity(0.15)]
        case .others: return [.purple.opacity(0.15), .indigo.opacity(0.15)]
        }
    }

    private var categoryGradient: [Color] {
        switch model.category {
        case .recommended: return [.orange, .yellow]
        case .japanese: return [.red, .pink]
        case .vision: return [.blue, .cyan]
        case .efficient: return [.green, .mint]
        case .others: return [.purple, .indigo]
        }
    }

    private var categoryIcon: String {
        switch model.category {
        case .recommended: return "star.fill"
        case .japanese: return "character.ja"
        case .vision: return "camera.fill"
        case .efficient: return "bolt.fill"
        case .others: return "cube.fill"
        }
    }

    // Model logo image name (if available)
    private var modelLogo: String? {
        let name = model.name.lowercased()
        if name.contains("qwen") { return "qwen-logo" }
        if name.contains("llama") { return "meta-logo" }
        if name.contains("deepseek") { return "deepseek-logo" }
        if name.contains("gemma") { return "google-logo" }
        if name.contains("phi") { return "microsoft-logo" }
        if name.contains("smolvlm") || name.contains("smol") { return "huggingface-logo" }
        if name.contains("rakuten") { return "rakuten-logo" }
        if name.contains("swallow") || name.contains("tinyswallow") { return "tokyotech-logo" }
        if name.contains("stablelm") || name.contains("japanese-stablelm") { return "stability-logo" }
        if name.contains("lfm") || name.contains("liquid") { return "liquid-logo" }
        return nil
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                // Model icon - logo or category icon
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.linearGradient(
                            colors: categoryColors,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                        .frame(width: 44, height: 44)

                    if let logo = modelLogo, let uiImage = UIImage(named: logo) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 28, height: 28)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    } else {
                        Image(systemName: categoryIcon)
                            .font(.system(size: 20))
                            .foregroundStyle(.linearGradient(
                                colors: categoryGradient,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ))
                    }
                }

                // Model info - fixed layout
                VStack(alignment: .leading, spacing: 6) {
                    // Name row - single line with fixed layout
                    HStack(spacing: 6) {
                        Text(model.name)
                            .font(.system(size: 15, weight: .semibold))
                            .lineLimit(1)

                        // Status badge (only one shown)
                        if isLoaded {
                            StatusBadge(text: String(localized: "model.status.in.use"), color: .green)
                        } else if isDownloaded {
                            StatusBadge(text: String(localized: "model.downloaded"), color: .blue)
                        }

                        Spacer(minLength: 0)
                    }

                    // Description
                    Text(model.description)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                // Action button - fixed width
                actionButton
            }

            // Progress indicators
            if let progress = downloadProgress {
                VStack(spacing: 4) {
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                        .tint(.purple)

                    Text(String(format: NSLocalizedString("model.status.downloading", comment: ""), Int(progress * 100)))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }

            if let progress = loadingProgress, isDownloaded && !isLoaded {
                VStack(spacing: 4) {
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                        .tint(.blue)

                    Text(String(format: NSLocalizedString("model.status.loading", comment: ""), Int(progress * 100)))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(isLoaded ? Color.green.opacity(0.3) : Color.clear, lineWidth: 2)
        )
        .alert(String(localized: "model.delete.confirm.title"), isPresented: $showingDeleteAlert) {
            Button(String(localized: "common.cancel"), role: .cancel) {}
            Button(String(localized: "common.delete"), role: .destructive) { onDelete() }
        } message: {
            Text(String(localized: "model.delete.confirm.message", defaultValue: "\(model.name) を削除しますか？再度使用するにはダウンロードが必要です。"))
        }
        .sheet(isPresented: $showingSettings) {
            ModelSettingsView(modelId: model.id, modelName: model.name)
        }
    }

    @ViewBuilder
    private var actionButton: some View {
        if downloadProgress != nil {
            ProgressView()
                .scaleEffect(0.8)
                .frame(width: 80)
        } else if isDownloaded {
            HStack(spacing: 6) {
                if !isLoaded {
                    Button(action: onLoad) {
                        Text(String(localized: "model.action.load"))
                            .font(.system(size: 13, weight: .semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(.linearGradient(
                                colors: [.purple, .blue],
                                startPoint: .leading,
                                endPoint: .trailing
                            ))
                            .foregroundStyle(.white)
                            .clipShape(Capsule())
                    }
                }

                Menu {
                    Button {
                        showingSettings = true
                    } label: {
                        Label(String(localized: "model.action.settings"), systemImage: "slider.horizontal.3")
                    }

                    Divider()

                    Button(role: .destructive) {
                        showingDeleteAlert = true
                    } label: {
                        Label(String(localized: "model.action.delete"), systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(.tertiary)
                }
            }
        } else {
            VStack(alignment: .trailing, spacing: 4) {
                Button(action: onDownload) {
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.system(size: 14))
                        Text(model.size)
                    }
                    .font(.system(size: 12, weight: .medium))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Color(.tertiarySystemBackground))
                    .foregroundStyle(.primary)
                    .clipShape(Capsule())
                }

                // Recommended device badge
                HStack(spacing: 2) {
                    Image(systemName: "iphone")
                        .font(.system(size: 9))
                    Text(model.recommendedDeviceName)
                }
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Status Badge

struct StatusBadge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.system(size: 9, weight: .semibold))
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }
}

// MARK: - About Rows

struct AboutRow: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(.secondary)
                .frame(width: 28)

            Text(title)
                .font(.system(size: 15))

            Spacer()

            Text(value)
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}

struct AboutLinkRow: View {
    let title: String
    let icon: String
    let url: String

    var body: some View {
        Link(destination: URL(string: url)!) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
                    .frame(width: 28)

                Text(title)
                    .font(.system(size: 15))
                    .foregroundStyle(.primary)

                Spacer()

                Image(systemName: "arrow.up.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
    }
}

// MARK: - System Prompt Editor View

struct SystemPromptEditorView: View {
    @Binding var customPrompt: String
    @Environment(\.dismiss) private var dismiss
    @State private var editingPrompt: String = ""
    @State private var showingResetAlert = false

    private var isJapanese: Bool {
        Locale.current.language.languageCode?.identifier == "ja"
    }

    private var defaultPromptPreview: String {
        if isJapanese {
            return """
            # 絶対ルール：知らないことは「知らない」と言う
            **これは最も重要なルールです。**
            - 知らないこと、自信がないことは絶対に推測や創作で答えない
            - 「分かりません」「知りません」と正直に言う
            - 嘘や作り話は絶対にしない
            """
        } else {
            return """
            # Absolute Rule: Say "I don't know" when you don't know
            **This is the most important rule.**
            - Never guess or make up answers
            - Say "I don't know" honestly
            - Never lie or fabricate
            """
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.chatBackgroundDynamic
                    .ignoresSafeArea()

                VStack(spacing: 16) {
                    // Instructions
                    Text(String(localized: "settings.prompt.editor.instruction"))
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)

                    // Text Editor
                    TextEditor(text: $editingPrompt)
                        .font(.system(size: 14, design: .monospaced))
                        .scrollContentBackground(.hidden)
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.chatInputBackgroundDynamic)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.chatBorderDynamic, lineWidth: 1)
                        )
                        .padding(.horizontal, 20)

                    // Default prompt preview
                    VStack(alignment: .leading, spacing: 8) {
                        Text(String(localized: "settings.prompt.default.preview"))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)

                        Text(defaultPromptPreview)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .lineLimit(6)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)

                    Spacer()
                }
                .padding(.top, 16)
            }
            .navigationTitle(String(localized: "settings.prompt.editor.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "common.cancel")) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button(String(localized: "common.save")) {
                        customPrompt = editingPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
                        dismiss()
                    }
                }
                ToolbarItem(placement: .bottomBar) {
                    Button(action: { showingResetAlert = true }) {
                        Label(String(localized: "settings.prompt.reset"), systemImage: "arrow.counterclockwise")
                    }
                    .disabled(editingPrompt.isEmpty)
                }
            }
            .alert(String(localized: "settings.prompt.reset.title"), isPresented: $showingResetAlert) {
                Button(String(localized: "settings.prompt.reset"), role: .destructive) {
                    editingPrompt = ""
                }
                Button(String(localized: "common.cancel"), role: .cancel) {}
            } message: {
                Text(String(localized: "settings.prompt.reset.message"))
            }
        }
        .onAppear {
            editingPrompt = customPrompt
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(AppState())
        .environmentObject(ThemeManager())
}
