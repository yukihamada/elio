import SwiftUI

/// Quick model/backend switcher shown from the header tap
/// Allows switching between chatweb.ai cloud and downloaded local models
struct ModelSwitcherView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var chatModeManager = ChatModeManager.shared
    @ObservedObject private var modelLoader = ModelLoader.shared

    @State private var isLoadingModel = false
    @State private var loadingModelId: String?

    private var downloadedModels: [(id: String, info: ModelLoader.ModelInfo?)] {
        let ids = modelLoader.getDownloadedModels()
        return ids.map { id in
            (id: id, info: modelLoader.getModelInfo(id))
        }.sorted { lhs, rhs in
            (lhs.info?.name ?? lhs.id) < (rhs.info?.name ?? rhs.id)
        }
    }

    var body: some View {
        NavigationView {
            ZStack {
                Color.chatBackgroundDynamic
                    .ignoresSafeArea()

                List {
                    // Cloud section
                    Section {
                        Button(action: selectChatWeb) {
                            HStack(spacing: 12) {
                                Image(systemName: "cloud.fill")
                                    .font(.system(size: 18))
                                    .foregroundStyle(.indigo)
                                    .frame(width: 32)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text("chatweb.ai")
                                        .font(.headline)
                                        .foregroundStyle(.primary)
                                    Text("Elio公式クラウドAI")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                if chatModeManager.isChatWebMode {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.indigo)
                                }
                            }
                        }
                    } header: {
                        Text("クラウド")
                    }

                    // Local models section
                    Section {
                        if downloadedModels.isEmpty {
                            HStack {
                                Image(systemName: "arrow.down.to.line")
                                    .foregroundStyle(.secondary)
                                Text("ダウンロード済みモデルなし")
                                    .foregroundStyle(.secondary)
                                    .font(.subheadline)
                            }
                        } else {
                            ForEach(downloadedModels, id: \.id) { model in
                                Button(action: { selectLocalModel(model.id) }) {
                                    HStack(spacing: 12) {
                                        Image(systemName: model.info?.supportsVision == true ? "eye.fill" : "cpu.fill")
                                            .font(.system(size: 18))
                                            .foregroundStyle(.green)
                                            .frame(width: 32)

                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(model.info?.name ?? model.id)
                                                .font(.headline)
                                                .foregroundStyle(.primary)

                                            HStack(spacing: 6) {
                                                if let info = model.info {
                                                    Text(info.size)
                                                    if info.supportsVision {
                                                        Text("•")
                                                        Text("Vision")
                                                            .foregroundStyle(.purple)
                                                    }
                                                }
                                            }
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        }

                                        Spacer()

                                        if isLoadingModel && loadingModelId == model.id {
                                            ProgressView()
                                        } else if appState.currentModelId == model.id && appState.isModelLoaded {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundStyle(.green)
                                        }
                                    }
                                }
                                .disabled(isLoadingModel)
                            }
                        }
                    } header: {
                        Text("ローカルモデル")
                    } footer: {
                        if !downloadedModels.isEmpty {
                            Text("設定からモデルの追加・削除ができます")
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
            .navigationTitle("モデル切り替え")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("閉じる") { dismiss() }
                }
            }
        }
    }

    private func selectChatWeb() {
        chatModeManager.setMode(.chatweb)
        dismiss()
    }

    private func selectLocalModel(_ modelId: String) {
        // Already loaded
        if appState.currentModelId == modelId && appState.isModelLoaded {
            chatModeManager.setMode(.local)
            dismiss()
            return
        }

        // Load the model
        isLoadingModel = true
        loadingModelId = modelId
        Task {
            do {
                try await appState.loadModel(named: modelId)
                chatModeManager.setMode(.local)
                dismiss()
            } catch {
                logError("ModelSwitcher", "Failed to load model \(modelId): \(error.localizedDescription)")
            }
            isLoadingModel = false
            loadingModelId = nil
        }
    }
}
