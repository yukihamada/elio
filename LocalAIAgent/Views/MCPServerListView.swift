import SwiftUI

struct MCPServerListView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    private let builtInServers: [MCPServerDisplayInfo] = [
        MCPServerDisplayInfo(
            id: "websearch",
            name: "Ghost Search",
            description: "DuckDuckGoで匿名検索（追跡なし）",
            icon: "theatermasks.fill",
            color: .purple
        ),
        MCPServerDisplayInfo(
            id: "filesystem",
            name: "ファイルシステム",
            description: "アプリ内のファイル読み書き",
            icon: "folder.fill",
            color: .blue
        ),
        MCPServerDisplayInfo(
            id: "calendar",
            name: "カレンダー",
            description: "予定の読み書き",
            icon: "calendar",
            color: .red
        ),
        MCPServerDisplayInfo(
            id: "reminders",
            name: "リマインダー",
            description: "リマインダーの管理",
            icon: "checklist",
            color: .orange
        ),
        MCPServerDisplayInfo(
            id: "contacts",
            name: "連絡先",
            description: "連絡先の検索・閲覧",
            icon: "person.crop.circle.fill",
            color: .green
        ),
        MCPServerDisplayInfo(
            id: "photos",
            name: "写真",
            description: "写真ライブラリへのアクセス",
            icon: "photo.fill",
            color: .pink
        ),
        MCPServerDisplayInfo(
            id: "location",
            name: "位置情報",
            description: "現在地の取得・場所検索",
            icon: "location.fill",
            color: .blue
        ),
        MCPServerDisplayInfo(
            id: "shortcuts",
            name: "ショートカット",
            description: "ショートカットの実行",
            icon: "command",
            color: .indigo
        )
    ]

    var body: some View {
        ZStack {
            // Background
            Color(.systemGroupedBackground)
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {
                    // Header info
                    headerInfo
                        .padding(.top, 8)

                    // Built-in servers
                    builtInServersSection

                    // Custom servers
                    customServersSection

                    // Footer info
                    footerInfo
                        .padding(.bottom, 20)
                }
                .padding(.horizontal, 20)
            }
        }
        .navigationTitle(String(localized: "settings.mcp.servers"))
        #if !targetEnvironment(macCatalyst)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    // MARK: - Header Info

    private var headerInfo: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(.linearGradient(
                        colors: [.orange.opacity(0.2), .yellow.opacity(0.2)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .frame(width: 44, height: 44)

                Image(systemName: "sparkles")
                    .font(.system(size: 20))
                    .foregroundStyle(.orange)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("\(appState.enabledMCPServers.count)個の連携機能が有効")
                    .font(.system(size: 15, weight: .semibold))

                Text("ElioChatがこれらの情報にアクセスできます")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.secondarySystemBackground))
        )
    }

    // MARK: - Built-in Servers

    private var builtInServersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "iPhone連携", icon: "iphone", color: .purple)

            VStack(spacing: 8) {
                ForEach(builtInServers) { server in
                    MCPServerCard(
                        server: server,
                        isEnabled: appState.enabledMCPServers.contains(server.id),
                        onToggle: {
                            withAnimation(.spring(response: 0.3)) {
                                appState.toggleMCPServer(server.id)
                            }
                        }
                    )
                }
            }
        }
    }

    // MARK: - Custom Servers

    private var customServersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "カスタム連携", icon: "plus.circle.fill", color: .green)

            NavigationLink(destination: CustomMCPServerView()) {
                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.green.opacity(0.1))
                            .frame(width: 44, height: 44)

                        Image(systemName: "plus")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(.green)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("連携機能を追加")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.primary)

                        Text("外部サービスとの連携を設定")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color(.secondarySystemBackground))
                )
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Footer Info

    private var footerInfo: some View {
        HStack(spacing: 10) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 16))
                .foregroundStyle(.blue)

            Text("必要な権限は各機能の初回使用時に確認されます")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.blue.opacity(0.08))
        )
    }
}

// MARK: - Server Display Info

struct MCPServerDisplayInfo: Identifiable {
    let id: String
    let name: String
    let description: String
    let icon: String
    let color: Color
}

// MARK: - Server Card

struct MCPServerCard: View {
    let server: MCPServerDisplayInfo
    let isEnabled: Bool
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            // Icon
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(server.color.opacity(isEnabled ? 0.15 : 0.08))
                    .frame(width: 44, height: 44)

                Image(systemName: server.icon)
                    .font(.system(size: 20))
                    .foregroundStyle(isEnabled ? server.color : Color.secondary)
            }

            // Info
            VStack(alignment: .leading, spacing: 2) {
                Text(server.name)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(isEnabled ? .primary : .secondary)

                Text(server.description)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Toggle
            Toggle("", isOn: Binding(
                get: { isEnabled },
                set: { _ in onToggle() }
            ))
            .labelsHidden()
            .tint(server.color)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(isEnabled ? server.color.opacity(0.3) : Color.clear, lineWidth: 1.5)
        )
    }
}

// MARK: - Custom MCP Server View

struct CustomMCPServerView: View {
    @State private var serverName = ""
    @State private var serverURL = ""
    @State private var showingImportSheet = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground)
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {
                    // Input fields
                    inputSection

                    // Import from file
                    importSection

                    // Example config
                    exampleSection
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
            }
        }
        .navigationTitle("カスタム連携")
        #if !targetEnvironment(macCatalyst)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("追加") {
                    addServer()
                }
                .fontWeight(.semibold)
                .disabled(serverName.isEmpty || serverURL.isEmpty)
            }
        }
        .fileImporter(
            isPresented: $showingImportSheet,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                importFromFile(url)
            }
        }
    }

    private var inputSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "連携設定", icon: "link", color: .blue)

            VStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("サーバー名")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)

                    TextField("例: My Custom Server", text: $serverName)
                        .textFieldStyle(.plain)
                        .padding(14)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color(.tertiarySystemBackground))
                        )
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("設定ファイルURL")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)

                    TextField("https://example.com/mcp-config.json", text: $serverURL)
                        .textFieldStyle(.plain)
                        .keyboardType(.URL)
                        .autocapitalization(.none)
                        .padding(14)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color(.tertiarySystemBackground))
                        )
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.secondarySystemBackground))
            )
        }
    }

    private var importSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "ファイルからインポート", icon: "doc.badge.plus", color: .green)

            Button(action: { showingImportSheet = true }) {
                HStack(spacing: 12) {
                    Image(systemName: "folder.badge.plus")
                        .font(.system(size: 20))
                        .foregroundStyle(.green)

                    Text("JSONファイルを選択")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.primary)

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color(.secondarySystemBackground))
                )
            }
            .buttonStyle(.plain)
        }
    }

    private var exampleSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "設定ファイル例", icon: "doc.text", color: .orange)

            ScrollView(.horizontal, showsIndicators: false) {
                Text(sampleConfig)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(14)
            }
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.secondarySystemBackground))
            )
        }
    }

    private let sampleConfig = """
    {
      "id": "my-server",
      "name": "My Custom Server",
      "tools": [
        {
          "name": "my_tool",
          "description": "My custom tool",
          "inputSchema": {
            "type": "object",
            "properties": {
              "param1": {
                "type": "string",
                "description": "A parameter"
              }
            }
          }
        }
      ]
    }
    """

    private func addServer() {
        guard !serverName.isEmpty, !serverURL.isEmpty else { return }
        // Save custom server config to UserDefaults
        var customServers = UserDefaults.standard.array(forKey: "custom_mcp_servers") as? [[String: String]] ?? []
        customServers.append(["name": serverName, "url": serverURL])
        UserDefaults.standard.set(customServers, forKey: "custom_mcp_servers")
        dismiss()
    }

    private func importFromFile(_ url: URL) {
        guard url.startAccessingSecurityScopedResource() else { return }
        defer { url.stopAccessingSecurityScopedResource() }
        if let data = try? Data(contentsOf: url),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let name = json["name"] as? String {
            serverName = name
            serverURL = (json["url"] as? String) ?? ""
        }
    }
}

#Preview {
    NavigationStack {
        MCPServerListView()
            .environmentObject(AppState())
    }
}
