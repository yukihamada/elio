import SwiftUI

/// Model selector for each cloud provider
struct ModelSelectorView: View {
    let provider: CloudProvider
    @Binding var selectedModel: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            ZStack {
                Color.chatBackgroundDynamic
                    .ignoresSafeArea()

                List {
                    ForEach(availableModels, id: \.id) { model in
                        Button(action: {
                            selectedModel = model.id
                            dismiss()
                        }) {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(model.name)
                                        .font(.headline)
                                        .foregroundStyle(.primary)

                                    Text(model.description)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .multilineTextAlignment(.leading)

                                    // Cost display
                                    if model.inputCost > 0 || model.outputCost > 0 {
                                        HStack(spacing: 4) {
                                            Text("入力: $\(String(format: "%.2f", model.inputCost))/1M")
                                            Text("•")
                                            Text("出力: $\(String(format: "%.2f", model.outputCost))/1M")
                                        }
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                    } else {
                                        Text("無料")
                                            .font(.caption2)
                                            .foregroundStyle(.green)
                                    }
                                }

                                Spacer()

                                if selectedModel == model.id {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.blue)
                                }
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
            .navigationTitle("\(provider.displayName) Models")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var availableModels: [ModelInfo] {
        switch provider {
        case .openai:
            return [
                ModelInfo(
                    id: "gpt-4o",
                    name: "GPT-4o",
                    description: "最新の高性能モデル（128K context）",
                    inputCost: 2.5,
                    outputCost: 10
                ),
                ModelInfo(
                    id: "gpt-4o-mini",
                    name: "GPT-4o Mini",
                    description: "コスパ最強の高速モデル",
                    inputCost: 0.15,
                    outputCost: 0.6
                ),
                ModelInfo(
                    id: "o1",
                    name: "o1",
                    description: "推論特化の高性能モデル",
                    inputCost: 15,
                    outputCost: 60
                ),
                ModelInfo(
                    id: "o1-mini",
                    name: "o1 Mini",
                    description: "推論特化の効率モデル",
                    inputCost: 3,
                    outputCost: 12
                ),
            ]
        case .anthropic:
            return [
                ModelInfo(
                    id: "claude-sonnet-4-5",
                    name: "Claude Sonnet 4.5",
                    description: "最新の高性能モデル（200K context）",
                    inputCost: 3,
                    outputCost: 15
                ),
                ModelInfo(
                    id: "claude-3-5-sonnet-20241022",
                    name: "Claude 3.5 Sonnet",
                    description: "バランスの取れた高性能モデル",
                    inputCost: 3,
                    outputCost: 15
                ),
                ModelInfo(
                    id: "claude-3-5-haiku-20241022",
                    name: "Claude 3.5 Haiku",
                    description: "高速・安価なモデル",
                    inputCost: 0.8,
                    outputCost: 4
                ),
            ]
        case .google:
            return [
                ModelInfo(
                    id: "gemini-2.0-flash-exp",
                    name: "Gemini 2.0 Flash (Experimental)",
                    description: "実験版・無料（レート制限あり）",
                    inputCost: 0,
                    outputCost: 0
                ),
                ModelInfo(
                    id: "gemini-1.5-pro",
                    name: "Gemini 1.5 Pro",
                    description: "長文対応の高性能モデル（2M context）",
                    inputCost: 1.25,
                    outputCost: 5
                ),
                ModelInfo(
                    id: "gemini-1.5-flash",
                    name: "Gemini 1.5 Flash",
                    description: "高速で安価なモデル",
                    inputCost: 0.075,
                    outputCost: 0.3
                ),
            ]
        }
    }
}

/// Information about a specific model
struct ModelInfo {
    let id: String
    let name: String
    let description: String
    let inputCost: Double  // per 1M tokens (USD)
    let outputCost: Double
}

#Preview {
    @Previewable @State var selectedModel = "gpt-4o"
    ModelSelectorView(provider: .openai, selectedModel: $selectedModel)
}
