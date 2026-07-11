import SwiftUI

// MARK: - Agent List View

struct AgentListView: View {
    @ObservedObject var agentManager = AgentManager.shared
    @State private var editingAgent: AgentProfile?
    @State private var showingNewAgent = false
    @State private var searchText = ""
    @Environment(\.dismiss) private var dismiss

    private var filteredAgents: [AgentProfile] {
        if searchText.isEmpty { return agentManager.agents }
        let q = searchText.lowercased()
        return agentManager.agents.filter {
            $0.name.lowercased().contains(q) || $0.description.lowercased().contains(q)
        }
    }

    private var groupedAgents: [(AgentCategory, [AgentProfile])] {
        let grouped = Dictionary(grouping: filteredAgents) { $0.category }
        return AgentCategory.allCases.compactMap { cat in
            guard let agents = grouped[cat], !agents.isEmpty else { return nil }
            return (cat, agents)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Search
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                        TextField("エージェントを検索", text: $searchText)
                            .textFieldStyle(.plain)
                    }
                    .padding(10)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal, 16)

                    // Grouped list
                    ForEach(groupedAgents, id: \.0) { category, agents in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 6) {
                                Image(systemName: category.icon)
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                                Text(category.displayName)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 20)

                            ForEach(agents) { agent in
                                AgentRow(
                                    agent: agent,
                                    isSelected: agent.id == agentManager.selectedAgentId,
                                    onSelect: {
                                        agentManager.select(agent)
                                        dismiss()
                                    },
                                    onEdit: {
                                        editingAgent = agent
                                    }
                                )
                            }
                        }
                    }
                }
                .padding(.vertical, 12)
            }
            .navigationTitle("エージェント")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("閉じる") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: { showingNewAgent = true }) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 20))
                    }
                }
            }
            .sheet(item: $editingAgent) { agent in
                AgentEditorView(agent: agent, mode: .edit)
            }
            .sheet(isPresented: $showingNewAgent) {
                AgentEditorView(agent: AgentProfile(
                    name: "",
                    description: "",
                    systemPrompt: "",
                    category: .custom
                ), mode: .create)
            }
        }
    }
}

// MARK: - Agent Row

struct AgentRow: View {
    let agent: AgentProfile
    let isSelected: Bool
    let onSelect: () -> Void
    let onEdit: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                // Icon
                ZStack {
                    Circle()
                        .fill(agent.color.opacity(0.15))
                        .frame(width: 44, height: 44)
                    Image(systemName: agent.icon)
                        .font(.system(size: 18))
                        .foregroundStyle(agent.color)
                }

                // Info
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(agent.name)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.primary)
                        if agent.isBuiltIn {
                            Text("組込")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(agent.color.opacity(0.6))
                                .clipShape(Capsule())
                        }
                    }
                    Text(agent.description)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer()

                // Selection indicator
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(agent.color)
                }

                // Edit button
                Button(action: onEdit) {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 18))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(isSelected ? agent.color.opacity(0.08) : Color(.systemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(isSelected ? agent.color.opacity(0.3) : Color(.separator).opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
    }
}

// MARK: - Agent Editor View

struct AgentEditorView: View {
    @ObservedObject var agentManager = AgentManager.shared
    @Environment(\.dismiss) private var dismiss

    enum Mode { case create, edit }
    let mode: Mode

    @State var agent: AgentProfile

    init(agent: AgentProfile, mode: Mode) {
        self._agent = State(initialValue: agent)
        self.mode = mode
    }

    private let colorOptions = [
        "#6366F1", "#3B82F6", "#10B981", "#F59E0B",
        "#EF4444", "#EC4899", "#8B5CF6", "#06B6D4",
        "#F97316", "#84CC16", "#14B8A6", "#A855F7"
    ]

    private let iconOptions = [
        "sparkles", "brain", "magnifyingglass", "globe",
        "chevron.left.forwardslash.chevron.right", "pencil.line",
        "calendar", "heart", "briefcase", "paintbrush",
        "wrench.and.screwdriver", "book", "music.note",
        "camera", "gamecontroller", "graduationcap",
        "stethoscope", "cart", "leaf", "star"
    ]

    var body: some View {
        NavigationStack {
            Form {
                // Basic Info
                Section("基本情報") {
                    TextField("名前", text: $agent.name)
                    TextField("説明", text: $agent.description, axis: .vertical)
                        .lineLimit(2...4)

                    Picker("カテゴリ", selection: $agent.category) {
                        ForEach(AgentCategory.allCases, id: \.self) { cat in
                            Label(cat.displayName, systemImage: cat.icon).tag(cat)
                        }
                    }
                }

                // Appearance
                Section("外観") {
                    // Icon picker
                    VStack(alignment: .leading, spacing: 8) {
                        Text("アイコン")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 10) {
                            ForEach(iconOptions, id: \.self) { icon in
                                Button {
                                    agent.icon = icon
                                } label: {
                                    Image(systemName: icon)
                                        .font(.system(size: 18))
                                        .frame(width: 36, height: 36)
                                        .background(agent.icon == icon ? agent.color.opacity(0.2) : Color.clear)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8)
                                                .stroke(agent.icon == icon ? agent.color : .clear, lineWidth: 2)
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    // Color picker
                    VStack(alignment: .leading, spacing: 8) {
                        Text("カラー")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 10) {
                            ForEach(colorOptions, id: \.self) { hex in
                                Button {
                                    agent.colorHex = hex
                                } label: {
                                    Circle()
                                        .fill(Color(hex: hex) ?? .blue)
                                        .frame(width: 32, height: 32)
                                        .overlay(
                                            Circle()
                                                .stroke(.white, lineWidth: agent.colorHex == hex ? 3 : 0)
                                        )
                                        .shadow(color: agent.colorHex == hex ? (Color(hex: hex) ?? .blue).opacity(0.5) : .clear, radius: 4)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                // System Prompt
                Section("システムプロンプト") {
                    TextEditor(text: $agent.systemPrompt)
                        .frame(minHeight: 200)
                        .font(.system(size: 14, design: .monospaced))

                    Text("空欄の場合はデフォルトのシステムプロンプトが使用されます")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // Advanced
                Section("詳細設定") {
                    HStack {
                        Text("Temperature")
                        Spacer()
                        if let temp = agent.temperature {
                            Text(String(format: "%.1f", temp))
                                .foregroundStyle(.secondary)
                        } else {
                            Text("デフォルト")
                                .foregroundStyle(.secondary)
                        }
                    }

                    Slider(
                        value: Binding(
                            get: { agent.temperature ?? 0.7 },
                            set: { agent.temperature = $0 }
                        ),
                        in: 0...2,
                        step: 0.1
                    )

                    Toggle("Temperature をカスタム", isOn: Binding(
                        get: { agent.temperature != nil },
                        set: { agent.temperature = $0 ? 0.7 : nil }
                    ))
                }

                // Preview
                Section("プレビュー") {
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(agent.color.opacity(0.15))
                                .frame(width: 50, height: 50)
                            Image(systemName: agent.icon)
                                .font(.system(size: 22))
                                .foregroundStyle(agent.color)
                        }
                        VStack(alignment: .leading, spacing: 3) {
                            Text(agent.name.isEmpty ? "名前未設定" : agent.name)
                                .font(.system(size: 16, weight: .semibold))
                            Text(agent.description.isEmpty ? "説明未設定" : agent.description)
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                    .padding(.vertical, 4)
                }

                // Actions
                if mode == .edit {
                    Section {
                        if !agent.isBuiltIn {
                            Button("このエージェントを削除", role: .destructive) {
                                agentManager.deleteAgent(agent)
                                dismiss()
                            }
                        }
                        Button("複製して新規作成") {
                            agentManager.duplicateAgent(agent)
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(mode == .create ? "新規エージェント" : "エージェント編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("保存") {
                        save()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(agent.name.isEmpty)
                }
            }
        }
    }

    private func save() {
        switch mode {
        case .create:
            agentManager.addAgent(agent)
        case .edit:
            agentManager.updateAgent(agent)
        }
    }
}
