import SwiftUI

// MARK: - Skill Publish View

struct SkillPublishView: View {
    @StateObject private var manager = SkillMarketplaceManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var description = ""
    @State private var category: SkillCategory = .tools
    @State private var mcpConfigJSON = ""
    @State private var tagsText = ""
    @State private var priceTokens = 0
    @State private var showingJSONHelp = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.chatBackgroundDynamic
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        // Header icon
                        ZStack {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [.purple, .indigo],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 80, height: 80)
                                .shadow(color: .purple.opacity(0.3), radius: 12, y: 4)

                            Image(systemName: "puzzlepiece.extension.fill")
                                .font(.system(size: 32))
                                .foregroundStyle(.white)
                        }
                        .padding(.top, 20)

                        Text("スキルを公開")
                            .font(.system(size: 18, weight: .bold))

                        Text("あなたのMCPスキルを他のユーザーと共有できます。\n審査後にマーケットプレイスに掲載されます。")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 30)

                        // Form
                        VStack(alignment: .leading, spacing: 16) {
                            // Name
                            formField(label: "スキル名", placeholder: "例: 翻訳ヘルパー") {
                                TextField("例: 翻訳ヘルパー", text: $name)
                                    .textFieldStyle(.plain)
                                    .padding(12)
                                    .background(
                                        RoundedRectangle(cornerRadius: 10)
                                            .fill(Color(.tertiarySystemBackground))
                                    )
                            }

                            // Description
                            formField(label: "説明", placeholder: "スキルの機能を説明してください") {
                                TextField("スキルの機能を説明してください", text: $description, axis: .vertical)
                                    .textFieldStyle(.plain)
                                    .lineLimit(3...6)
                                    .padding(12)
                                    .background(
                                        RoundedRectangle(cornerRadius: 10)
                                            .fill(Color(.tertiarySystemBackground))
                                    )
                            }

                            // Category
                            formField(label: "カテゴリ") {
                                Picker("カテゴリ", selection: $category) {
                                    ForEach(SkillCategory.allCases, id: \.self) { cat in
                                        HStack(spacing: 6) {
                                            Image(systemName: cat.iconName)
                                            Text(cat.shortName)
                                        }
                                        .tag(cat)
                                    }
                                }
                                .pickerStyle(.menu)
                                .tint(.purple)
                                .padding(8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(Color(.tertiarySystemBackground))
                                )
                            }

                            // Tags
                            formField(label: "タグ (カンマ区切り)", placeholder: "翻訳, 言語, 英語") {
                                TextField("翻訳, 言語, 英語", text: $tagsText)
                                    .textFieldStyle(.plain)
                                    .padding(12)
                                    .background(
                                        RoundedRectangle(cornerRadius: 10)
                                            .fill(Color(.tertiarySystemBackground))
                                    )
                            }

                            // Price
                            formField(label: "価格 (トークン)") {
                                HStack(spacing: 12) {
                                    Stepper(value: $priceTokens, in: 0...1000, step: 10) {
                                        HStack(spacing: 4) {
                                            Image(systemName: "dollarsign.circle.fill")
                                                .foregroundStyle(.orange)
                                            Text("\(priceTokens)")
                                                .font(.system(size: 16, weight: .semibold))
                                        }
                                    }
                                }
                                .padding(8)
                                .background(
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(Color(.tertiarySystemBackground))
                                )
                            }

                            Text("0 = 無料で公開")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .padding(.leading, 4)

                            // MCP Config JSON
                            HStack {
                                formFieldLabel("MCP設定 (JSON)")
                                Spacer()
                                Button(action: { showingJSONHelp = true }) {
                                    Image(systemName: "questionmark.circle")
                                        .font(.system(size: 14))
                                        .foregroundStyle(.secondary)
                                }
                            }

                            TextEditor(text: $mcpConfigJSON)
                                .font(.system(size: 13, design: .monospaced))
                                .scrollContentBackground(.hidden)
                                .frame(minHeight: 200)
                                .padding(12)
                                .background(
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(Color(.tertiarySystemBackground))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(Color.subtleSeparator, lineWidth: 0.5)
                                )

                            // JSON template button
                            Button(action: { insertTemplate() }) {
                                HStack(spacing: 6) {
                                    Image(systemName: "doc.on.clipboard")
                                        .font(.system(size: 13))
                                    Text("テンプレートを挿入")
                                        .font(.system(size: 13, weight: .medium))
                                }
                                .foregroundStyle(.purple)
                            }
                        }
                        .padding(.horizontal, 20)

                        // Error
                        if let error = manager.error {
                            Text(error)
                                .font(.system(size: 13))
                                .foregroundStyle(.red)
                                .padding(.horizontal, 20)
                        }

                        // Submit button
                        Button(action: { submitSkill() }) {
                            if manager.isPublishing {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                HStack(spacing: 8) {
                                    Image(systemName: "paperplane.fill")
                                    Text("審査に提出")
                                        .font(.system(size: 16, weight: .semibold))
                                }
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            LinearGradient(
                                colors: [.purple, .indigo],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .padding(.horizontal, 20)
                        .disabled(!isFormValid || manager.isPublishing)
                        .opacity(isFormValid ? 1 : 0.6)

                        Spacer(minLength: 20)
                    }
                }
            }
            .navigationTitle("スキルを公開")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
            }
            .alert("MCP設定JSONについて", isPresented: $showingJSONHelp) {
                Button("OK") {}
            } message: {
                Text("""
                MCP設定JSONは、スキルが提供するサーバーとツールの定義です。

                必須フィールド:
                - server_id: 一意のサーバーID
                - server_name: 表示名
                - server_description: 説明
                - icon: SF Symbolsアイコン名
                - tools: ツール定義の配列

                各ツールには:
                - name, description
                - input_schema (JSON Schema)
                - action_type (httpRequest/shortcut/urlScheme/javascript)
                - action_config
                """)
            }
        }
    }

    // MARK: - Form Helpers

    private var isFormValid: Bool {
        !name.isEmpty && !description.isEmpty && !mcpConfigJSON.isEmpty
    }

    @ViewBuilder
    private func formField<Content: View>(label: String, placeholder: String = "", @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            formFieldLabel(label)
            content()
        }
    }

    private func formFieldLabel(_ label: String) -> some View {
        Text(label)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.secondary)
    }

    // MARK: - Actions

    private func submitSkill() {
        let tags = tagsText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        Task {
            let success = await manager.publishSkill(
                name: name,
                description: description,
                category: category,
                mcpConfigJSON: mcpConfigJSON,
                tags: tags,
                priceTokens: priceTokens
            )
            if success {
                dismiss()
            }
        }
    }

    private func insertTemplate() {
        mcpConfigJSON = """
        {
          "server_id": "my-skill-server",
          "server_name": "\(name.isEmpty ? "My Skill" : name)",
          "server_description": "\(description.isEmpty ? "スキルの説明" : description)",
          "icon": "puzzlepiece.extension",
          "tools": [
            {
              "name": "my_tool",
              "description": "ツールの説明",
              "input_schema": {
                "type": "object",
                "properties": {
                  "input": {
                    "type": "string",
                    "description": "入力テキスト"
                  }
                },
                "required": ["input"]
              },
              "action_type": "httpRequest",
              "action_config": {
                "url": "https://api.example.com/tool",
                "method": "POST"
              }
            }
          ]
        }
        """
    }
}

#Preview {
    SkillPublishView()
}
