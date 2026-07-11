import SwiftUI

// MARK: - Remote (External) MCP Servers Settings

struct RemoteMCPServerView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var manager = RemoteMCPServerManager.shared
    @State private var showingAdd = false

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {
                    presetsSection
                    savedSection
                    footer
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 24)
            }
        }
        .navigationTitle("外部MCPサーバー")
        #if !targetEnvironment(macCatalyst)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showingAdd = true } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAdd) {
            NavigationStack {
                RemoteMCPServerEditView(config: nil)
                    .environmentObject(appState)
            }
        }
    }

    // MARK: Presets

    private var presetsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "ワンタップで追加", icon: "sparkles", color: .orange)

            if manager.availablePresets.isEmpty {
                Text("すべてのプリセットを追加済みです")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemBackground)))
            } else {
                VStack(spacing: 8) {
                    ForEach(manager.availablePresets) { preset in
                        Button {
                            manager.addOrUpdate(preset, token: nil)
                            appState.reloadRemoteMCPServers()
                        } label: {
                            HStack(spacing: 14) {
                                iconBubble(preset.icon, .orange)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(preset.name)
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundStyle(.primary)
                                    Text(preset.urlString + (preset.requiresToken ? " · 要トークン" : " · 匿名可"))
                                        .font(.system(size: 12))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer()
                                Image(systemName: "plus.circle.fill")
                                    .foregroundStyle(.orange)
                            }
                            .padding(14)
                            .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemBackground)))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: Saved servers

    private var savedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "登録済みサーバー", icon: "server.rack", color: .blue)

            if manager.configs.isEmpty {
                Text("まだサーバーがありません。上のプリセットか + から追加してください。")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemBackground)))
            } else {
                VStack(spacing: 8) {
                    ForEach(manager.configs) { config in
                        NavigationLink {
                            RemoteMCPServerEditView(config: config)
                                .environmentObject(appState)
                        } label: {
                            RemoteServerRow(
                                config: config,
                                isEnabled: config.isEnabled,
                                onToggle: {
                                    manager.setEnabled(!config.isEnabled, id: config.id)
                                    appState.reloadRemoteMCPServers()
                                }
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Image(systemName: "lock.fill").foregroundStyle(.green)
            Text("トークンはこの端末のキーチェーンにのみ保存されます。")
                .font(.system(size: 13)).foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.green.opacity(0.08)))
    }

    private func iconBubble(_ name: String, _ color: Color) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10).fill(color.opacity(0.12)).frame(width: 44, height: 44)
            Image(systemName: name).font(.system(size: 20)).foregroundStyle(color)
        }
    }
}

// MARK: - Server Row

private struct RemoteServerRow: View {
    let config: RemoteMCPServerConfig
    let isEnabled: Bool
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill((isEnabled ? Color.blue : Color.secondary).opacity(0.12))
                    .frame(width: 44, height: 44)
                Image(systemName: config.icon)
                    .font(.system(size: 20))
                    .foregroundStyle(isEnabled ? .blue : .secondary)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(config.name)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(isEnabled ? .primary : .secondary)
                Text(config.urlString)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Toggle("", isOn: Binding(get: { isEnabled }, set: { _ in onToggle() }))
                .labelsHidden()
                .tint(.blue)
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemBackground)))
    }
}

// MARK: - Add / Edit View

struct RemoteMCPServerEditView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @StateObject private var manager = RemoteMCPServerManager.shared

    /// nil = add new
    let config: RemoteMCPServerConfig?

    @State private var name = ""
    @State private var urlString = ""
    @State private var token = ""
    @State private var tokenLoaded = false

    @State private var testing = false
    @State private var testResult: String?
    @State private var testIsError = false

    private var isEditing: Bool { config != nil }

    var body: some View {
        Form {
            Section("接続設定") {
                TextField("名前", text: $name)
                TextField("URL (https://.../mcp)", text: $urlString)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField("Bearer トークン (任意)", text: $token)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }

            Section {
                Button {
                    Task { await runTest() }
                } label: {
                    HStack {
                        if testing { ProgressView().padding(.trailing, 6) }
                        Text("接続テスト")
                    }
                }
                .disabled(testing || urlString.isEmpty)

                if let result = testResult {
                    Text(result)
                        .font(.system(size: 13))
                        .foregroundStyle(testIsError ? .red : .green)
                }
            }

            if isEditing {
                Section {
                    Button("削除", role: .destructive) {
                        if let c = config {
                            manager.remove(id: c.id)
                            appState.reloadRemoteMCPServers()
                        }
                        dismiss()
                    }
                }
            }
        }
        .navigationTitle(isEditing ? "サーバーを編集" : "サーバーを追加")
        #if !targetEnvironment(macCatalyst)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("保存") { save() }
                    .fontWeight(.semibold)
                    .disabled(name.isEmpty || urlString.isEmpty)
            }
        }
        .onAppear(perform: loadInitial)
    }

    private func loadInitial() {
        guard let c = config, !tokenLoaded else { return }
        name = c.name
        urlString = c.urlString
        token = manager.token(for: c) ?? ""
        tokenLoaded = true
    }

    /// Normalize and validate the entered URL. Only `https://` is accepted —
    /// the bearer token must never travel over a cleartext connection.
    private func normalizedURLString() -> String {
        urlString.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func isValidHTTPSURL(_ s: String) -> Bool {
        guard let url = URL(string: s), url.scheme?.lowercased() == "https", url.host != nil else {
            return false
        }
        return true
    }

    private func currentConfig() -> RemoteMCPServerConfig {
        var c = config ?? RemoteMCPServerConfig(name: name, urlString: normalizedURLString(),
                                                isEnabled: true,
                                                requiresToken: !token.isEmpty)
        c.name = name
        c.urlString = normalizedURLString()
        c.requiresToken = !token.isEmpty || c.requiresToken
        return c
    }

    private func save() {
        let url = normalizedURLString()
        guard isValidHTTPSURL(url) else {
            testIsError = true
            testResult = "URLは https:// で始まる必要があります"
            return
        }
        let c = currentConfig()
        // Pass token (possibly empty -> clears) only when editing the token field is meaningful.
        manager.addOrUpdate(c, token: token)
        appState.reloadRemoteMCPServers()
        dismiss()
    }

    private func runTest() async {
        testing = true
        testResult = nil
        defer { testing = false }
        guard isValidHTTPSURL(normalizedURLString()) else {
            testIsError = true
            testResult = "URLは https:// で始まる必要があります"
            return
        }
        do {
            let probe = currentConfig()
            let server = try RemoteMCPServer(config: probe, token: token.isEmpty ? nil : token)
            let tools = try await server.refreshTools()
            testIsError = false
            if tools.isEmpty {
                testResult = "接続成功 · ツール0個（権限/認証を確認）"
            } else {
                let names = tools.prefix(8).map { $0.name }.joined(separator: ", ")
                testResult = "接続成功 · \(tools.count)個のツール: \(names)"
            }
        } catch {
            testIsError = true
            testResult = "失敗: \(error.localizedDescription)"
        }
    }
}

#Preview {
    NavigationStack {
        RemoteMCPServerView().environmentObject(AppState())
    }
}
