import SwiftUI

/// Onboarding view for selecting MCP servers on first launch
struct OnboardingMCPView: View {
    @EnvironmentObject var appState: AppState
    @Binding var isPresented: Bool

    @State private var selectedServers: Set<String> = []

    private let serverGroups: [(title: String, servers: [ServerOption])] = [
        ("基本機能", [
            ServerOption(id: "filesystem", name: "ファイル", icon: "folder", description: "アプリ内ファイルの読み書き"),
            ServerOption(id: "notes", name: "メモ", icon: "note.text", description: "メモの作成・管理"),
            ServerOption(id: "websearch", name: "Web検索", icon: "theatermasks.fill", description: "DuckDuckGoで匿名検索")
        ]),
        ("カレンダー・タスク", [
            ServerOption(id: "calendar", name: "カレンダー", icon: "calendar", description: "予定の確認・作成"),
            ServerOption(id: "reminders", name: "リマインダー", icon: "checklist", description: "タスクの管理")
        ]),
        ("連絡先・写真", [
            ServerOption(id: "contacts", name: "連絡先", icon: "person.crop.circle", description: "連絡先の検索"),
            ServerOption(id: "photos", name: "写真", icon: "photo", description: "写真ライブラリへのアクセス")
        ]),
        ("位置情報", [
            ServerOption(id: "location", name: "位置情報", icon: "location", description: "現在地の取得")
        ]),
        ("ユーティリティ", [
            ServerOption(id: "weather", name: "天気", icon: "cloud.sun", description: "天気予報の取得"),
            ServerOption(id: "shortcuts", name: "ショートカット", icon: "command", description: "iOSショートカットの実行")
        ])
    ]

    private struct ServerOption: Identifiable {
        let id: String
        let name: String
        let icon: String
        let description: String
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Header
                VStack(spacing: 12) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 50))
                        .foregroundStyle(.blue)

                    Text("ElioChatの機能を選択")
                        .font(.title.bold())

                    Text("使用したい機能を選んでください。\n後から設定で変更できます。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.vertical, 24)

                // Presets
                HStack(spacing: 12) {
                    presetButton("全機能", icon: "star.fill", servers: allServerIds)
                    presetButton("プライバシー重視", icon: "lock.shield", servers: privacyFocusedIds)
                    presetButton("最小構成", icon: "leaf", servers: minimalIds)
                }
                .padding(.horizontal)
                .padding(.bottom, 16)

                // Server list
                ScrollView {
                    LazyVStack(spacing: 20) {
                        ForEach(serverGroups, id: \.title) { group in
                            serverGroupView(group)
                        }
                    }
                    .padding()
                }

                // Continue button
                Button(action: {
                    appState.enabledMCPServers = selectedServers
                    UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
                    isPresented = false
                }) {
                    Text("続ける (\(selectedServers.count)個選択)")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(selectedServers.isEmpty ? Color.gray : Color.blue)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(selectedServers.isEmpty)
                .padding()
            }
            #if !targetEnvironment(macCatalyst)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .onAppear {
                // Start with default selection
                selectedServers = appState.enabledMCPServers
            }
        }
    }

    private var allServerIds: Set<String> {
        Set(serverGroups.flatMap { $0.servers.map { $0.id } })
    }

    private var privacyFocusedIds: Set<String> {
        ["filesystem", "notes", "calendar", "reminders"]
    }

    private var minimalIds: Set<String> {
        ["filesystem", "notes", "websearch"]
    }

    @ViewBuilder
    private func presetButton(_ title: String, icon: String, servers: Set<String>) -> some View {
        Button(action: {
            withAnimation(.spring(response: 0.3)) {
                selectedServers = servers
            }
        }) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                Text(title)
                    .font(.caption)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                selectedServers == servers
                    ? Color.blue.opacity(0.2)
                    : Color(.systemGray6)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(selectedServers == servers ? Color.blue : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func serverGroupView(_ group: (title: String, servers: [ServerOption])) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(group.title)
                .font(.headline)
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                ForEach(group.servers) { server in
                    serverRow(server)
                }
            }
        }
    }

    @ViewBuilder
    private func serverRow(_ server: ServerOption) -> some View {
        let isSelected = selectedServers.contains(server.id)

        Button(action: {
            withAnimation(.spring(response: 0.2)) {
                if isSelected {
                    selectedServers.remove(server.id)
                } else {
                    selectedServers.insert(server.id)
                }
            }
        }) {
            HStack(spacing: 12) {
                Image(systemName: server.icon)
                    .font(.system(size: 20))
                    .foregroundStyle(isSelected ? .blue : .secondary)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text(server.name)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                    Text(server.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(isSelected ? .blue : Color(.systemGray4))
            }
            .padding()
            .background(
                isSelected
                    ? Color.blue.opacity(0.1)
                    : Color(.systemGray6)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}

/// Check if onboarding should be shown
struct OnboardingChecker {
    static var shouldShowOnboarding: Bool {
        !UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
    }
}

#Preview {
    OnboardingMCPView(isPresented: .constant(true))
        .environmentObject(AppState())
}
