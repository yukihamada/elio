import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var themeManager: ThemeManager
    @StateObject private var modelLoader = ModelLoader()
    @Environment(\.dismiss) private var dismiss
    @State private var loadingModelId: String?
    @State private var showMoreModels = false

    // Models filtered and categorized based on device capability
    private var recommendedModels: [ModelLoader.ModelInfo] {
        modelLoader.availableModels.filter { model in
            !model.isTooHeavy(for: modelLoader.deviceTier) &&
            model.isRecommended(for: modelLoader.deviceTier)
        }
    }

    private var otherModels: [ModelLoader.ModelInfo] {
        modelLoader.availableModels.filter { model in
            !model.isTooHeavy(for: modelLoader.deviceTier) &&
            !model.isRecommended(for: modelLoader.deviceTier)
        }
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

                        // MCP Server Section
                        mcpSection

                        // About Section
                        aboutSection

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
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionHeader(title: String(localized: "settings.model.section"), icon: "brain.head.profile", color: .purple)

                Spacer()

                // Device tier indicator
                Text(String(localized: "settings.model.recommended", defaultValue: "推奨: \(modelLoader.deviceTier.recommendedModelSize)"))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 10) {
                // Recommended models (always shown)
                ForEach(recommendedModels) { model in
                    modelCard(for: model)
                }

                // Show More button (if there are other models)
                if !otherModels.isEmpty {
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
                                 : String(format: NSLocalizedString("settings.model.show.more", comment: ""), otherModels.count))
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

                    // Other models (collapsible)
                    if showMoreModels {
                        ForEach(otherModels) { model in
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

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                // Model icon
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.linearGradient(
                            colors: isRecommended
                                ? [.green.opacity(0.15), .mint.opacity(0.15)]
                                : [.purple.opacity(0.15), .blue.opacity(0.15)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                        .frame(width: 44, height: 44)

                    Image(systemName: isRecommended ? "star.fill" : "cube.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.linearGradient(
                            colors: isRecommended
                                ? [.green, .mint]
                                : [.purple, .blue],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
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
                        } else if isRecommended {
                            StatusBadge(text: String(localized: "model.status.recommended"), color: .orange)
                        }

                        Spacer(minLength: 0)
                    }

                    // Description with Vision badge inline
                    HStack(spacing: 4) {
                        if model.supportsVision {
                            Image(systemName: "camera.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(.blue)
                        }
                        Text(model.description)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
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

#Preview {
    SettingsView()
        .environmentObject(AppState())
        .environmentObject(ThemeManager())
}
