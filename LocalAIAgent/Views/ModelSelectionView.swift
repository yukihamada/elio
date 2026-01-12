import SwiftUI

struct ModelSelectionView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var modelLoader = ModelLoader()
    @Environment(\.dismiss) private var dismiss

    @State private var selectedModelId: String?
    @State private var isDownloading = false
    @State private var downloadError: String?
    @State private var currentDownloadProgress: Double = 0
    @State private var downloadingModelId: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                headerView

                ScrollView {
                    VStack(spacing: 16) {
                        ForEach(modelLoader.availableModels) { model in
                            ModelCard(
                                model: model,
                                isSelected: selectedModelId == model.id,
                                isDownloaded: modelLoader.isModelDownloaded(model.id),
                                downloadProgress: downloadingModelId == model.id ? currentDownloadProgress : nil,
                                onSelect: {
                                    selectedModelId = model.id
                                }
                            )
                        }
                    }
                    .padding()
                }

                actionButton
            }
            .navigationTitle("モデルを選択")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("キャンセル") {
                        dismiss()
                    }
                }
            }
            .alert("エラー", isPresented: .init(
                get: { downloadError != nil },
                set: { if !$0 { downloadError = nil } }
            )) {
                Button("OK") {}
            } message: {
                Text(downloadError ?? "")
            }
        }
    }

    private var headerView: some View {
        VStack(spacing: 8) {
            Image(systemName: "cpu")
                .font(.system(size: 40))
                .foregroundStyle(Color.accentColor)

            Text("AIモデルを選択")
                .font(.title2)
                .fontWeight(.semibold)

            Text("モデルはデバイス上でローカル実行されます")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 24)
    }

    private var actionButton: some View {
        VStack(spacing: 12) {
            if let selectedModelId = selectedModelId,
               let selectedModel = modelLoader.availableModels.first(where: { $0.id == selectedModelId }) {

                // Show selected model name
                HStack {
                    Text("選択中:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(selectedModel.name)
                        .font(.subheadline.weight(.medium))
                    Spacer()
                }
                .padding(.horizontal, 4)

                if modelLoader.isModelDownloaded(selectedModelId) {
                    // Load button - more prominent
                    Button(action: loadSelectedModel) {
                        HStack(spacing: 12) {
                            if appState.isLoading {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Image(systemName: "play.circle.fill")
                                    .font(.title2)
                                Text("モデルをロード")
                                    .font(.headline)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            LinearGradient(
                                colors: [.green, .green.opacity(0.8)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .shadow(color: .green.opacity(0.3), radius: 8, y: 4)
                    }
                    .disabled(appState.isLoading)
                } else {
                    // Download button
                    Button(action: downloadSelectedModel) {
                        HStack(spacing: 12) {
                            if isDownloading {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Image(systemName: "arrow.down.circle.fill")
                                    .font(.title2)
                                Text("ダウンロード (\(selectedModel.size))")
                                    .font(.headline)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.accentColor)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .disabled(isDownloading)
                }
            } else {
                Text("モデルを選択してください")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color(.secondarySystemBackground))
                    .foregroundStyle(.secondary)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
        }
        .padding()
        .background(.bar)
    }

    private func downloadSelectedModel() {
        guard let modelId = selectedModelId,
              let model = modelLoader.availableModels.first(where: { $0.id == modelId }) else {
            return
        }

        isDownloading = true
        downloadingModelId = modelId
        currentDownloadProgress = 0

        // Start progress monitoring task
        let progressTask = Task {
            while !Task.isCancelled {
                if let progress = modelLoader.downloadProgress[modelId] {
                    await MainActor.run {
                        currentDownloadProgress = progress
                    }
                }
                try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 second
            }
        }

        Task {
            do {
                try await modelLoader.downloadModel(model)
            } catch {
                downloadError = error.localizedDescription
            }
            progressTask.cancel()
            isDownloading = false
            downloadingModelId = nil
            currentDownloadProgress = 0
        }
    }

    private func loadSelectedModel() {
        guard let modelId = selectedModelId else { return }

        Task {
            do {
                try await appState.loadModel(named: modelId)
                dismiss()
            } catch {
                downloadError = error.localizedDescription
            }
        }
    }
}

struct ModelCard: View {
    let model: ModelLoader.ModelInfo
    let isSelected: Bool
    let isDownloaded: Bool
    let downloadProgress: Double?
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        // Full model name - no truncation
                        Text(model.name)
                            .font(.headline)
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)

                        HStack(spacing: 8) {
                            Text(model.size)
                            Text("•")
                            HStack(spacing: 2) {
                                Image(systemName: "iphone")
                                    .font(.system(size: 10))
                                Text(model.recommendedDeviceName)
                            }
                            if model.supportsVision {
                                Text("•")
                                HStack(spacing: 2) {
                                    Image(systemName: "camera")
                                        .font(.system(size: 10))
                                    Text("画像対応")
                                }
                                .foregroundStyle(.purple)
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 4) {
                        // Selection indicator
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .font(.title2)
                            .foregroundStyle(isSelected ? Color.accentColor : Color.secondary.opacity(0.5))

                        if isDownloaded {
                            HStack(spacing: 2) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 10))
                                Text("DL済")
                            }
                            .font(.caption2)
                            .foregroundStyle(.green)
                        }
                    }
                }

                Text(model.description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                if let progress = downloadProgress {
                    VStack(alignment: .leading, spacing: 4) {
                        ProgressView(value: progress)
                            .progressViewStyle(.linear)
                            .tint(.accentColor)

                        Text("ダウンロード中... \(Int(progress * 100))%")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                // Show context length in readable format
                HStack(spacing: 16) {
                    let contextK = model.config.maxContextLength / 1000
                    Label("\(contextK)Kコンテキスト", systemImage: "text.quote")
                    Label("4-bit量子化", systemImage: "square.stack.3d.up")
                }
                .font(.caption)
                .foregroundStyle(.tertiary)
            }
            .padding()
            .background(isSelected ? Color.accentColor.opacity(0.08) : Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    ModelSelectionView()
        .environmentObject(AppState())
}
