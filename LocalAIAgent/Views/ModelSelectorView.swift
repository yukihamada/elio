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
        case .teai:
            return [
                ModelInfo(
                    id: "teai/auto",
                    name: "teai Auto",
                    description: "用途に応じて最適モデルを自動選択",
                    inputCost: 0,
                    outputCost: 0
                ),
                ModelInfo(
                    id: "anthropic/claude-sonnet-5",
                    name: "Claude Sonnet 5",
                    description: "Anthropic最新の高性能モデル",
                    inputCost: 3,
                    outputCost: 15
                ),
                ModelInfo(
                    id: "anthropic/claude-opus-4.8",
                    name: "Claude Opus 4.8",
                    description: "最高性能モデル",
                    inputCost: 15,
                    outputCost: 75
                ),
                ModelInfo(
                    id: "openai/gpt-5.5",
                    name: "GPT-5.5",
                    description: "OpenAI最新モデル",
                    inputCost: 5,
                    outputCost: 15
                ),
                ModelInfo(
                    id: "google/gemini-3.5-flash",
                    name: "Gemini 3.5 Flash",
                    description: "Google製・高速モデル",
                    inputCost: 0.3,
                    outputCost: 1.2
                ),
                ModelInfo(
                    id: "deepseek/deepseek-v4-flash",
                    name: "DeepSeek V4 Flash",
                    description: "低コスト高性能モデル",
                    inputCost: 0.3,
                    outputCost: 0.9
                ),
                ModelInfo(
                    id: "qwen/qwen3.8-max",
                    name: "Qwen 3.8 Max",
                    description: "Alibaba製オープンモデル",
                    inputCost: 1,
                    outputCost: 3
                ),
                ModelInfo(
                    id: "moonshotai/kimi-k3",
                    name: "Kimi K3",
                    description: "Moonshot AI製モデル",
                    inputCost: 1,
                    outputCost: 3
                ),
            ]
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
                    name: "Advanced",
                    description: "最新の高性能モデル（128K context）",
                    inputCost: 2.5,
                    outputCost: 10
                ),
                ModelInfo(
                    id: "gpt-4o-mini",
                    name: "Advanced Mini",
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
        case .openrouter:
            return [
                ModelInfo(
                    id: "anthropic/claude-3.5-sonnet",
                    name: "Claude 3.5 Sonnet",
                    description: "Anthropic経由（200K context）",
                    inputCost: 3,
                    outputCost: 15
                ),
                ModelInfo(
                    id: "openai/gpt-4o",
                    name: "Advanced",
                    description: "クラウドAI（128K context）",
                    inputCost: 2.5,
                    outputCost: 10
                ),
                ModelInfo(
                    id: "meta-llama/llama-3.3-70b-instruct",
                    name: "Llama 3.3 70B",
                    description: "Meta製オープンモデル",
                    inputCost: 0.4,
                    outputCost: 0.4
                ),
                ModelInfo(
                    id: "google/gemini-2.0-flash-001",
                    name: "Gemini 2.0 Flash",
                    description: "Google経由・高速",
                    inputCost: 0.1,
                    outputCost: 0.4
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
    ModelSelectorView(provider: .openai, selectedModel: $selectedModel)  // Internal API ID unchanged
}
