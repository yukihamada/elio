import Foundation
import Network
import CryptoKit

// MARK: - Distributed Query Protocol Types

/// Query broadcast message sent across the P2P network
struct DistributedQuery: Codable, Identifiable {
    let id: UUID
    let anonymizedQuery: String
    let requesterHash: String  // SHA256 of device ID
    let timestamp: Date
    let ttl: TimeInterval      // seconds
    let maxResponses: Int

    var isExpired: Bool {
        Date().timeIntervalSince(timestamp) > ttl
    }
}

/// Response from a peer that processed the query
struct DistributedResponse: Codable, Identifiable {
    let id: UUID
    let queryId: UUID
    let responseText: String
    let responderHash: String  // SHA256 of responder device ID
    let confidence: Double     // 0.0 - 1.0
    let modelInfo: String
    let processingTimeMs: Int
}

/// Aggregated result from multiple distributed responses
struct AggregatedResult {
    let queryId: UUID
    let responses: [DistributedResponse]
    let bestResponse: DistributedResponse?
    let totalPeersQueried: Int
    let totalResponses: Int
    let averageConfidence: Double
    let totalTimeMs: Int
}

/// State of a distributed query lifecycle
enum QueryState: Equatable {
    case preparing
    case broadcasting
    case collecting(received: Int, total: Int)
    case aggregating
    case complete
    case timeout
    case cancelled
}

// MARK: - DistributedQueryManager

/// Distributes anonymous queries across the P2P mesh network and collects parallel responses.
///
/// Workflow:
/// 1. Receive user query
/// 2. Strip PII via PIIFilter
/// 3. Broadcast to ledger servers (EBR >= 1000)
/// 4. Ledger servers fan out to connected peers
/// 5. Collect responses with timeout
/// 6. Aggregate and return best result
@MainActor
final class DistributedQueryManager: ObservableObject {

    static let shared = DistributedQueryManager()

    // MARK: - Published Properties

    @Published private(set) var activeQueries: [UUID: QueryState] = [:]
    @Published private(set) var queryResults: [UUID: [DistributedResponse]] = [:]
    @Published private(set) var isLedgerServerActive = false
    @Published private(set) var queriesProcessed: Int = 0

    // MARK: - Private Properties

    private let meshManager = MeshP2PManager.shared
    private let privateServerManager = PrivateServerManager.shared
    private let tokenManager = TokenManager.shared

    /// Minimum EBR (Earned Balance Ratio) to act as ledger server
    private let ledgerServerMinEBR: Int = 1000

    /// Pending response continuations keyed by query ID
    private var pendingCollectors: [UUID: ResponseCollector] = [:]

    /// Seen query IDs for deduplication
    private var seenQueryIds: Set<UUID> = []

    /// Maximum seen IDs to retain (prevent unbounded growth)
    private let maxSeenIds = 10_000

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    // MARK: - Initialization

    init() {}

    // MARK: - Submit Query

    /// Submit a query for distributed processing across the P2P network.
    ///
    /// - Parameters:
    ///   - query: The raw user query (PII will be stripped)
    ///   - maxPeers: Maximum number of peer responses to collect
    ///   - timeoutSeconds: Timeout in seconds for response collection
    /// - Returns: Aggregated result from multiple peers
    func submitQuery(
        _ query: String,
        maxPeers: Int = 5,
        timeoutSeconds: Double = 10
    ) async -> AggregatedResult {
        let queryId = UUID()
        let startTime = Date()

        activeQueries[queryId] = .preparing
        queryResults[queryId] = []

        // 1. Strip PII from query
        let (anonymized, _) = PIIFilter.filter(query)

        // 2. Build distributed query
        let requesterHash = sha256Hash(DeviceIdentityManager.shared.deviceId)
        let distributedQuery = DistributedQuery(
            id: queryId,
            anonymizedQuery: anonymized,
            requesterHash: requesterHash,
            timestamp: Date(),
            ttl: timeoutSeconds,
            maxResponses: maxPeers
        )

        // 3. Register for deduplication
        markSeen(queryId)

        // 4. Broadcast to peers
        activeQueries[queryId] = .broadcasting
        let peersQueried = await broadcastQuery(distributedQuery)

        if peersQueried == 0 {
            // No peers available - return empty result
            activeQueries[queryId] = .complete
            return AggregatedResult(
                queryId: queryId,
                responses: [],
                bestResponse: nil,
                totalPeersQueried: 0,
                totalResponses: 0,
                averageConfidence: 0,
                totalTimeMs: Int(Date().timeIntervalSince(startTime) * 1000)
            )
        }

        // 5. Collect responses with timeout
        activeQueries[queryId] = .collecting(received: 0, total: maxPeers)
        let responses = await collectResponses(
            queryId: queryId,
            maxResponses: maxPeers,
            timeout: timeoutSeconds
        )

        // 6. Aggregate
        activeQueries[queryId] = .aggregating
        let result = aggregate(
            queryId: queryId,
            responses: responses,
            peersQueried: peersQueried,
            startTime: startTime
        )

        activeQueries[queryId] = .complete
        return result
    }

    /// Cancel an in-progress query
    func cancelQuery(_ queryId: UUID) {
        activeQueries[queryId] = .cancelled
        pendingCollectors[queryId]?.cancel()
        pendingCollectors.removeValue(forKey: queryId)
    }

    // MARK: - Handle Incoming Query (Responder Side)

    /// Process an incoming distributed query from the network.
    /// Returns a response if this device can answer, nil otherwise.
    func handleIncomingQuery(_ query: DistributedQuery) async -> DistributedResponse? {
        // Deduplication check
        guard !seenQueryIds.contains(query.id) else {
            return nil
        }
        markSeen(query.id)

        // TTL check
        guard !query.isExpired else {
            return nil
        }

        // Attempt local inference
        let startTime = Date()

        guard let localBackend = resolveLocalBackend(),
              localBackend.isReady else {
            return nil
        }

        do {
            var resultText = ""
            let response = try await localBackend.generate(
                messages: [Message(role: .user, content: query.anonymizedQuery)],
                systemPrompt: "Answer concisely.",
                settings: ModelSettings.default,
                onToken: { token in
                    resultText += token
                }
            )

            let elapsed = Int(Date().timeIntervalSince(startTime) * 1000)
            let responderHash = sha256Hash(DeviceIdentityManager.shared.deviceId)

            queriesProcessed += 1

            return DistributedResponse(
                id: UUID(),
                queryId: query.id,
                responseText: response,
                responderHash: responderHash,
                confidence: estimateConfidence(response),
                modelInfo: localBackend.displayName,
                processingTimeMs: elapsed
            )
        } catch {
            print("[DistributedQuery] Local inference failed: \(error)")
            return nil
        }
    }

    /// Handle an incoming response for a query we originated
    func handleIncomingResponse(_ response: DistributedResponse) {
        guard let collector = pendingCollectors[response.queryId] else {
            return
        }

        // Append to results
        var current = queryResults[response.queryId] ?? []
        current.append(response)
        queryResults[response.queryId] = current

        activeQueries[response.queryId] = .collecting(
            received: current.count,
            total: collector.maxResponses
        )

        collector.addResponse(response)
    }

    // MARK: - Ledger Server Mode

    /// Start ledger server mode (requires EBR >= 1000).
    /// Ledger servers receive queries and fan them out to connected peers.
    func startLedgerServer() async throws {
        guard EBRTokenGate.shared.isEligible else {
            throw DistributedQueryError.insufficientEBR(
                required: ledgerServerMinEBR,
                current: Int(EBRTokenGate.shared.ebrBalance)
            )
        }

        isLedgerServerActive = true
        print("[DistributedQuery] Ledger server started (EBR: \(tokenManager.totalEarned))")
    }

    /// Stop ledger server mode
    func stopLedgerServer() {
        isLedgerServerActive = false
        print("[DistributedQuery] Ledger server stopped")
    }

    /// Fan out an incoming query to all connected peers (ledger server duty)
    func fanOutQuery(_ query: DistributedQuery) async {
        guard isLedgerServerActive else { return }
        guard !query.isExpired else { return }

        let peers = meshManager.connectedPeers
        for peer in peers {
            guard let connection = privateServerManager.serverPeerConnections[peer.id] else {
                continue
            }
            await sendDistributedQuery(query, via: connection)
        }
    }

    // MARK: - Broadcasting

    /// Broadcast query to connected peers. Returns number of peers contacted.
    private func broadcastQuery(_ query: DistributedQuery) async -> Int {
        let peers = meshManager.connectedPeers
        guard !peers.isEmpty else { return 0 }

        var sent = 0
        for peer in peers.prefix(query.maxResponses) {
            guard let connection = privateServerManager.serverPeerConnections[peer.id] else {
                continue
            }
            await sendDistributedQuery(query, via: connection)
            sent += 1
        }
        return sent
    }

    private func sendDistributedQuery(_ query: DistributedQuery, via connection: NWConnection) async {
        do {
            let payload = try encoder.encode(query)
            let envelope = P2PEnvelope(
                type: .distributedQuery,
                payload: payload
            )
            let data = try encoder.encode(envelope)
            var framedData = data
            framedData.append(contentsOf: [0x0A])  // newline delimiter

            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                connection.send(content: framedData, completion: .contentProcessed { error in
                    if let error = error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume()
                    }
                })
            }
        } catch {
            print("[DistributedQuery] Failed to send query: \(error)")
        }
    }

    func sendDistributedResponse(_ response: DistributedResponse, via connection: NWConnection) async {
        do {
            let payload = try encoder.encode(response)
            let envelope = P2PEnvelope(
                type: .distributedResponse,
                payload: payload
            )
            let data = try encoder.encode(envelope)
            var framedData = data
            framedData.append(contentsOf: [0x0A])

            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                connection.send(content: framedData, completion: .contentProcessed { error in
                    if let error = error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume()
                    }
                })
            }
        } catch {
            print("[DistributedQuery] Failed to send response: \(error)")
        }
    }

    // MARK: - Response Collection

    /// Collect responses until maxResponses or timeout, whichever comes first.
    private func collectResponses(
        queryId: UUID,
        maxResponses: Int,
        timeout: TimeInterval
    ) async -> [DistributedResponse] {
        let collector = ResponseCollector(queryId: queryId, maxResponses: maxResponses)
        pendingCollectors[queryId] = collector

        defer {
            pendingCollectors.removeValue(forKey: queryId)
        }

        // Race: collect vs timeout
        return await withTaskGroup(of: [DistributedResponse]?.self) { group in
            // Task 1: Wait for all responses
            group.addTask { @MainActor in
                await collector.waitForCompletion()
                return collector.responses
            }

            // Task 2: Timeout
            group.addTask { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                collector.cancel()
                return nil
            }

            // Return first non-nil result
            for await result in group {
                if let responses = result {
                    group.cancelAll()
                    return responses
                }
            }

            // Fallback: return whatever we have
            return collector.responses
        }
    }

    // MARK: - Aggregation

    private func aggregate(
        queryId: UUID,
        responses: [DistributedResponse],
        peersQueried: Int,
        startTime: Date
    ) -> AggregatedResult {
        let totalTimeMs = Int(Date().timeIntervalSince(startTime) * 1000)

        let avgConfidence: Double
        if responses.isEmpty {
            avgConfidence = 0
        } else {
            avgConfidence = responses.map(\.confidence).reduce(0, +) / Double(responses.count)
        }

        // Best response = highest confidence, then shortest processing time as tiebreak
        let best = responses.max { a, b in
            if a.confidence != b.confidence {
                return a.confidence < b.confidence
            }
            return a.processingTimeMs > b.processingTimeMs
        }

        return AggregatedResult(
            queryId: queryId,
            responses: responses,
            bestResponse: best,
            totalPeersQueried: peersQueried,
            totalResponses: responses.count,
            averageConfidence: avgConfidence,
            totalTimeMs: totalTimeMs
        )
    }

    // MARK: - Helpers

    private func sha256Hash(_ input: String) -> String {
        let data = Data(input.utf8)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Heuristic confidence estimate based on response length and structure
    private func estimateConfidence(_ response: String) -> Double {
        let length = response.count
        guard length > 0 else { return 0.0 }

        var confidence: Double = 0.5

        // Longer, more detailed responses tend to be higher quality
        if length > 200 { confidence += 0.15 }
        if length > 500 { confidence += 0.1 }

        // Penalize very short responses
        if length < 20 { confidence -= 0.2 }

        return min(max(confidence, 0.0), 1.0)
    }

    private func resolveLocalBackend() -> (any InferenceBackend)? {
        // MeshP2PManager holds a reference to the local backend;
        // we access it through the mesh manager's generate path.
        // For direct access, return the mesh manager itself if it is ready.
        return meshManager.isReady ? meshManager : nil
    }

    private func markSeen(_ queryId: UUID) {
        seenQueryIds.insert(queryId)
        // Prune oldest entries if set grows too large
        if seenQueryIds.count > maxSeenIds {
            // Remove approximately half to amortize cleanup cost
            let removeCount = maxSeenIds / 2
            for id in seenQueryIds.prefix(removeCount) {
                seenQueryIds.remove(id)
            }
        }
    }
}

// MARK: - ResponseCollector

/// Internal actor-like collector that accumulates responses for a single query.
@MainActor
private final class ResponseCollector {
    let queryId: UUID
    let maxResponses: Int
    private(set) var responses: [DistributedResponse] = []
    private var continuation: CheckedContinuation<Void, Never>?
    private var isCancelled = false

    init(queryId: UUID, maxResponses: Int) {
        self.queryId = queryId
        self.maxResponses = maxResponses
    }

    func addResponse(_ response: DistributedResponse) {
        guard !isCancelled else { return }
        responses.append(response)

        if responses.count >= maxResponses {
            continuation?.resume()
            continuation = nil
        }
    }

    func waitForCompletion() async {
        if responses.count >= maxResponses || isCancelled { return }

        await withCheckedContinuation { cont in
            if responses.count >= maxResponses || isCancelled {
                cont.resume()
            } else {
                continuation = cont
            }
        }
    }

    func cancel() {
        isCancelled = true
        continuation?.resume()
        continuation = nil
    }
}

// MARK: - Errors

enum DistributedQueryError: Error, LocalizedError {
    case insufficientEBR(required: Int, current: Int)
    case noPeersAvailable
    case queryTimeout(UUID)
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .insufficientEBR(let required, let current):
            return "Insufficient EBR to act as ledger server (required: \(required), current: \(current))"
        case .noPeersAvailable:
            return "No peers available for distributed query"
        case .queryTimeout(let id):
            return "Query \(id) timed out"
        case .encodingFailed:
            return "Failed to encode distributed query message"
        }
    }
}

// MARK: - P2PMessageType Extension (requires adding to existing enum)

// NOTE: The following message types must be added to P2PMessageType in PrivateServerManager.swift:
//   case distributedQuery
//   case distributedResponse
//
// And handled in PrivateServerManager.processMessage(_:from:) to route to DistributedQueryManager.
