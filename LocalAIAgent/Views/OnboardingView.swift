import SwiftUI

struct OnboardingView: View {
    @Binding var hasCompletedOnboarding: Bool
    @EnvironmentObject var appState: AppState
    @State private var currentPage = 0
    @State private var isDownloading = false
    @State private var downloadProgress: Double = 0
    @State private var downloadError: String?
    @State private var downloadCompleted = false
    @Environment(\.dismiss) private var dismiss
    @StateObject private var modelLoader = ModelLoader()

    // Get recommended model based on device spec
    private var recommendedModel: ModelLoader.ModelInfo? {
        let deviceTier = DeviceTier.current
        // For high/ultra devices: Qwen3 4B, for medium/low: Qwen3 1.7B
        switch deviceTier {
        case .ultra, .high:
            return modelLoader.availableModels.first { $0.id == "qwen3-4b" }
        case .medium:
            return modelLoader.availableModels.first { $0.id == "qwen3-1.7b" }
        case .low:
            return modelLoader.availableModels.first { $0.id == "qwen3-0.6b" }
        }
    }

    var body: some View {
        ZStack {
            Color.chatBackgroundDynamic
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Skip button
                HStack {
                    Spacer()
                    Button("スキップ") {
                        completeOnboarding()
                    }
                    .foregroundStyle(.secondary)
                    .padding(.trailing, 20)
                    .padding(.top, 16)
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
                .tabViewStyle(.page(indexDisplayMode: .always))

                // Bottom buttons
                VStack(spacing: 16) {
                    if currentPage < 3 {
                        Button(action: { withAnimation { currentPage += 1 } }) {
                            Text("次へ")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(Color.accentColor)
                                .foregroundColor(.white)
                                .cornerRadius(12)
                        }
                    } else {
                        // Last page - download or complete
                        if downloadCompleted {
                            Button(action: { completeOnboarding() }) {
                                Text("始める")
                                    .font(.headline)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 16)
                                    .background(Color.accentColor)
                                    .foregroundColor(.white)
                                    .cornerRadius(12)
                            }
                        } else if isDownloading {
                            Button(action: {}) {
                                HStack {
                                    ProgressView()
                                        .tint(.white)
                                    Text("ダウンロード中...")
                                        .font(.headline)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(Color.gray)
                                .foregroundColor(.white)
                                .cornerRadius(12)
                            }
                            .disabled(true)
                        } else {
                            Button(action: { startModelDownload() }) {
                                HStack {
                                    Image(systemName: "arrow.down.circle.fill")
                                    Text("ダウンロード開始")
                                        .font(.headline)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(Color.cyan)
                                .foregroundColor(.white)
                                .cornerRadius(12)
                            }

                            Button(action: { completeOnboarding() }) {
                                Text("後でダウンロード")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
            }
        }
    }

    private var welcomePage: some View {
        VStack(spacing: 24) {
            Spacer()

            // Gradient brain icon
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.purple.opacity(0.3), .blue.opacity(0.2)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 120, height: 120)

                Image(systemName: "brain.head.profile")
                    .font(.system(size: 60))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.purple, .blue],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }

            Text(String(localized: "onboarding.welcome.title"))
                .font(.system(size: 32, weight: .bold))
                .multilineTextAlignment(.center)

            Text(String(localized: "onboarding.welcome.subtitle"))
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            // Airplane mode badge
            HStack(spacing: 8) {
                Image(systemName: "airplane")
                    .foregroundStyle(.green)
                Text("機内モードでも動作")
                    .font(.subheadline.weight(.medium))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color.green.opacity(0.15))
            .cornerRadius(20)

            Spacer()
            Spacer()
        }
        .padding(.horizontal, 32)
    }

    private var featuresPage: some View {
        VStack(spacing: 32) {
            Spacer()

            Text(String(localized: "onboarding.features.title"))
                .font(.system(size: 24, weight: .bold))

            VStack(alignment: .leading, spacing: 20) {
                FeatureRow(
                    icon: "airplane",
                    iconColor: .green,
                    title: String(localized: "onboarding.feature.offline"),
                    description: String(localized: "onboarding.feature.offline.desc")
                )
                FeatureRow(
                    icon: "lock.shield.fill",
                    iconColor: .blue,
                    title: String(localized: "onboarding.feature.privacy"),
                    description: String(localized: "onboarding.feature.privacy.desc")
                )
                FeatureRow(
                    icon: "calendar.badge.clock",
                    iconColor: .orange,
                    title: String(localized: "onboarding.feature.vault"),
                    description: String(localized: "onboarding.feature.vault.desc")
                )
                FeatureRow(
                    icon: "briefcase.fill",
                    iconColor: .purple,
                    title: String(localized: "onboarding.feature.secure"),
                    description: String(localized: "onboarding.feature.secure.desc")
                )
            }

            Spacer()
            Spacer()
        }
        .padding(.horizontal, 32)
    }

    private var privacyPage: some View {
        VStack(spacing: 24) {
            Spacer()

            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.15))
                    .frame(width: 100, height: 100)

                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 50))
                    .foregroundStyle(.green)
            }

            Text(String(localized: "onboarding.privacy.title"))
                .font(.system(size: 24, weight: .bold))
                .multilineTextAlignment(.center)

            VStack(alignment: .leading, spacing: 16) {
                PrivacyItem(icon: "iphone", text: String(localized: "onboarding.privacy.item1"))
                PrivacyItem(icon: "xmark.icloud.fill", text: String(localized: "onboarding.privacy.item2"))
                PrivacyItem(icon: "brain.head.profile", text: String(localized: "onboarding.privacy.item3"))
            }
            .padding(.horizontal, 16)

            Spacer()
            Spacer()
        }
        .padding(.horizontal, 32)
    }

    private var getStartedPage: some View {
        VStack(spacing: 24) {
            Spacer()

            if let model = recommendedModel {
                // Model download section
                ZStack {
                    Circle()
                        .fill(downloadCompleted ? Color.green.opacity(0.15) : Color.cyan.opacity(0.15))
                        .frame(width: 100, height: 100)

                    if isDownloading {
                        CircularProgressView(progress: downloadProgress)
                            .frame(width: 80, height: 80)
                    } else if downloadCompleted {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 50))
                            .foregroundStyle(.green)
                    } else {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.system(size: 50))
                            .foregroundStyle(.cyan)
                    }
                }

                Text(downloadCompleted ? "準備完了！" : "AIモデルをダウンロード")
                    .font(.system(size: 24, weight: .bold))

                // Device tier info
                HStack(spacing: 8) {
                    Image(systemName: "iphone")
                        .foregroundStyle(.secondary)
                    Text("お使いのデバイス: \(DeviceTier.current.displayName)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                // Recommended model card
                VStack(spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(model.name)
                                    .font(.headline)
                                Text("おすすめ")
                                    .font(.caption)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 2)
                                    .background(Color.green.opacity(0.2))
                                    .foregroundStyle(.green)
                                    .cornerRadius(8)
                            }
                            Text(model.description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(model.size)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if isDownloading {
                        VStack(spacing: 8) {
                            ProgressView(value: downloadProgress)
                                .tint(.cyan)
                            Text("\(Int(downloadProgress * 100))% ダウンロード中...")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if let error = downloadError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
                .padding(16)
                .background(Color(.systemGray6))
                .cornerRadius(12)

                if !downloadCompleted && !isDownloading {
                    Text("AIを使うにはモデルのダウンロードが必要です")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            } else {
                // Fallback if no model found
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
            }

            Spacer()
            Spacer()
        }
        .padding(.horizontal, 32)
    }

    private func startModelDownload() {
        guard let model = recommendedModel else { return }

        isDownloading = true
        downloadError = nil

        Task {
            do {
                // Monitor download progress
                let progressTask = Task { @MainActor in
                    while !Task.isCancelled {
                        if let progress = modelLoader.downloadProgress[model.id] {
                            self.downloadProgress = progress
                        }
                        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1s
                    }
                }

                try await modelLoader.downloadModel(model)
                progressTask.cancel()

                await MainActor.run {
                    downloadProgress = 1.0
                    isDownloading = false
                    downloadCompleted = true
                }
            } catch {
                await MainActor.run {
                    isDownloading = false
                    downloadError = "ダウンロードに失敗しました: \(error.localizedDescription)"
                }
            }
        }
    }

    private func completeOnboarding() {
        hasCompletedOnboarding = true
        dismiss()
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

#Preview {
    OnboardingView(hasCompletedOnboarding: .constant(false))
        .environmentObject(AppState())
}
