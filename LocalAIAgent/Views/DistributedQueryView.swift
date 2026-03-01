import SwiftUI

// MARK: - Distributed Query View

/// Distributed query status display + ledger server management.
/// Three sections: ledger server status, query execution, result display.
struct DistributedQueryView: View {
    @StateObject private var queryManager = DistributedQueryViewModel.shared
    @StateObject private var ledgerServer = LedgerServerViewModel.shared
    @StateObject private var tokenGate = EBRTokenGate.shared

    @State private var queryText = ""
    @State private var currentResult: DistributedQueryUIResult?
    @State private var showIndividualResponses = false
    @State private var copiedToClipboard = false

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Section 1: Ledger Server Status
                    ledgerServerSection

                    // Section 2: Distributed Query Execution
                    queryExecutionSection

                    // Section 3: Results
                    if let result = currentResult {
                        resultSection(result)
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Distributed Query")
            #if !targetEnvironment(macCatalyst)
            .navigationBarTitleDisplayMode(.inline)
            #endif
        }
    }

    // MARK: - Section 1: Ledger Server Status

    private var ledgerServerSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader(
                title: "台帳サーバー",
                icon: "server.rack",
                color: .blue
            )

            if tokenGate.walletAddress == nil {
                // Wallet not connected
                walletNotConnectedCard
            } else if !tokenGate.isEligible {
                // Wallet connected but insufficient EBR
                insufficientBalanceCard
            } else {
                // Eligible: show server toggle and stats
                eligibleServerCard
            }
        }
    }

    private var walletNotConnectedCard: some View {
        VStack(spacing: 16) {
            Image(systemName: "wallet.pass")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)

            Text("ウォレット未接続")
                .font(.headline)

            Text("台帳サーバーを運用するにはPhantom Walletの接続が必要です")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button(action: connectPhantomWallet) {
                HStack(spacing: 8) {
                    Image(systemName: "link")
                    Text("Connect Phantom Wallet")
                        .font(.subheadline.weight(.semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    LinearGradient(
                        colors: [.purple, .blue],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private var insufficientBalanceCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "diamond.fill")
                    .foregroundStyle(.yellow)
                Text("EBR残高")
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text("\(tokenGate.ebrBalance) EBR")
                    .font(.system(.body, design: .monospaced).weight(.semibold))
            }

            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.caption)
                Text("1,000 EBR required. Current: \(tokenGate.ebrBalance)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Progress toward threshold
            let progress = min(Double(tokenGate.ebrBalance) / Double(EBRTokenGate.minimumBalance), 1.0)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.gray.opacity(0.2))
                        .frame(height: 6)

                    RoundedRectangle(cornerRadius: 4)
                        .fill(
                            LinearGradient(
                                colors: [.orange, .yellow],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geo.size.width * progress, height: 6)
                }
            }
            .frame(height: 6)

            Button(action: openGetEBR) {
                HStack(spacing: 4) {
                    Text("Get EBR")
                        .font(.caption.weight(.semibold))
                    Image(systemName: "arrow.right")
                        .font(.caption)
                }
                .foregroundStyle(.blue)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private var eligibleServerCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            // EBR balance + toggle
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Image(systemName: "diamond.fill")
                            .foregroundStyle(.yellow)
                            .font(.caption)
                        Text("\(tokenGate.ebrBalance) EBR")
                            .font(.system(.subheadline, design: .monospaced).weight(.semibold))
                    }

                    Text(tokenGate.walletAddress.map { shortenAddress($0) } ?? "")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Toggle("", isOn: Binding(
                    get: { ledgerServer.isActive },
                    set: { newValue in
                        withAnimation(.easeInOut) {
                            if newValue {
                                ledgerServer.start()
                            } else {
                                ledgerServer.stop()
                            }
                        }
                    }
                ))
                .labelsHidden()
                .tint(.green)
            }

            if ledgerServer.isActive {
                // Active server stats
                LazyVGrid(
                    columns: [GridItem(.flexible()), GridItem(.flexible())],
                    spacing: 12
                ) {
                    serverStatCard(
                        title: "処理クエリ",
                        value: "\(ledgerServer.processedQueries)",
                        icon: "doc.text.magnifyingglass",
                        color: .blue
                    )
                    serverStatCard(
                        title: "獲得トークン",
                        value: "+\(ledgerServer.earnedTokens)",
                        icon: "plus.circle.fill",
                        color: .green
                    )
                    serverStatCard(
                        title: "接続クライアント",
                        value: "\(ledgerServer.connectedClients)",
                        icon: "person.2.fill",
                        color: .purple
                    )
                    serverStatCard(
                        title: "稼働時間",
                        value: formattedUptime(ledgerServer.uptimeSeconds),
                        icon: "clock.fill",
                        color: .orange
                    )
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemBackground))
        )
    }

    // MARK: - Section 2: Query Execution

    private var queryExecutionSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader(
                title: "分散クエリ",
                icon: "magnifyingglass",
                color: .green
            )

            // Text input
            VStack(alignment: .leading, spacing: 8) {
                TextField("ネットワークに質問...", text: $queryText, axis: .vertical)
                    .font(.system(.body, design: .monospaced))
                    .lineLimit(3...6)
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color(.tertiarySystemBackground))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                    )

                // PII redaction notice
                if queryManager.redactedItemCount > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "shield.checkered")
                        Text("\(queryManager.redactedItemCount) items redacted")
                            .font(.caption)
                    }
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 4)
                }
            }

            // Ask the Network button
            Button(action: executeQuery) {
                HStack(spacing: 8) {
                    if queryManager.phase == .idle {
                        Image(systemName: "network")
                    } else {
                        ProgressView()
                            .tint(.white)
                    }
                    Text("Ask the Network")
                        .font(.subheadline.weight(.semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    LinearGradient(
                        colors: queryText.isEmpty
                            ? [.gray.opacity(0.5), .gray.opacity(0.3)]
                            : [Color.green, Color.green.opacity(0.8)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .disabled(queryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                      || queryManager.phase != .idle)

            // Query phase status
            if queryManager.phase != .idle {
                queryPhaseView
            }
        }
    }

    private var queryPhaseView: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch queryManager.phase {
            case .idle:
                EmptyView()

            case .preparing:
                phaseRow(
                    icon: "shield.checkered",
                    text: "Filtering personal info...",
                    color: .orange,
                    showSpinner: true
                )

            case .broadcasting(let peerCount):
                phaseRow(
                    icon: "antenna.radiowaves.left.and.right",
                    text: "Sending to \(peerCount) peers...",
                    color: .blue,
                    showSpinner: true
                )

            case .collecting(let received, let total):
                VStack(alignment: .leading, spacing: 6) {
                    phaseRow(
                        icon: "arrow.down.circle",
                        text: "Received \(received)/\(total) responses",
                        color: .purple,
                        showSpinner: true
                    )

                    // Progress bar
                    let progress = total > 0 ? Double(received) / Double(total) : 0
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.gray.opacity(0.2))
                                .frame(height: 6)

                            RoundedRectangle(cornerRadius: 4)
                                .fill(
                                    LinearGradient(
                                        colors: [.purple, .blue],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: geo.size.width * progress, height: 6)
                                .animation(.easeInOut, value: progress)
                        }
                    }
                    .frame(height: 6)
                }

            case .aggregating:
                phaseRow(
                    icon: "arrow.triangle.merge",
                    text: "Merging responses...",
                    color: .cyan,
                    showSpinner: true
                )

            case .complete:
                phaseRow(
                    icon: "checkmark.circle.fill",
                    text: "Complete",
                    color: .green,
                    showSpinner: false
                )

            case .error(let message):
                phaseRow(
                    icon: "exclamationmark.triangle.fill",
                    text: message,
                    color: .red,
                    showSpinner: false
                )
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.tertiarySystemBackground))
        )
    }

    // MARK: - Section 3: Result Display

    private func resultSection(_ result: DistributedQueryUIResult) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader(
                title: "クエリ結果",
                icon: "text.page.fill",
                color: .cyan
            )

            // Summary
            Text(result.summary)
                .font(.system(.body, design: .monospaced))
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.secondarySystemBackground))
                )

            // Consensus score
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Agreement")
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    Text("\(Int(result.consensusScore * 100))%")
                        .font(.system(.subheadline, design: .monospaced).weight(.bold))
                        .foregroundStyle(consensusColor(result.consensusScore))
                }

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.gray.opacity(0.2))
                            .frame(height: 8)

                        RoundedRectangle(cornerRadius: 4)
                            .fill(
                                LinearGradient(
                                    colors: consensusGradient(result.consensusScore),
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: geo.size.width * result.consensusScore, height: 8)
                    }
                }
                .frame(height: 8)
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.secondarySystemBackground))
            )

            // Individual responses (collapsible)
            DisclosureGroup(
                isExpanded: $showIndividualResponses
            ) {
                VStack(spacing: 12) {
                    ForEach(result.individualResponses) { response in
                        individualResponseRow(response)
                    }
                }
                .padding(.top, 8)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "list.bullet.rectangle")
                    Text("個別回答 (\(result.individualResponses.count))")
                        .font(.subheadline.weight(.medium))
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.secondarySystemBackground))
            )

            // Action buttons
            HStack(spacing: 12) {
                Button(action: copyResult) {
                    HStack(spacing: 6) {
                        Image(systemName: copiedToClipboard ? "checkmark" : "doc.on.doc")
                        Text(copiedToClipboard ? "Copied" : "Copy Result")
                            .font(.subheadline.weight(.medium))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color(.tertiarySystemBackground))
                    )
                    .foregroundStyle(.primary)
                }

                Button(action: useInChat) {
                    HStack(spacing: 6) {
                        Image(systemName: "bubble.left.fill")
                        Text("Use in Chat")
                            .font(.subheadline.weight(.medium))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        LinearGradient(
                            colors: [.blue, .blue.opacity(0.8)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
        }
    }

    private func individualResponseRow(_ response: IndividualResponse) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                // Quality score (star bar)
                HStack(spacing: 2) {
                    ForEach(0..<5) { index in
                        Image(systemName: index < Int(response.qualityScore * 5) ? "star.fill" : "star")
                            .font(.caption2)
                            .foregroundStyle(index < Int(response.qualityScore * 5) ? .yellow : .gray.opacity(0.3))
                    }
                }

                Spacer()

                // Outlier marker
                if response.isOutlier {
                    HStack(spacing: 2) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption2)
                        Text("outlier")
                            .font(.caption2)
                    }
                    .foregroundStyle(.orange)
                }
            }

            // Responder hash (anonymous, truncated)
            HStack(spacing: 4) {
                Image(systemName: "person.fill.questionmark")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(shortenHash(response.responderHash))
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            // Model info + processing time
            HStack {
                if let model = response.modelInfo {
                    Text(model)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.1))
                        .foregroundStyle(.blue)
                        .clipShape(Capsule())
                }

                Spacer()

                Text("\(response.processingTimeMs)ms")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(.tertiarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(
                    response.isOutlier ? Color.orange.opacity(0.4) : Color.clear,
                    lineWidth: 1
                )
        )
    }

    // MARK: - Shared Components

    private func sectionHeader(title: String, icon: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(color)
            Text(title)
                .font(.headline)
        }
    }

    private func phaseRow(icon: String, text: String, color: Color, showSpinner: Bool) -> some View {
        HStack(spacing: 10) {
            if showSpinner {
                ProgressView()
                    .tint(color)
            } else {
                Image(systemName: icon)
                    .foregroundStyle(color)
            }

            Text(text)
                .font(.system(.subheadline, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }

    private func serverStatCard(title: String, value: String, icon: String, color: Color) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)

            Text(value)
                .font(.system(.title3, design: .monospaced).bold())

            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(.tertiarySystemBackground))
        )
    }

    // MARK: - Actions

    private func executeQuery() {
        let trimmed = queryText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        Task {
            let result = await queryManager.execute(query: trimmed)
            withAnimation(.easeInOut) {
                currentResult = result
            }
        }
    }

    private func connectPhantomWallet() {
        guard let url = tokenGate.phantomConnectURL() else { return }
        #if os(iOS)
        UIApplication.shared.open(url)
        #endif
    }

    private func openGetEBR() {
        guard let url = URL(string: "https://elio.love/ebr") else { return }
        #if os(iOS)
        UIApplication.shared.open(url)
        #endif
    }

    private func copyResult() {
        guard let result = currentResult else { return }
        #if os(iOS)
        UIPasteboard.general.string = result.summary
        #endif
        withAnimation(.easeInOut) {
            copiedToClipboard = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation(.easeInOut) {
                copiedToClipboard = false
            }
        }
    }

    private func useInChat() {
        guard let result = currentResult else { return }
        // Post notification so ChatView can pick up the text
        NotificationCenter.default.post(
            name: .distributedQueryResultInsert,
            object: nil,
            userInfo: ["text": result.summary]
        )
    }

    // MARK: - Helpers

    private func shortenAddress(_ address: String) -> String {
        guard address.count > 10 else { return address }
        let prefix = address.prefix(6)
        let suffix = address.suffix(4)
        return "\(prefix)...\(suffix)"
    }

    private func shortenHash(_ hash: String) -> String {
        guard hash.count > 12 else { return hash }
        let prefix = hash.prefix(8)
        let suffix = hash.suffix(4)
        return "\(prefix)...\(suffix)"
    }

    private func formattedUptime(_ seconds: Int) -> String {
        if seconds < 60 {
            return "\(seconds)s"
        } else if seconds < 3600 {
            return "\(seconds / 60)m"
        } else {
            let hours = seconds / 3600
            let minutes = (seconds % 3600) / 60
            return "\(hours)h \(minutes)m"
        }
    }

    private func consensusColor(_ score: Double) -> Color {
        if score >= 0.8 { return .green }
        if score >= 0.5 { return .orange }
        return .red
    }

    private func consensusGradient(_ score: Double) -> [Color] {
        if score >= 0.8 { return [.green, .green.opacity(0.7)] }
        if score >= 0.5 { return [.orange, .yellow] }
        return [.red, .orange]
    }
}

// MARK: - Notification Name

extension Notification.Name {
    static let distributedQueryResultInsert = Notification.Name("distributedQueryResultInsert")
}

// MARK: - Query Phase

/// Represents the current phase of a distributed query lifecycle.
enum QueryPhase: Equatable {
    case idle
    case preparing
    case broadcasting(peerCount: Int)
    case collecting(received: Int, total: Int)
    case aggregating
    case complete
    case error(String)
}

// MARK: - Aggregated Result

/// Final merged result from a distributed query across the network.
struct DistributedQueryUIResult {
    let summary: String
    let consensusScore: Double
    let individualResponses: [IndividualResponse]
}

// MARK: - Individual Response

/// A single response from one peer in the distributed query.
struct IndividualResponse: Identifiable {
    let id = UUID()
    let responderHash: String
    let qualityScore: Double
    let modelInfo: String?
    let processingTimeMs: Int
    let isOutlier: Bool
}

// MARK: - Distributed Query Manager

/// Manages distributed query lifecycle: PII filtering, broadcast, collection, aggregation.
@MainActor
final class DistributedQueryViewModel: ObservableObject {
    static let shared = DistributedQueryViewModel()

    @Published private(set) var phase: QueryPhase = .idle
    @Published private(set) var redactedItemCount: Int = 0

    private init() {}

    /// Execute a distributed query across the P2P network.
    func execute(query: String) async -> DistributedQueryUIResult? {
        phase = .preparing

        // PII filter pass
        let (filtered, redactedCount) = PIIFilter.filter(query, level: .standard)
        redactedItemCount = redactedCount

        // Broadcast to peers
        let peers = MeshP2PManager.shared.connectedPeers
        let peerCount = peers.count
        guard peerCount > 0 else {
            phase = .error("No peers connected")
            return nil
        }

        phase = .broadcasting(peerCount: peerCount)

        // Simulate collection (real implementation dispatches via MeshP2PManager)
        var responses: [IndividualResponse] = []
        let peerArray = Array(peers)
        for i in 0..<peerCount {
            try? await Task.sleep(nanoseconds: 300_000_000) // 0.3s per peer
            phase = .collecting(received: i + 1, total: peerCount)
            // Placeholder response
            responses.append(IndividualResponse(
                responderHash: peerArray[i].id,
                qualityScore: Double.random(in: 0.5...1.0),
                modelInfo: peerArray[i].capability.modelName,
                processingTimeMs: Int.random(in: 200...2000),
                isOutlier: Double.random(in: 0...1) < 0.1
            ))
        }

        phase = .aggregating
        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s aggregation

        // Build aggregated result
        let avgQuality = responses.map(\.qualityScore).reduce(0, +) / Double(responses.count)
        let result = DistributedQueryUIResult(
            summary: "Distributed answer for: \(filtered)",
            consensusScore: avgQuality,
            individualResponses: responses
        )

        phase = .complete
        return result
    }

    /// Reset to idle state.
    func reset() {
        phase = .idle
        redactedItemCount = 0
    }
}

// MARK: - Ledger Server

/// Manages the local ledger server that processes distributed queries for EBR rewards.
@MainActor
final class LedgerServerViewModel: ObservableObject {
    static let shared = LedgerServerViewModel()

    @Published private(set) var isActive: Bool = false
    @Published private(set) var processedQueries: Int = 0
    @Published private(set) var earnedTokens: Int = 0
    @Published private(set) var connectedClients: Int = 0
    @Published private(set) var uptimeSeconds: Int = 0

    private var uptimeTimer: Timer?

    private init() {}

    /// Start the ledger server. Requires EBR >= 1000.
    func start() {
        guard EBRTokenGate.shared.isEligible else { return }
        isActive = true
        uptimeSeconds = 0
        startUptimeTimer()
    }

    /// Stop the ledger server and reset counters.
    func stop() {
        isActive = false
        uptimeTimer?.invalidate()
        uptimeTimer = nil
        connectedClients = 0
    }

    private func startUptimeTimer() {
        uptimeTimer?.invalidate()
        uptimeTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.uptimeSeconds += 1
            }
        }
    }
}

// MARK: - Preview

#Preview {
    DistributedQueryView()
        .preferredColorScheme(.dark)
}
