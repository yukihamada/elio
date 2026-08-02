import SwiftUI

/// Simple, clean model picker for the ChatWeb (teai.io) backend.
/// Replaces the old inline menu-style Picker in SettingsView with a proper
/// full-screen list (same visual pattern as ModelSelectorView for direct API keys).
struct ChatWebModelSelectorView: View {
    @Binding var selectedModel: String  // "auto" or a ChatWebBackend.availableModels id
    let isPro: Bool
    let onSelectRequiresPro: () -> Void
    @Environment(\.dismiss) private var dismiss

    private struct Row: Identifiable {
        let id: String
        let displayName: String
        let description: String
        let requiresPro: Bool
    }

    /// Strips the "✦ Pro" suffix baked into ChatWebBackend.availableModels' name
    /// (kept there for older call sites) and pairs each model with a short description.
    private var rows: [Row] {
        ChatWebBackend.availableModels.map { model in
            let name = model.name.replacingOccurrences(of: " ✦ Pro", with: "")
            return Row(id: model.id, displayName: name, description: description(for: model.id), requiresPro: model.requiresPro)
        }
    }

    private func description(for id: String) -> String {
        switch id {
        case "auto": return "サーバーが自動で選ぶ標準モデル"
        case "moonshotai/kimi-k3": return "Kimi K3 — teai.io実モデル。率直な意見と迷いを隠さず話す"
        case "deepseek/deepseek-v4-flash": return "DeepSeek V4-Flash — teai.io実モデル。簡潔で率直"
        case "claude-sonnet-5": return "Claude Sonnet 5 — teai.io実モデル。丁寧で不確かさを正直に言う"
        default: return "teai.io経由のモデル"
        }
    }

    var body: some View {
        NavigationView {
            List {
                Section {
                    ForEach(rows.filter { !$0.requiresPro }) { row in
                        modelRow(row)
                    }
                }
                Section {
                    ForEach(rows.filter { $0.requiresPro }) { row in
                        modelRow(row)
                    }
                } header: {
                    Text("AIモデル本人と話す")
                } footer: {
                    Text("番組「AIに、本音を。」と同じ実モデルです。Pro限定。")
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("モデル")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("閉じる") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private func modelRow(_ row: Row) -> some View {
        Button(action: {
            if row.requiresPro && !isPro {
                onSelectRequiresPro()
            } else {
                selectedModel = row.id
                dismiss()
            }
        }) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(row.displayName)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.primary)
                        if row.requiresPro {
                            Text("PRO")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.indigo))
                        }
                    }
                    Text(row.description)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if selectedModel == row.id {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.indigo)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
