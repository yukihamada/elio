#if targetEnvironment(macCatalyst)
import SwiftUI
import Charts

// MARK: - DePIN Dashboard View

/// Mac-exclusive DePIN node dashboard showing real-time stats,
/// earnings, model status, network info, and node controls.
struct DePINDashboardView: View {
    @ObservedObject private var serverManager = PrivateServerManager.shared
    @ObservedObject private var tokenManager = TokenManager.shared
    @ObservedObject private var ledgerServer = LedgerServer.shared
    @ObservedObject private var nodeReputation = NodeReputation.shared
    @StateObject private var dashboardState = DePINDashboardState()
    @State private var animateGradient = false
    @State private var showingWalletSetup = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Node Status Hero
                nodeStatusCard

                // Earnings Overview
                earningsOverviewCard

                // Stats Grid
                statsGrid

                // Model Status
                modelStatusCard

                // Network Status
                networkStatusCard

                // Reputation Score
                reputationCard

                // Wallet & Rewards
                walletCard
            }
            .padding(24)
        }
        .background(Color.chatBackgroundDynamic)
        .navigationTitle("DePIN Node")
        .onAppear {
            withAnimation(.easeInOut(duration: 3).repeatForever(autoreverses: true)) {
                animateGradient = true
            }
            dashboardState.startUpdating()
        }
        .onDisappear {
            dashboardState.stopUpdating()
        }
        .sheet(isPresented: $showingWalletSetup) {
            PhantomWalletSetupView()
        }
    }

    // MARK: - Node Status Hero Card

    private var nodeStatusCard: some View {
        VStack(spacing: 20) {
            ZStack {
                // Outer glow ring
                Circle()
                    .stroke(
                        .linearGradient(
                            colors: isNodeActive
                                ? [.green.opacity(0.6), .mint.opacity(0.3)]
                                : [.gray.opacity(0.3), .gray.opacity(0.1)],
                            startPoint: animateGradient ? .topLeading : .bottomTrailing,
                            endPoint: animateGradient ? .bottomTrailing : .topLeading
                        ),
                        lineWidth: 3
                    )
                    .frame(width: 100, height: 100)
                    .shadow(color: isNodeActive ? .green.opacity(0.3) : .clear, radius: 20)

                Circle()
                    .fill(
                        .linearGradient(
                            colors: isNodeActive
                                ? [.green, .mint]
                                : [.gray.opacity(0.5), .gray.opacity(0.3)],
                            startPoint: animateGradient ? .topLeading : .bottomTrailing,
                            endPoint: animateGradient ? .bottomTrailing : .topLeading
                        )
                    )
                    .frame(width: 80, height: 80)
                    .shadow(color: isNodeActive ? .green.opacity(0.4) : .clear, radius: 15)

                Image(systemName: isNodeActive ? "cpu.fill" : "cpu")
                    .font(.system(size: 32, weight: .medium))
                    .foregroundStyle(.white)
                    .symbolEffect(.pulse, isActive: isNodeActive)
            }

            VStack(spacing: 6) {
                Text(isNodeActive ? "DePIN Node Active" : "DePIN Node Inactive")
                    .font(.system(size: 24, weight: .bold, design: .rounded))

                Text(isNodeActive
                     ? "Earning tokens by serving AI inference"
                     : "Start your node to earn tokens")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)

                if isNodeActive, let uptime = formattedUptime {
                    Text("Uptime: \(uptime)")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(.green)
                        .padding(.top, 2)
                }
            }

            // Start/Stop toggle
            Button {
                Task {
                    await toggleNode()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: isNodeActive ? "stop.fill" : "play.fill")
                        .font(.system(size: 14, weight: .bold))
                    Text(isNodeActive ? "Stop Node" : "Start Node")
                        .font(.system(size: 15, weight: .semibold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(
                            .linearGradient(
                                colors: isNodeActive ? [.red, .orange] : [.green, .mint],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                )
                .shadow(color: (isNodeActive ? Color.red : Color.green).opacity(0.3), radius: 8, y: 4)
            }
            .buttonStyle(.plain)
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .stroke(Color.glassBorder, lineWidth: 0.5)
        )
    }

    // MARK: - Earnings Overview

    private var earningsOverviewCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            ModernSectionHeader(
                title: "Earnings",
                icon: "chart.line.uptrend.xyaxis",
                gradient: [.green, .mint]
            )

            // Hourly earnings chart
            if !dashboardState.hourlyEarnings.isEmpty {
                Chart(dashboardState.hourlyEarnings) { entry in
                    BarMark(
                        x: .value("Hour", entry.hour),
                        y: .value("Tokens", entry.tokens)
                    )
                    .foregroundStyle(
                        .linearGradient(
                            colors: [.green, .mint],
                            startPoint: .bottom,
                            endPoint: .top
                        )
                    )
                    .cornerRadius(4)
                }
                .frame(height: 150)
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 6)) { value in
                        AxisValueLabel()
                            .font(.system(size: 10))
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisValueLabel()
                            .font(.system(size: 10))
                    }
                }
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "chart.bar.xaxis")
                        .font(.system(size: 32))
                        .foregroundStyle(.secondary)
                    Text("No earnings data yet")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .frame(height: 150)
                .frame(maxWidth: .infinity)
            }

            // Summary row
            HStack(spacing: 0) {
                earningsSummaryItem(
                    label: "Today",
                    value: "\(dashboardState.todayEarnings)",
                    icon: "sun.max.fill",
                    color: .orange
                )

                Divider().frame(height: 40)

                earningsSummaryItem(
                    label: "This Week",
                    value: "\(tokenManager.weeklyEarnings())",
                    icon: "calendar",
                    color: .blue
                )

                Divider().frame(height: 40)

                earningsSummaryItem(
                    label: "All Time",
                    value: "\(tokenManager.totalEarned)",
                    icon: "infinity",
                    color: .purple
                )
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.cardBackground)
                .shadow(color: .black.opacity(0.06), radius: 12, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.subtleSeparator, lineWidth: 0.5)
        )
    }

    private func earningsSummaryItem(label: String, value: String, icon: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(color)
            Text(value)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .monospacedDigit()
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Stats Grid

    private var statsGrid: some View {
        LazyVGrid(columns: [
            GridItem(.flexible()),
            GridItem(.flexible()),
            GridItem(.flexible()),
            GridItem(.flexible())
        ], spacing: 12) {
            statTile(
                icon: "bolt.fill",
                value: "\(ledgerServer.queriesServed + serverManager.todayRequestsServed)",
                label: "Queries Served",
                gradient: [.purple, .pink]
            )

            statTile(
                icon: "bitcoinsign.circle.fill",
                value: "\(tokenManager.balance)",
                label: "Token Balance",
                gradient: [.yellow, .orange]
            )

            statTile(
                icon: "person.2.fill",
                value: "\(serverManager.connectedClients + ledgerServer.connectedClients)",
                label: "Connected Peers",
                gradient: [.blue, .cyan]
            )

            statTile(
                icon: "star.fill",
                value: String(format: "%.0f", nodeReputation.score),
                label: "Reputation",
                gradient: [.orange, .red]
            )
        }
    }

    private func statTile(icon: String, value: String, label: String, gradient: [Color]) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(
                    .linearGradient(colors: gradient, startPoint: .topLeading, endPoint: .bottomTrailing)
                )

            Text(value)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .monospacedDigit()

            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.cardBackground)
                .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.subtleSeparator, lineWidth: 0.5)
        )
    }

    // MARK: - Model Status Card

    private var modelStatusCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            ModernSectionHeader(
                title: "Model Status",
                icon: "brain",
                gradient: [.purple, .indigo]
            )

            HStack(spacing: 16) {
                // Model info
                VStack(alignment: .leading, spacing: 8) {
                    if let modelName = dashboardState.loadedModelName {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(.green)
                                .frame(width: 8, height: 8)
                            Text(modelName)
                                .font(.system(size: 15, weight: .semibold))
                        }

                        Text("Ready for inference")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    } else {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(.orange)
                                .frame(width: 8, height: 8)
                            Text("No model loaded")
                                .font(.system(size: 15, weight: .semibold))
                        }

                        Text("Load a model to start serving")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                // Device info
                VStack(alignment: .trailing, spacing: 4) {
                    let memoryGB = Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824
                    Text(String(format: "%.0f GB RAM", memoryGB))
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)

                    Text(DeviceTier.current.displayName)
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.cardBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.subtleSeparator, lineWidth: 0.5)
            )
        }
    }

    // MARK: - Network Status Card

    private var networkStatusCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            ModernSectionHeader(
                title: "Network",
                icon: "network",
                gradient: [.blue, .cyan]
            )

            VStack(spacing: 0) {
                networkRow(
                    icon: "antenna.radiowaves.left.and.right",
                    label: "P2P Server",
                    value: serverManager.isRunning ? "Active" : "Inactive",
                    valueColor: serverManager.isRunning ? .green : .secondary,
                    showDivider: true
                )

                networkRow(
                    icon: "server.rack",
                    label: "Ledger Server",
                    value: ledgerServer.isActive ? "Active" : "Inactive",
                    valueColor: ledgerServer.isActive ? .green : .secondary,
                    showDivider: true
                )

                networkRow(
                    icon: "person.2",
                    label: "LAN Peers",
                    value: "\(serverManager.connectedClients)",
                    valueColor: .primary,
                    showDivider: true
                )

                if let address = serverManager.serverAddress {
                    networkRow(
                        icon: "link",
                        label: "Address",
                        value: address,
                        valueColor: .primary,
                        showDivider: false
                    )
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.cardBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.subtleSeparator, lineWidth: 0.5)
            )
        }
    }

    private func networkRow(icon: String, label: String, value: String, valueColor: Color, showDivider: Bool) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 20)

                Text(label)
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)

                Spacer()

                Text(value)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(valueColor)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            if showDivider {
                Divider().padding(.leading, 48)
            }
        }
    }

    // MARK: - Reputation Card

    private var reputationCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            ModernSectionHeader(
                title: "Node Reputation",
                icon: "star.circle.fill",
                gradient: [.orange, .yellow]
            )

            HStack(spacing: 20) {
                // Score circle
                ZStack {
                    Circle()
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 8)
                        .frame(width: 80, height: 80)

                    Circle()
                        .trim(from: 0, to: nodeReputation.score / 100)
                        .stroke(
                            .linearGradient(
                                colors: reputationGradient,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            style: StrokeStyle(lineWidth: 8, lineCap: .round)
                        )
                        .frame(width: 80, height: 80)
                        .rotationEffect(.degrees(-90))

                    Text(String(format: "%.0f", nodeReputation.score))
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                }

                // Breakdown
                VStack(alignment: .leading, spacing: 6) {
                    reputationRow(label: "Uptime", value: String(format: "%.0f%%", nodeReputation.uptimePercentage))
                    reputationRow(label: "Avg Quality", value: String(format: "%.1f", nodeReputation.avgQuality))
                    reputationRow(label: "Success Rate", value: String(format: "%.0f%%", nodeReputation.successRate * 100))
                    reputationRow(label: "Avg Speed", value: String(format: "%.0fms", nodeReputation.avgResponseTimeMs))
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.cardBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.subtleSeparator, lineWidth: 0.5)
            )
        }
    }

    private func reputationRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
        }
    }

    private var reputationGradient: [Color] {
        let score = nodeReputation.score
        if score >= 80 { return [.green, .mint] }
        if score >= 60 { return [.yellow, .orange] }
        if score >= 40 { return [.orange, .red] }
        return [.red, .pink]
    }

    // MARK: - Wallet Card

    private var walletCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            ModernSectionHeader(
                title: "EBR Wallet",
                icon: "wallet.pass.fill",
                gradient: [.purple, .blue]
            )

            VStack(spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("EBR Balance")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)

                        Text("\(ledgerServer.ebrBalance)")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(
                                .linearGradient(
                                    colors: [.purple, .blue],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 4) {
                        Text("Tokens Earned")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)

                        Text("\(ledgerServer.tokensEarned)")
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.green)
                    }
                }

                if ledgerServer.ebrBalance < Int(EBRTokenGate.minimumBalance) {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text("Need \(Int(EBRTokenGate.minimumBalance)) EBR to activate Ledger Server")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(.orange.opacity(0.1))
                    )
                }

                Button {
                    showingWalletSetup = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "link.badge.plus")
                        Text("Connect Phantom Wallet")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .foregroundStyle(.purple)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(.purple.opacity(0.3), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.cardBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.subtleSeparator, lineWidth: 0.5)
            )
        }
    }

    // MARK: - Helpers

    private var isNodeActive: Bool {
        serverManager.isRunning || ledgerServer.isActive
    }

    private var formattedUptime: String? {
        let totalSeconds: TimeInterval
        if ledgerServer.isActive {
            totalSeconds = ledgerServer.uptime
        } else if serverManager.isRunning {
            totalSeconds = dashboardState.serverUptime
        } else {
            return nil
        }

        let hours = Int(totalSeconds) / 3600
        let minutes = (Int(totalSeconds) % 3600) / 60
        let seconds = Int(totalSeconds) % 60

        if hours > 0 {
            return String(format: "%dh %02dm %02ds", hours, minutes, seconds)
        }
        return String(format: "%dm %02ds", minutes, seconds)
    }

    private func toggleNode() async {
        if isNodeActive {
            serverManager.stop()
            ledgerServer.deactivate()
        } else {
            do {
                try await serverManager.start()
                // Also try to activate ledger if EBR is sufficient
                try? await ledgerServer.activate()
            } catch {
                // Server start failed - handled by serverManager
            }
        }
    }
}

// MARK: - Dashboard State

@MainActor
final class DePINDashboardState: ObservableObject {
    @Published var hourlyEarnings: [HourlyEarning] = []
    @Published var todayEarnings: Int = 0
    @Published var serverUptime: TimeInterval = 0
    @Published var loadedModelName: String?

    private var updateTimer: Timer?
    private var serverStartTime: Date?

    struct HourlyEarning: Identifiable {
        let id = UUID()
        let hour: String
        let tokens: Int
    }

    func startUpdating() {
        updateData()
        updateTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateData()
            }
        }
    }

    func stopUpdating() {
        updateTimer?.invalidate()
        updateTimer = nil
    }

    private func updateData() {
        // Update model name
        let appStateModelName = UserDefaults.standard.string(forKey: "lastUsedModel")
        if let modelId = appStateModelName {
            loadedModelName = ModelLoader.shared.getModelInfo(modelId)?.name
        }

        // Calculate today's earnings from transactions
        let calendar = Calendar.current
        let todayTransactions = TokenManager.shared.transactions.filter { tx in
            tx.type == .earned && calendar.isDateInToday(tx.timestamp)
        }
        todayEarnings = todayTransactions.reduce(0) { $0 + $1.amount }

        // Build hourly earnings for chart
        buildHourlyEarnings()

        // Update server uptime
        if PrivateServerManager.shared.isRunning {
            if serverStartTime == nil {
                serverStartTime = Date()
            }
            serverUptime = Date().timeIntervalSince(serverStartTime ?? Date())
        } else {
            serverStartTime = nil
            serverUptime = 0
        }
    }

    private func buildHourlyEarnings() {
        let calendar = Calendar.current
        let now = Date()
        var earnings: [HourlyEarning] = []

        // Last 12 hours
        for hoursAgo in stride(from: 11, through: 0, by: -1) {
            guard let hourStart = calendar.date(byAdding: .hour, value: -hoursAgo, to: now) else { continue }
            let hourEnd = calendar.date(byAdding: .hour, value: 1, to: hourStart) ?? now

            let hourTokens = TokenManager.shared.transactions.filter { tx in
                tx.type == .earned && tx.timestamp >= hourStart && tx.timestamp < hourEnd
            }.reduce(0) { $0 + $1.amount }

            let hourLabel = String(format: "%02d:00", calendar.component(.hour, from: hourStart))
            earnings.append(HourlyEarning(hour: hourLabel, tokens: hourTokens))
        }

        hourlyEarnings = earnings
    }
}

// MARK: - Phantom Wallet Setup

struct PhantomWalletSetupView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: "wallet.pass.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.purple)

                Text("Connect Phantom Wallet")
                    .font(.system(size: 22, weight: .bold))

                Text("Connect your Solana wallet to receive EBR token rewards for serving AI inference on the DePIN network.")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                VStack(alignment: .leading, spacing: 16) {
                    setupStep(number: 1, text: "Install Phantom browser extension or mobile app")
                    setupStep(number: 2, text: "Create or import a Solana wallet")
                    setupStep(number: 3, text: "Acquire EBR tokens (min 1,000 for Ledger Server)")
                    setupStep(number: 4, text: "Copy your wallet address and paste below")
                }
                .padding(20)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.cardBackground)
                )

                Text("EBR Token Mint:")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)

                Text("E1JxwaWRd8nw8vDdWMdqwdbXGBshqDcnTcinHzNMqg2Y")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.purple)
                    .textSelection(.enabled)

                Spacer()
            }
            .padding(24)
            .navigationTitle("Wallet Setup")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    private func setupStep(number: Int, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(Circle().fill(.purple))

            Text(text)
                .font(.system(size: 14))
                .foregroundStyle(.primary)
        }
    }
}

#endif
