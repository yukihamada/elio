import SwiftUI

/// View to download vision-capable models when user tries to attach an image
struct VisionModelDownloadView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject private var modelLoader = ModelLoader.shared
    @Environment(\.dismiss) private var dismiss

    @State private var isDownloading = false
    @State private var downloadComplete = false
    @State private var showDownloadConfirmation = false  // App Store 4.2.3 compliance
    @State private var modelToDownload: ModelLoader.ModelInfo?  // Model pending confirmation

    private var deviceTier: DeviceTier {
        modelLoader.deviceTier
    }

    private var visionModels: [ModelLoader.ModelInfo] {
        modelLoader.availableModels.filter {
            $0.supportsVision && !$0.isTooHeavy(for: deviceTier)
        }
    }

    private var recommendedModel: ModelLoader.ModelInfo? {
        modelLoader.getRecommendedVisionModel(for: deviceTier)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.chatBackgroundDynamic
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {
                        // Header
                        headerView

                        // Device info
                        deviceInfoBadge

                        // Recommended model
                        if let recommended = recommendedModel {
                            recommendedModelCard(recommended)
                        }

                        // Other vision models
                        if visionModels.count > 1 {
                            otherModelsSection
                        }

                        // Download complete message
                        if downloadComplete {
                            downloadCompleteView
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle(String(localized: "vision.model.download.title"))
            #if !targetEnvironment(macCatalyst)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(String(localized: "common.close")) {
                        dismiss()
                    }
                }
            }
            // App Store Guideline 4.2.3: Explicit download confirmation with size disclosure
            .alert("モデルをダウンロード", isPresented: $showDownloadConfirmation) {
                Button("ダウンロード開始", role: nil) {
                    if let model = modelToDownload {
                        downloadModel(model)
                    }
                }
                Button("キャンセル", role: .cancel) {
                    modelToDownload = nil
                }
            } message: {
                if let model = modelToDownload {
                    Text("\(model.name)（\(model.size)）をダウンロードします。\n\nWi-Fi環境でのダウンロードを推奨します。\n\n今すぐダウンロードしますか？")
                } else {
                    Text("モデルをダウンロードしますか？")
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
                        colors: [.blue.opacity(0.2), .cyan.opacity(0.2)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .frame(width: 80, height: 80)

                Image(systemName: "camera.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(.linearGradient(
                        colors: [.blue, .cyan],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
            }

            VStack(spacing: 8) {
                Text(String(localized: "vision.model.required.header"))
                    .font(.system(size: 20, weight: .bold))

                Text(String(localized: "vision.model.required.description"))
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.top, 16)
    }

    // MARK: - Device Info Badge

    private var deviceInfoBadge: some View {
        HStack(spacing: 8) {
            Image(systemName: "cpu")
                .font(.system(size: 12))
            Text(deviceTier.displayName)
            Text("•")
            Text(String(localized: "vision.model.recommended.size \(deviceTier.recommendedModelSize)"))
        }
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(.tertiarySystemBackground))
        .clipShape(Capsule())
    }

    // MARK: - Recommended Model Card

    private func recommendedModelCard(_ model: ModelLoader.ModelInfo) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "star.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.orange)
                Text(String(localized: "vision.model.recommended"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    // Model icon
                    ZStack {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(.linearGradient(
                                colors: [.blue.opacity(0.15), .cyan.opacity(0.15)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ))
                            .frame(width: 52, height: 52)

                        Image(systemName: "camera.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(.blue)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(model.name)
                            .font(.system(size: 17, weight: .semibold))

                        Text(model.description)
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }

                    Spacer()
                }

                // Download button
                if modelLoader.isModelDownloaded(model.id) {
                    Button(action: {
                        loadModelAndDismiss(model)
                    }) {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                            Text(String(localized: "vision.model.use.this"))
                        }
                        .font(.system(size: 15, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.green)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                } else if let info = modelLoader.downloadProgressInfo[model.id] {
                    VStack(spacing: 8) {
                        ProgressView(value: info.progress)
                            .progressViewStyle(.linear)
                            .tint(.blue)
                        HStack {
                            Text("\(Int(info.progress * 100))%")
                            Spacer()
                            if info.speed > 0 {
                                Text(info.speedFormatted)
                            }
                            if let eta = info.etaFormatted {
                                Text(eta)
                            }
                        }
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    }
                } else {
                    Button(action: {
                        modelToDownload = model
                        showDownloadConfirmation = true
                    }) {
                        HStack {
                            Image(systemName: "arrow.down.circle.fill")
                            Text(String(localized: "vision.model.download.button \(model.size)"))
                        }
                        .font(.system(size: 15, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(.linearGradient(
                            colors: [.blue, .cyan],
                            startPoint: .leading,
                            endPoint: .trailing
                        ))
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .disabled(isDownloading)
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.secondarySystemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.blue.opacity(0.3), lineWidth: 2)
            )
        }
    }

    // MARK: - Other Models Section

    private var otherModelsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(String(localized: "vision.model.other.options"))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 4)

            ForEach(visionModels.filter { $0.id != recommendedModel?.id }) { model in
                otherModelRow(model)
            }
        }
    }

    private func otherModelRow(_ model: ModelLoader.ModelInfo) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.blue.opacity(0.1))
                    .frame(width: 44, height: 44)

                Image(systemName: "camera.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.blue)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(model.name)
                    .font(.system(size: 15, weight: .semibold))
                Text(model.description)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if modelLoader.isModelDownloaded(model.id) {
                Button(action: {
                    loadModelAndDismiss(model)
                }) {
                    Text(String(localized: "model.action.load"))
                        .font(.system(size: 13, weight: .semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Color.green)
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                }
            } else if let info = modelLoader.downloadProgressInfo[model.id] {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(Int(info.progress * 100))%")
                        .font(.system(size: 13, weight: .medium))
                    if info.speed > 0 {
                        Text(info.speedFormatted)
                            .font(.system(size: 10))
                    }
                }
                .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .trailing, spacing: 4) {
                    Button(action: {
                        modelToDownload = model
                        showDownloadConfirmation = true
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.down.circle.fill")
                                .font(.system(size: 12))
                            Text(model.size)
                        }
                        .font(.system(size: 12, weight: .medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(Color(.tertiarySystemBackground))
                        .foregroundStyle(.primary)
                        .clipShape(Capsule())
                    }
                    .disabled(isDownloading)

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
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemBackground))
        )
    }

    // MARK: - Download Complete View

    private var downloadCompleteView: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 24))
                .foregroundStyle(.green)

            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "vision.model.download.complete"))
                    .font(.system(size: 15, weight: .semibold))
                Text(String(localized: "vision.model.download.complete.message"))
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.green.opacity(0.1))
        )
    }

    // MARK: - Actions

    private func downloadModel(_ model: ModelLoader.ModelInfo) {
        isDownloading = true
        Task.detached {
            try? await modelLoader.downloadModel(model)
            await MainActor.run {
                isDownloading = false
                downloadComplete = true

                // Auto-load after download
                loadModelAndDismiss(model)
            }
        }
    }

    private func loadModelAndDismiss(_ model: ModelLoader.ModelInfo) {
        Task {
            do {
                try await appState.loadModel(named: model.id)
                dismiss()
            } catch {
                print("Failed to load model: \(error)")
            }
        }
    }
}

#Preview {
    VisionModelDownloadView()
        .environmentObject(AppState())
}
