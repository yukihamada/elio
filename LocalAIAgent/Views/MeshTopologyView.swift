import SwiftUI

/// Mesh Topology View - Visualizes P2P mesh network topology
struct MeshTopologyView: View {
    @ObservedObject var meshManager = MeshP2PManager.shared
    @State private var showingPeerDetail: MeshPeer?

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 30) {
                    // My Node
                    VStack(spacing: 12) {
                        Text("あなたのデバイス")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        NodeCard(
                            name: getDeviceName(),
                            capability: getLocalCapability(),
                            isLocal: true,
                            hopCount: 0
                        )
                    }

                    if !meshManager.connectedPeers.isEmpty {
                        // Connection Indicator
                        Image(systemName: "arrow.down")
                            .font(.title2)
                            .foregroundStyle(.gray)

                        // Connected Peers
                        VStack(alignment: .leading, spacing: 16) {
                            Text("接続済みピア (\(meshManager.connectedPeers.count))")
                                .font(.headline)
                                .padding(.horizontal)

                            ForEach(meshManager.connectedPeers) { peer in
                                Button(action: {
                                    showingPeerDetail = peer
                                }) {
                                    HStack(spacing: 12) {
                                        // Hop count indicator
                                        Text("\(peer.hopCount)")
                                            .font(.caption.bold())
                                            .foregroundStyle(.white)
                                            .frame(width: 30, height: 30)
                                            .background(Circle().fill(hopColor(peer.hopCount)))

                                        NodeCard(
                                            name: peer.name,
                                            capability: peer.capability,
                                            isLocal: false,
                                            hopCount: peer.hopCount
                                        )
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    } else {
                        // Empty State
                        VStack(spacing: 16) {
                            Image(systemName: "antenna.radiowaves.left.and.right.slash")
                                .font(.system(size: 50))
                                .foregroundStyle(.secondary)

                            Text("接続されたピアはありません")
                                .font(.headline)

                            Text("メッシュモードを有効にして\n近くのデバイスと接続しましょう")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding()
                    }

                    // Network Stats
                    if !meshManager.connectedPeers.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("ネットワーク統計")
                                .font(.headline)

                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                                StatCard(
                                    title: "接続ピア",
                                    value: "\(meshManager.connectedPeers.count)",
                                    icon: "network",
                                    color: .blue
                                )

                                StatCard(
                                    title: "LLM搭載",
                                    value: "\(meshManager.connectedPeers.filter { $0.capability.hasLocalLLM }.count)",
                                    icon: "cpu",
                                    color: .green
                                )

                                StatCard(
                                    title: "最大ホップ",
                                    value: "\(meshManager.connectedPeers.map { $0.hopCount }.max() ?? 0)",
                                    icon: "arrow.turn.up.right",
                                    color: .orange
                                )

                                StatCard(
                                    title: "平均信頼度",
                                    value: String(format: "%.0f%%", averageTrustScore() * 100),
                                    icon: "checkmark.shield",
                                    color: .purple
                                )
                            }
                        }
                        .padding()
                        .background(Color(.systemGray6))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
                .padding()
            }
            .navigationTitle("メッシュネットワーク")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(item: $showingPeerDetail) { peer in
                PeerDetailView(peer: peer)
            }
        }
    }

    private func hopColor(_ hopCount: Int) -> Color {
        switch hopCount {
        case 1: return .green
        case 2: return .blue
        case 3: return .orange
        case 4: return .red
        default: return .gray
        }
    }

    private func averageTrustScore() -> Float {
        let scores = meshManager.connectedPeers.map { $0.capability.score }
        guard !scores.isEmpty else { return 0 }
        return scores.reduce(0, +) / Float(scores.count) / 100
    }

    private func getDeviceName() -> String {
        #if os(iOS)
        return UIDevice.current.name
        #else
        return "My Device"
        #endif
    }

    private func getLocalCapability() -> ComputeCapability {
        return ComputeCapability(
            hasLocalLLM: ChatModeManager.shared.isModeAvailable(.local),
            modelName: AppState.shared.currentModelName,
            freeMemoryGB: getAvailableMemory(),
            batteryLevel: getBatteryLevel(),
            isCharging: isCharging()
        )
    }

    private func getAvailableMemory() -> Float {
        let totalMemory = Float(ProcessInfo.processInfo.physicalMemory)
        return totalMemory / (1024 * 1024 * 1024)  // GB
    }

    private func getBatteryLevel() -> Float? {
        #if os(iOS)
        UIDevice.current.isBatteryMonitoringEnabled = true
        let level = UIDevice.current.batteryLevel
        return level >= 0 ? level : nil
        #else
        return nil
        #endif
    }

    private func isCharging() -> Bool {
        #if os(iOS)
        UIDevice.current.isBatteryMonitoringEnabled = true
        return UIDevice.current.batteryState == .charging || UIDevice.current.batteryState == .full
        #else
        return false
        #endif
    }
}

// MARK: - Node Card

struct NodeCard: View {
    let name: String
    let capability: ComputeCapability
    let isLocal: Bool
    let hopCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(name)
                        .font(.headline)

                    if let modelName = capability.modelName {
                        Text(modelName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                if isLocal {
                    Image(systemName: "star.fill")
                        .foregroundStyle(.yellow)
                }
            }

            Divider()

            // Capabilities
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                CapabilityBadge(
                    icon: "cpu",
                    label: capability.hasLocalLLM ? "LLM搭載" : "LLMなし",
                    color: capability.hasLocalLLM ? .green : .gray
                )

                CapabilityBadge(
                    icon: "memorychip",
                    label: String(format: "%.1fGB", capability.freeMemoryGB),
                    color: .blue
                )

                if let battery = capability.batteryLevel {
                    CapabilityBadge(
                        icon: capability.isCharging ? "battery.100.bolt" : "battery.100",
                        label: String(format: "%.0f%%", battery * 100),
                        color: batteryColor(battery)
                    )
                }

                if let cores = capability.cpuCores {
                    CapabilityBadge(
                        icon: "cpu.fill",
                        label: "\(cores) cores",
                        color: .purple
                    )
                }
            }

            // Score
            if !isLocal {
                HStack {
                    Text("スコア:")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Text(String(format: "%.0f", capability.score))
                        .font(.caption.bold())
                        .foregroundStyle(.green)
                }
                .padding(.top, 4)
            }
        }
        .padding()
        .background(isLocal ? Color.blue.opacity(0.1) : Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isLocal ? Color.blue : Color.clear, lineWidth: 2)
        )
    }

    private func batteryColor(_ level: Float) -> Color {
        if level > 0.5 {
            return .green
        } else if level > 0.2 {
            return .orange
        } else {
            return .red
        }
    }
}

struct CapabilityBadge: View {
    let icon: String
    let label: String
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
            Text(label)
        }
        .font(.caption2)
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(color.opacity(0.1))
        .foregroundStyle(color)
        .clipShape(Capsule())
    }
}

// MARK: - Stat Card

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)

            Text(value)
                .font(.title.bold())

            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Peer Detail View

struct PeerDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let peer: MeshPeer

    var body: some View {
        NavigationView {
            List {
                Section("基本情報") {
                    HStack {
                        Text("デバイス名")
                        Spacer()
                        Text(peer.name)
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Text("ホップ数")
                        Spacer()
                        Text("\(peer.hopCount)")
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Text("最終確認")
                        Spacer()
                        Text(peer.lastSeen.formatted(date: .omitted, time: .shortened))
                            .foregroundStyle(.secondary)
                    }
                }

                Section("計算能力") {
                    HStack {
                        Text("ローカルLLM")
                        Spacer()
                        Text(peer.capability.hasLocalLLM ? "搭載" : "なし")
                            .foregroundStyle(peer.capability.hasLocalLLM ? .green : .secondary)
                    }

                    if let modelName = peer.capability.modelName {
                        HStack {
                            Text("モデル")
                            Spacer()
                            Text(modelName)
                                .foregroundStyle(.secondary)
                        }
                    }

                    HStack {
                        Text("空きメモリ")
                        Spacer()
                        Text(String(format: "%.1f GB", peer.capability.freeMemoryGB))
                            .foregroundStyle(.secondary)
                    }

                    if let battery = peer.capability.batteryLevel {
                        HStack {
                            Text("バッテリー")
                            Spacer()
                            HStack(spacing: 4) {
                                Text(String(format: "%.0f%%", battery * 100))
                                if peer.capability.isCharging {
                                    Image(systemName: "bolt.fill")
                                        .foregroundStyle(.yellow)
                                }
                            }
                            .foregroundStyle(.secondary)
                        }
                    }

                    if let cores = peer.capability.cpuCores {
                        HStack {
                            Text("CPUコア数")
                            Spacer()
                            Text("\(cores)")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("スコア") {
                    HStack {
                        Text("計算能力スコア")
                        Spacer()
                        Text(String(format: "%.0f", peer.capability.score))
                            .font(.headline)
                            .foregroundStyle(.green)
                    }
                }
            }
            .navigationTitle("ピア詳細")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") {
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    MeshTopologyView()
}
