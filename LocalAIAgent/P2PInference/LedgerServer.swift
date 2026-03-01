import Foundation
import Network
#if os(iOS)
import UIKit
#endif

// MARK: - Ledger Server

/// EBR token-gated ledger server that accepts queries from other Elio clients,
/// distributes them to connected peers, aggregates responses, and records token rewards.
///
/// Requirements:
/// - EBR balance >= 1,000 to activate (verified via `EBRTokenGate`)
/// - Advertises on Bonjour as `_elio-ledger._tcp` (separate from regular P2P `_eliochat._tcp`)
/// - Listens on port 8766 (regular P2P uses 8765)
/// - Periodic re-verification every 30 minutes; auto-deactivates if balance drops below threshold
@MainActor
final class LedgerServer: ObservableObject {
    static let shared = LedgerServer()

    // MARK: - Constants

    private let serviceType = "_elio-ledger._tcp"
    private let serviceDomain = "local."
    private let defaultPort: UInt16 = 8766
    private static let revalidationInterval: TimeInterval = 30 * 60 // 30 minutes

    // MARK: - Published Properties

    @Published var isActive: Bool = false
    @Published var ebrBalance: Int = 0
    @Published var queriesServed: Int = 0
    @Published var tokensEarned: Int = 0
    @Published var connectedClients: Int = 0
    @Published var uptime: TimeInterval = 0
    @Published var errorMessage: String?

    // MARK: - Private Properties

    private var listener: NWListener?
    private var connections: [NWConnection] = []
    private var processedQueryIds: Set<UUID> = []
    private var activationTime: Date?
    private var uptimeTimer: Timer?
    private var revalidationTimer: Timer?
    private let tokenManager = TokenManager.shared
    private let tokenGate = EBRTokenGate.shared
    private let aggregator = ResponseAggregator()

    // Peer connections for query distribution (peerId -> connection)
    private var peerConnections: [String: NWConnection] = [:]

    // Pending query continuations: queryId -> continuation
    private var pendingQueries: [UUID: CheckedContinuation<[DistributedResponse], Never>] = [:]

    // Collected responses per query
    private var collectedResponses: [UUID: [DistributedResponse]] = [:]

    // Statistics persistence
    private let statsKey = "ledger_server_stats"

    private init() {
        loadStats()
    }

    // MARK: - Activation / Deactivation

    /// Activate the ledger server after verifying EBR balance >= 1,000.
    func activate() async throws {
        guard !isActive else { throw LedgerError.alreadyActive }

        // 1. Verify EBR balance
        guard let verification = await tokenGate.verifyBalance() else {
            throw LedgerError.insufficientEBR(balance: Int(tokenGate.ebrBalance))
        }

        guard verification.isEligible else {
            throw LedgerError.insufficientEBR(balance: Int(verification.balance))
        }

        ebrBalance = Int(verification.balance)

        // 2. Start NWListener on port 8766
        do {
            let parameters = NWParameters.tcp
            parameters.allowLocalEndpointReuse = true

            listener = try NWListener(using: parameters, on: NWEndpoint.Port(rawValue: defaultPort)!)

            // 3. Bonjour advertisement with TXT record
            var txtRecord = NWTXTRecord()
            txtRecord["elioId"] = DeviceIdentityManager.shared.elioId
            txtRecord["ebrBalance"] = String(ebrBalance)
            txtRecord["modelCapability"] = currentModelCapability()
            txtRecord["availableMemoryGB"] = String(format: "%.1f", availableMemoryGB())

            listener?.service = NWListener.Service(
                name: deviceName(),
                type: serviceType,
                domain: serviceDomain,
                txtRecord: txtRecord
            )

            listener?.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in
                    self?.handleListenerState(state)
                }
            }

            listener?.newConnectionHandler = { [weak self] connection in
                Task { @MainActor in
                    self?.handleNewConnection(connection)
                }
            }

            listener?.start(queue: .main)

            // 4. Mark active
            isActive = true
            activationTime = Date()
            startUptimeTimer()
            startRevalidationTimer()

            print("[LedgerServer] Activated on port \(defaultPort)")

        } catch {
            errorMessage = "Failed to start ledger server: \(error.localizedDescription)"
            throw LedgerError.networkError(error.localizedDescription)
        }
    }

    /// Deactivate the ledger server, stopping Bonjour advertisement and listener.
    func deactivate() {
        // 1. Stop Bonjour advertisement and listener
        listener?.cancel()
        listener = nil

        // 2. Close all client connections
        for connection in connections {
            connection.cancel()
        }
        connections.removeAll()
        peerConnections.removeAll()

        // 3. Cancel pending queries
        for (_, continuation) in pendingQueries {
            continuation.resume(returning: [])
        }
        pendingQueries.removeAll()
        collectedResponses.removeAll()

        // 4. Stop timers
        uptimeTimer?.invalidate()
        uptimeTimer = nil
        revalidationTimer?.invalidate()
        revalidationTimer = nil

        // 5. Update state
        isActive = false
        connectedClients = 0
        activationTime = nil
        processedQueryIds.removeAll()

        saveStats()
        print("[LedgerServer] Deactivated")
    }

    // MARK: - Listener State

    private func handleListenerState(_ state: NWListener.State) {
        switch state {
        case .ready:
            print("[LedgerServer] Listener ready and advertising")
        case .failed(let error):
            errorMessage = "Ledger server error: \(error.localizedDescription)"
            deactivate()
        case .cancelled:
            isActive = false
        default:
            break
        }
    }

    // MARK: - Connection Handling

    private func handleNewConnection(_ connection: NWConnection) {
        connections.append(connection)
        connectedClients = connections.count

        connection.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                switch state {
                case .ready:
                    print("[LedgerServer] Client connected")
                case .failed, .cancelled:
                    self?.removeConnection(connection)
                default:
                    break
                }
            }
        }

        connection.start(queue: .main)
        receiveMessage(from: connection)
    }

    private func removeConnection(_ connection: NWConnection) {
        connections.removeAll { $0 === connection }

        // Also remove from peer connections if present
        peerConnections = peerConnections.filter { $0.value !== connection }

        connectedClients = connections.count
    }

    // MARK: - Message Receiving

    private func receiveMessage(from connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            Task { @MainActor in
                guard let self = self else { return }

                if let data = data, !data.isEmpty {
                    await self.processIncomingData(data, from: connection)
                }

                if let error = error {
                    print("[LedgerServer] Receive error: \(error)")
                    self.removeConnection(connection)
                    return
                }

                if isComplete {
                    self.removeConnection(connection)
                } else {
                    self.receiveMessage(from: connection)
                }
            }
        }
    }

    // MARK: - Query Processing

    private func processIncomingData(_ data: Data, from connection: NWConnection) async {
        // Try to decode as a LedgerEnvelope
        guard let envelope = try? JSONDecoder().decode(LedgerEnvelope.self, from: data) else {
            sendError(to: connection, message: "Invalid envelope format")
            return
        }

        switch envelope.type {
        case .query:
            guard let query = try? JSONDecoder().decode(DistributedQuery.self, from: envelope.payload) else {
                sendError(to: connection, message: "Invalid query format")
                return
            }
            await handleClientQuery(query, connection: connection)

        case .peerResponse:
            guard let response = try? JSONDecoder().decode(DistributedResponse.self, from: envelope.payload) else {
                return
            }
            handlePeerResponse(response)

        case .peerRegister:
            guard let registration = try? JSONDecoder().decode(LedgerPeerRegistration.self, from: envelope.payload) else {
                return
            }
            handlePeerRegistration(registration, connection: connection)

        case .queryResult:
            break // Server does not process its own results
        }
    }

    /// Handle a client query: validate, distribute to peers, aggregate, and respond.
    func handleClientQuery(_ query: DistributedQuery, connection: NWConnection) async {
        // 1. TTL check
        guard !query.isExpired else {
            sendError(to: connection, message: "Query TTL expired")
            return
        }

        // 2. Duplicate check
        guard !processedQueryIds.contains(query.id) else {
            sendError(to: connection, message: "Duplicate query")
            return
        }
        processedQueryIds.insert(query.id)

        // Prevent unbounded growth of processed IDs
        if processedQueryIds.count > 10_000 {
            processedQueryIds.removeAll()
        }

        // 3. Distribute to connected peers and collect responses with timeout
        let responses = await distributeAndCollect(query: query)

        // 4. Aggregate responses using ResponseAggregator
        let enriched = await aggregator.aggregate(responses)

        // 5. Build and send result back to the client
        let ledgerResult = LedgerQueryResult(
            queryId: query.id,
            summary: enriched.summary,
            totalPeers: enriched.totalPeers,
            avgConfidence: enriched.avgConfidence,
            consensusScore: enriched.consensusScore,
            processingTimeMs: enriched.processingTimeMs,
            rankedResponses: enriched.responses.map { ranked in
                LedgerRankedEntry(
                    peerId: ranked.response.responderHash,
                    content: ranked.response.responseText,
                    rank: ranked.rank,
                    qualityScore: ranked.qualityScore,
                    isOutlier: ranked.isOutlier
                )
            }
        )

        do {
            let resultPayload = try JSONEncoder().encode(ledgerResult)
            let envelope = LedgerEnvelope(type: .queryResult, payload: resultPayload)
            let data = try JSONEncoder().encode(envelope)
            sendData(data, to: connection)
        } catch {
            sendError(to: connection, message: "Failed to encode result")
        }

        // 6. Record stats
        queriesServed += 1
        let earned = max(responses.count, 1)
        tokensEarned += earned
        tokenManager.earn(earned, reason: .p2pServing)
        saveStats()
    }

    // MARK: - Query Distribution

    /// Distribute a query to all connected peers and collect responses with a timeout.
    private func distributeAndCollect(query: DistributedQuery) async -> [DistributedResponse] {
        let queryId = query.id
        collectedResponses[queryId] = []

        // Build envelope for peers
        guard let queryPayload = try? JSONEncoder().encode(query),
              let envelopeData = try? JSONEncoder().encode(
                  LedgerEnvelope(type: .query, payload: queryPayload)
              ) else {
            return []
        }

        // Send to all peer connections in parallel
        let activePeers = peerConnections
        await withTaskGroup(of: Void.self) { group in
            for (_, conn) in activePeers {
                group.addTask { @MainActor in
                    self.sendData(envelopeData, to: conn)
                }
            }
        }

        // Wait for responses with timeout
        let timeoutNs = UInt64(query.ttl * 1_000_000_000)
        let responses: [DistributedResponse] = await withCheckedContinuation { continuation in
            pendingQueries[queryId] = continuation

            // Schedule timeout
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: timeoutNs)
                // If still pending, resolve with whatever we have
                if let cont = self.pendingQueries.removeValue(forKey: queryId) {
                    let collected = self.collectedResponses.removeValue(forKey: queryId) ?? []
                    cont.resume(returning: collected)
                }
            }
        }

        return responses
    }

    /// Handle an incoming peer response and add it to the collection.
    private func handlePeerResponse(_ response: DistributedResponse) {
        let queryId = response.queryId

        guard pendingQueries[queryId] != nil else { return }

        collectedResponses[queryId, default: []].append(response)

        // If we've collected from all peers, resolve early
        if collectedResponses[queryId]?.count == peerConnections.count {
            if let continuation = pendingQueries.removeValue(forKey: queryId) {
                let collected = collectedResponses.removeValue(forKey: queryId) ?? []
                continuation.resume(returning: collected)
            }
        }
    }

    /// Handle a new peer registering itself as available for query distribution.
    private func handlePeerRegistration(_ registration: LedgerPeerRegistration, connection: NWConnection) {
        peerConnections[registration.peerId] = connection
        connectedClients = connections.count
        print("[LedgerServer] Peer registered: \(registration.peerName) (\(registration.peerId))")
    }

    // MARK: - Data Transmission

    private func sendData(_ data: Data, to connection: NWConnection) {
        var framedData = data
        framedData.append(contentsOf: [0x0A]) // newline delimiter

        connection.send(content: framedData, completion: .contentProcessed { error in
            if let error = error {
                print("[LedgerServer] Send error: \(error)")
            }
        })
    }

    private func sendError(to connection: NWConnection, message: String) {
        let error = P2PErrorResponse(error: message)
        if let data = try? JSONEncoder().encode(error) {
            sendData(data, to: connection)
        }
    }

    // MARK: - Timers

    private func startUptimeTimer() {
        uptimeTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self, let start = self.activationTime else { return }
                self.uptime = Date().timeIntervalSince(start)
            }
        }
    }

    /// Periodically re-verify EBR balance. Auto-deactivate if below threshold.
    private func startRevalidationTimer() {
        revalidationTimer = Timer.scheduledTimer(
            withTimeInterval: Self.revalidationInterval,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self = self, self.isActive else { return }
                await self.revalidateBalance()
            }
        }
    }

    private func revalidateBalance() async {
        guard let verification = await tokenGate.forceRefresh() else {
            print("[LedgerServer] Revalidation failed — deactivating")
            deactivate()
            return
        }

        ebrBalance = Int(verification.balance)

        if !verification.isEligible {
            print("[LedgerServer] EBR balance dropped below threshold (\(verification.balance)) — deactivating")
            errorMessage = "EBR balance below minimum (\(verification.balance)/\(EBRTokenGate.minimumBalance))"
            deactivate()
        }
    }

    // MARK: - Helpers

    private func deviceName() -> String {
        #if os(iOS)
        return UIDevice.current.name
        #else
        return Host.current().localizedName ?? "Elio Ledger Server"
        #endif
    }

    private func currentModelCapability() -> String {
        let capability = PrivateServerManager.shared.getComputeCapability()
        return capability.modelName ?? (capability.hasLocalLLM ? "local" : "none")
    }

    private func availableMemoryGB() -> Float {
        let totalBytes = Float(ProcessInfo.processInfo.physicalMemory)
        let totalGB = totalBytes / (1024 * 1024 * 1024)

        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }

        if result == KERN_SUCCESS {
            let usedGB = Float(info.resident_size) / (1024 * 1024 * 1024)
            return max(0, totalGB - usedGB)
        }
        return 1.0
    }

    // MARK: - Stats Persistence

    private func loadStats() {
        guard let data = UserDefaults.standard.data(forKey: statsKey),
              let stats = try? JSONDecoder().decode(LedgerStats.self, from: data) else {
            return
        }
        queriesServed = stats.queriesServed
        tokensEarned = stats.tokensEarned
    }

    private func saveStats() {
        let stats = LedgerStats(
            queriesServed: queriesServed,
            tokensEarned: tokensEarned,
            lastSaved: Date()
        )
        if let data = try? JSONEncoder().encode(stats) {
            UserDefaults.standard.set(data, forKey: statsKey)
        }
    }
}

// MARK: - Ledger Protocol Types

/// Envelope for ledger server protocol messages.
struct LedgerEnvelope: Codable {
    let type: LedgerMessageType
    let payload: Data
}

enum LedgerMessageType: String, Codable {
    case query
    case queryResult
    case peerResponse
    case peerRegister
}

/// Aggregated result returned to the querying client.
struct LedgerQueryResult: Codable {
    let queryId: UUID
    let summary: String
    let totalPeers: Int
    let avgConfidence: Double
    let consensusScore: Double
    let processingTimeMs: Int
    let rankedResponses: [LedgerRankedEntry]
}

/// A single ranked entry in the ledger result.
struct LedgerRankedEntry: Codable {
    let peerId: String
    let content: String
    let rank: Int
    let qualityScore: Double
    let isOutlier: Bool
}

/// Registration message from a peer joining the ledger's distribution pool.
struct LedgerPeerRegistration: Codable {
    let peerId: String
    let peerName: String
    let modelName: String?
    let availableMemoryGB: Float
}

/// Persisted ledger server statistics.
struct LedgerStats: Codable {
    let queriesServed: Int
    let tokensEarned: Int
    let lastSaved: Date
}

// MARK: - Errors

enum LedgerError: Error, LocalizedError {
    case insufficientEBR(balance: Int)
    case alreadyActive
    case networkError(String)

    var errorDescription: String? {
        switch self {
        case .insufficientEBR(let balance):
            return "Insufficient EBR balance (\(balance)/\(EBRTokenGate.minimumBalance)). Minimum 1,000 EBR required."
        case .alreadyActive:
            return "Ledger server is already active"
        case .networkError(let message):
            return "Ledger network error: \(message)"
        }
    }
}
