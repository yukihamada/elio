import SwiftUI

/// Settings view for running inference server and earning tokens
struct InferenceServerSettingsView: View {
    @StateObject private var config = InferenceServerConfig.shared
    @StateObject private var serverManager = PrivateServerManager.shared
    @StateObject private var tokenManager = TokenManager.shared

    @State private var showingInfo = false

    var body: some View {
        Form {
            // Server Status
            Section {
                HStack {
                    Image(systemName: serverManager.isRunning ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(serverManager.isRunning ? .green : .gray)
                        .font(.title2)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(serverManager.isRunning ? "サーバー稼働中" : "サーバー停止中")
                            .font(.headline)

                        if serverManager.isRunning {
                            if let address = serverManager.serverAddress {
                                Text(address)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }

                    Spacer()

                    Toggle("", isOn: $config.isEnabled)
                        .labelsHidden()
                        .onChange(of: config.isEnabled) { _, newValue in
                            Task {
                                if newValue {
                                    await config.startServerIfNeeded()
                                } else {
                                    config.stopServer()
                                }
                            }
                        }
                }
            } header: {
                Text("サーバー状態")
            }

            // Earnings Today
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("処理したリクエスト")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Text("\(serverManager.todayRequestsServed)")
                            .font(.title2)
                            .fontWeight(.bold)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 4) {
                        Text("獲得トークン")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        HStack(spacing: 4) {
                            Image(systemName: "star.fill")
                                .foregroundColor(.yellow)
                            Text("\(serverManager.todayTokensEarned)")
                                .font(.title2)
                                .fontWeight(.bold)
                        }
                    }
                }
                .padding(.vertical, 8)

                // Total Balance
                HStack {
                    Text("合計残高")
                        .font(.subheadline)
                    Spacer()
                    HStack(spacing: 4) {
                        Image(systemName: "star.fill")
                            .foregroundColor(.yellow)
                        Text("\(tokenManager.balance)")
                            .font(.headline)
                    }
                }
            } header: {
                Text("収益")
            } footer: {
                Text("他のユーザーのAI推論リクエストを処理してトークンを獲得できます")
            }

            // Server Mode
            Section {
                Picker("公開範囲", selection: $config.serverMode) {
                    ForEach(ServerMode.allCases) { mode in
                        HStack {
                            Image(systemName: mode.icon)
                            Text(mode.displayName)
                        }
                        .tag(mode)
                    }
                }
                .pickerStyle(.menu)

                Text(config.serverMode.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            } header: {
                Text("サーバーモード")
            }

            // Pricing
            Section {
                Stepper(value: $config.pricePerRequest, in: 0...10) {
                    HStack {
                        Text("リクエスト単価")
                        Spacer()
                        HStack(spacing: 4) {
                            Image(systemName: "star.fill")
                                .foregroundColor(.yellow)
                            Text("\(config.pricePerRequest)")
                                .font(.headline)
                        }
                    }
                }

                if config.pricePerRequest == 0 {
                    Label("無料提供 - コミュニティに貢献！", systemImage: "heart.fill")
                        .font(.caption)
                        .foregroundColor(.pink)
                } else {
                    Label("ユーザーはリクエストごとに\(config.pricePerRequest)トークンを支払います", systemImage: "info.circle")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } header: {
                Text("料金設定")
            }

            // Auto-Start Settings
            Section {
                Toggle("充電中に自動起動", isOn: $config.autoStartWhenCharging)

                HStack {
                    Text("バッテリー残量で自動停止")
                    Spacer()
                    Text("\(config.autoStopBatteryThreshold)%")
                        .foregroundColor(.secondary)
                }

                Slider(value: Binding(
                    get: { Double(config.autoStopBatteryThreshold) },
                    set: { config.autoStopBatteryThreshold = Int($0) }
                ), in: 10...50, step: 5)
            } header: {
                Text("電源管理")
            } footer: {
                Text("バッテリー残量が\(config.autoStopBatteryThreshold)%を下回るとサーバーを自動停止します")
            }

            // Performance Settings
            Section {
                Stepper(value: $config.maxConcurrentRequests, in: 1...10) {
                    HStack {
                        Text("最大同時リクエスト数")
                        Spacer()
                        Text("\(config.maxConcurrentRequests)")
                            .foregroundColor(.secondary)
                    }
                }

                Toggle("インターネット接続を許可", isOn: $config.allowInternetConnections)
            } header: {
                Text("パフォーマンス")
            } footer: {
                if config.allowInternetConnections {
                    Label("インターネット経由の接続を許可するとトークンを多く獲得できますが、データ通信量が増えます", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundColor(.orange)
                } else {
                    Text("ローカルネットワークからの接続のみ受け付けます")
                }
            }

            // Pairing Code
            if serverManager.isRunning {
                Section {
                    HStack {
                        Text("ペアリングコード")
                        Spacer()
                        Text(serverManager.pairingCode)
                            .font(.system(.title2, design: .monospaced))
                            .fontWeight(.bold)
                    }

                    Button {
                        serverManager.regeneratePairingCode()
                    } label: {
                        Label("コードを再生成", systemImage: "arrow.clockwise")
                    }
                } header: {
                    Text("接続")
                } footer: {
                    Text("このコードを共有して他のユーザーがサーバーに接続できるようにします")
                }
            }

            // Info Section
            Section {
                Button {
                    showingInfo = true
                } label: {
                    Label("サーバーモードの仕組み", systemImage: "info.circle")
                }
            }
        }
        .navigationTitle("推論サーバー")
        .sheet(isPresented: $showingInfo) {
            InferenceServerInfoView()
        }
    }
}

/// Info sheet explaining how server mode works
struct InferenceServerInfoView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Header
                    HStack {
                        Image(systemName: "server.rack")
                            .font(.system(size: 60))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.blue, .purple],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )

                        VStack(alignment: .leading, spacing: 4) {
                            Text("推論サーバー")
                                .font(.title)
                                .fontWeight(.bold)
                            Text("GPUを共有してトークンを獲得")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding()

                    Divider()

                    // How It Works
                    VStack(alignment: .leading, spacing: 12) {
                        Text("仕組み")
                            .font(.headline)

                        InfoCard(
                            icon: "1.circle.fill",
                            title: "サーバーモードを有効化",
                            description: "サーバーをオンにすると、他のユーザーからの推論リクエストを受け付けます"
                        )

                        InfoCard(
                            icon: "2.circle.fill",
                            title: "リクエストを処理",
                            description: "他のユーザーがAI推論を必要とする時、あなたのデバイスがローカルモデルで処理します"
                        )

                        InfoCard(
                            icon: "3.circle.fill",
                            title: "トークンを獲得",
                            description: "リクエストを処理するたびにトークンを獲得。プレミアム機能や他のサーバーの利用に使えます"
                        )
                    }
                    .padding()

                    Divider()

                    // Server Modes
                    VStack(alignment: .leading, spacing: 12) {
                        Text("サーバーモード")
                            .font(.headline)

                        ForEach(ServerMode.allCases) { mode in
                            HStack(spacing: 12) {
                                Image(systemName: mode.icon)
                                    .font(.title2)
                                    .foregroundColor(mode.color)
                                    .frame(width: 40)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(mode.displayName)
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                    Text(mode.description)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding(12)
                            .background(mode.color.opacity(0.1))
                            .cornerRadius(8)
                        }
                    }
                    .padding()

                    Divider()

                    // Tips
                    VStack(alignment: .leading, spacing: 12) {
                        Text("ヒント")
                            .font(.headline)

                        TipCard(
                            icon: "bolt.fill",
                            title: "充電しながら使おう",
                            description: "充電中の自動起動を有効にして収益を最大化"
                        )

                        TipCard(
                            icon: "wifi",
                            title: "安定した接続を確保",
                            description: "Wi-Fiを使うとパフォーマンスが向上し、データ通信量も節約できます"
                        )

                        TipCard(
                            icon: "dollarsign.circle.fill",
                            title: "料金を設定",
                            description: "低価格にするとリクエスト数が増えます。無料提供でコミュニティに貢献も！"
                        )
                    }
                    .padding()
                }
            }
            .navigationTitle("サーバーモードについて")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("閉じる") {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct InfoCard: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(
                    LinearGradient(
                        colors: [.blue, .purple],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 40)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

struct TipCard: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(.orange)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .fontWeight(.semibold)
                Text(description)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(10)
        .background(Color.orange.opacity(0.1))
        .cornerRadius(8)
    }
}

#Preview {
    NavigationStack {
        InferenceServerSettingsView()
    }
}
