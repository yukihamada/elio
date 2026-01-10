import SwiftUI

struct ModelSelectionView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var modelLoader = ModelLoader()
    @Environment(\.dismiss) private var dismiss

    @State private var selectedModelId: String?
    @State private var isDownloading = false
    @State private var downloadError: String?

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
                                downloadProgress: modelLoader.downloadProgress[model.id],
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
        VStack(spacing: 8) {
            if let selectedModelId = selectedModelId {
                if modelLoader.isModelDownloaded(selectedModelId) {
                    Button(action: loadSelectedModel) {
                        HStack {
                            if appState.isLoading {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Text("このモデルを使用")
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.accentColor)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .disabled(appState.isLoading)
                } else {
                    Button(action: downloadSelectedModel) {
                        HStack {
                            if isDownloading {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Image(systemName: "arrow.down.circle")
                                Text("ダウンロード")
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.accentColor)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .disabled(isDownloading)
                }
            } else {
                Text("モデルを選択してください")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .foregroundStyle(.secondary)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
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

        Task {
            do {
                try await modelLoader.downloadModel(model)
            } catch {
                downloadError = error.localizedDescription
            }
            isDownloading = false
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
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(model.name)
                            .font(.headline)
                            .foregroundStyle(.primary)

                        Text(model.size)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    HStack(spacing: 8) {
                        if isDownloaded {
                            Label("ダウンロード済み", systemImage: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.green)
                        }

                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    }
                }

                Text(model.description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)

                if let progress = downloadProgress {
                    VStack(alignment: .leading, spacing: 4) {
                        ProgressView(value: progress)
                            .progressViewStyle(.linear)

                        Text("ダウンロード中... \(Int(progress * 100))%")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                HStack(spacing: 16) {
                    Label("\(model.config.maxContextLength)", systemImage: "text.quote")
                    Label("4-bit量子化", systemImage: "square.stack.3d.up")
                }
                .font(.caption)
                .foregroundStyle(.tertiary)
            }
            .padding()
            .background(Color(.secondarySystemBackground))
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
