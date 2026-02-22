import Foundation
import Network
import Combine

/// Mesh P2P Manager - Core of the Offline Intelligence Grid
/// Manages mesh network topology, routing, and intelligent peer selection
@MainActor
final class MeshP2PManager: InferenceBackend, ObservableObject {
    static let shared = MeshP2PManager()

    // MARK: - Published Properties

    @Published private(set) var connectedPeers: [MeshPeer] = []
    @Published private(set) var routingTable: [String: RouteEntry] = [:]
    @Published private(set) var isGenerating = false

    // MARK: - Private Properties

    private var localBackend: LocalBackend?
    private var privateServerManager: PrivateServerManager?
    private var p2pBackend: P2PBackend?

    private let deviceIdKey = "mesh_device_id"
    private var pendingRequests: [UUID: CheckedContinuation<P2PMeshForwardResponse, Error>] = [:]

    // MARK: - InferenceBackend Protocol

    var backendId: String { "mesh_p2p" }
    var displayName: String { "Mesh" }
    var tokenCost: Int { 0 }  // Free - community-powered

    var isReady: Bool {
        // Ready if we have local LLM OR connected peers with LLM
        return (localBackend?.isReady ?? false) || !availableLLMPeers.isEmpty
    }

    // MARK: - Initialization

    private init() {
        setupComponents()
    }

    private func setupComponents() {
        // LocalBackend is created by AppState, will be set later
        localBackend = nil
        privateServerManager = PrivateServerManager.shared
        p2pBackend = P2PBackend()
    }

    /// Set the local backend (called by AppState)
    func setLocalBackend(_ backend: LocalBackend?) {
        self.localBackend = backend
    }

    // MARK: - Mesh Mode Control

    /// Enable mesh mode - start server and begin peer discovery
    func enableMeshMode() async throws {
        guard let privateServer = privateServerManager,
              let localBackend = localBackend else {
            throw InferenceError.notReady
        }

        // Configure and start P2P server
        privateServer.configure(backend: localBackend)
        try await privateServer.start()

        // Start browsing for peers
        p2pBackend?.startBrowsing()

        // Start periodic peer discovery broadcast
        startPeerDiscovery()
    }

    /// Disable mesh mode
    func disableMeshMode() {
        privateServerManager?.stop()
        p2pBackend?.stopBrowsing()
        connectedPeers.removeAll()
        routingTable.removeAll()
    }

    // MARK: - Peer Discovery

    private func startPeerDiscovery() {
        // Discover nearby peers
        Task {
            while true {
                await discoverPeers()
                try? await Task.sleep(nanoseconds: 10_000_000_000) // 10 seconds
            }
        }
    }

    private func discoverPeers() async {
        guard let p2pBackend = p2pBackend else { return }

        // Get available servers from P2P backend
        let availableServers = p2pBackend.availableServers

        for server in availableServers {
            // Skip if already connected
            if connectedPeers.contains(where: { $0.id == server.id }) {
                continue
            }

            // Try to connect
            do {
                try await privateServerManager?.connectToServerPeer(server)

                // Add to connected peers (will be updated with actual capability later)
                let peer = MeshPeer(
                    id: server.id,
                    name: server.name,
                    endpoint: server.endpoint,
                    capability: ComputeCapability(
                        hasLocalLLM: false,
                        freeMemoryGB: 0,
                        batteryLevel: nil,
                        isCharging: false
                    ),
                    hopCount: 1,
                    lastSeen: Date()
                )
                connectedPeers.append(peer)
                updateRoutingTable()

            } catch {
                print("[Mesh P2P] Failed to connect to \(server.name): \(error)")
            }
        }
    }

    /// Update routing table based on connected peers
    private func updateRoutingTable() {
        routingTable.removeAll()

        // Add direct connections (1 hop)
        for peer in connectedPeers {
            routingTable[peer.id] = RouteEntry(
                deviceId: peer.id,
                nextHop: peer.id,
                hopCount: 1,
                lastUpdated: Date()
            )
        }

        // TODO: Add multi-hop routes from peer announcements
    }

    // MARK: - Inference Generation

    func generate(
        messages: [Message],
        systemPrompt: String,
        settings: ModelSettings,
        onToken: @escaping (String) -> Void
    ) async throws -> String {
        isGenerating = true
        defer { isGenerating = false }

        let startTime = Date()

        // Strategy 1: Try local LLM first
        if let localBackend = localBackend, localBackend.isReady {
            do {
                let response = try await localBackend.generate(
                    messages: messages,
                    systemPrompt: systemPrompt,
                    settings: settings,
                    onToken: onToken
                )

                let latency = Int(Date().timeIntervalSince(startTime) * 1000)
                _ = NetworkMetadata(
                    sourceDeviceId: getDeviceId(),
                    networkType: .local,
                    hopCount: 0,
                    processingDeviceName: "Local",
                    routePath: [getDeviceId()],
                    latencyMs: latency
                )

                return response
            } catch {
                print("[Mesh P2P] Local inference failed: \(error)")
                // Fall through to mesh network
            }
        }

        // Strategy 2: Use mesh network
        let (response, _) = try await forwardToMesh(
            messages: messages,
            systemPrompt: systemPrompt,
            settings: settings,
            onToken: onToken
        )

        return response
    }

    func stopGeneration() {
        isGenerating = false
        localBackend?.stopGeneration()
    }

    // MARK: - Mesh Forwarding

    private func forwardToMesh(
        messages: [Message],
        systemPrompt: String,
        settings: ModelSettings,
        onToken: @escaping (String) -> Void
    ) async throws -> (response: String, metadata: NetworkMetadata) {
        // Select best peer
        guard let bestPeer = selectBestPeer() else {
            throw InferenceError.notReady
        }

        // Build mesh forward request
        let inferenceRequest = P2PInferenceRequest(
            messages: messages,
            systemPrompt: systemPrompt,
            settings: settings,
            clientId: getDeviceId(),
            signature: nil
        )

        let meshRequest = P2PMeshForwardRequest(
            requestId: UUID(),
            originalRequest: inferenceRequest,
            visitedNodes: [getDeviceId()],
            maxHops: 5
        )

        // Send to best peer and wait for response
        let meshResponse = try await sendMeshRequest(meshRequest, to: bestPeer)

        if let error = meshResponse.error {
            throw InferenceError.serverError(500, error)
        }

        // Stream the response (simulate streaming for now)
        for char in meshResponse.response {
            onToken(String(char))
            try? await Task.sleep(nanoseconds: 1_000_000) // 1ms per char
        }

        let metadata = NetworkMetadata(
            sourceDeviceId: getDeviceId(),
            networkType: .p2pMesh,
            hopCount: meshResponse.hopCount,
            processingDeviceName: meshResponse.processingDeviceName,
            routePath: meshResponse.routePath,
            latencyMs: nil
        )

        return (meshResponse.response, metadata)
    }

    private func sendMeshRequest(_ request: P2PMeshForwardRequest, to peer: MeshPeer) async throws -> P2PMeshForwardResponse {
        // Get connection to peer from PrivateServerManager
        guard let privateServer = privateServerManager,
              let connection = privateServer.serverPeerConnections[peer.id] else {
            throw InferenceError.networkError("No connection to peer")
        }

        // Encode and send request
        let envelope = P2PEnvelope(
            type: .meshForwardRequest,
            payload: try JSONEncoder().encode(request)
        )
        let data = try JSONEncoder().encode(envelope)
        var framedData = data
        framedData.append(contentsOf: [0x0A])

        // Send request
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: framedData, completion: .contentProcessed { error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            })
        }

        // Wait for response
        return try await withCheckedThrowingContinuation { continuation in
            pendingRequests[request.requestId] = continuation

            // Timeout after 60 seconds
            Task {
                try? await Task.sleep(nanoseconds: 60_000_000_000)
                if pendingRequests[request.requestId] != nil {
                    pendingRequests.removeValue(forKey: request.requestId)
                    continuation.resume(throwing: InferenceError.networkError("Request timeout"))
                }
            }
        }
    }

    /// Handle incoming mesh response
    func handleMeshResponse(_ response: P2PMeshForwardResponse) {
        guard let continuation = pendingRequests.removeValue(forKey: response.requestId) else {
            return
        }
        continuation.resume(returning: response)
    }

    // MARK: - Peer Selection

    /// Select best peer for inference based on capability score
    private func selectBestPeer() -> MeshPeer? {
        let llmPeers = availableLLMPeers
        guard !llmPeers.isEmpty else { return nil }

        // Score and select best peer
        return llmPeers.max { peer1, peer2 in
            calculatePeerScore(peer1) < calculatePeerScore(peer2)
        }
    }

    /// Calculate peer selection score (higher is better)
    private func calculatePeerScore(_ peer: MeshPeer) -> Float {
        var score: Float = 0

        // Base score from compute capability
        score += peer.capability.score

        // Penalty for hop count
        score -= Float(peer.hopCount) * 10

        // Bonus for recent activity
        let timeSinceLastSeen = Date().timeIntervalSince(peer.lastSeen)
        if timeSinceLastSeen < 60 {
            score += 20
        } else if timeSinceLastSeen < 300 {
            score += 10
        }

        return score
    }

    /// Get peers with local LLM capability
    private var availableLLMPeers: [MeshPeer] {
        connectedPeers.filter { $0.capability.hasLocalLLM }
    }

    /// Find peer with specific capability (used by SpeculativeBackend)
    func findPeerWith(capability: PeerCapability) async -> MeshPeer? {
        let matchingPeers = connectedPeers.filter { peer in
            switch capability {
            case .inference:
                return peer.capability.hasLocalLLM
            case .largeModel:
                // Large model (7B+) - requires significant free memory (>4GB)
                return peer.capability.hasLocalLLM && peer.capability.freeMemoryGB > 4.0
            case .mediumModel:
                // Medium model (3-7B) - moderate memory (2-4GB)
                return peer.capability.hasLocalLLM && peer.capability.freeMemoryGB > 2.0 && peer.capability.freeMemoryGB <= 4.0
            case .smallModel:
                // Small model (1-3B) - low memory (<2GB)
                return peer.capability.hasLocalLLM && peer.capability.freeMemoryGB <= 2.0
            }
        }

        // Sort by latency/score and return best
        return matchingPeers.max { calculatePeerScore($0) < calculatePeerScore($1) }
    }

    // MARK: - Helpers

    private func getDeviceId() -> String {
        if let existingId = UserDefaults.standard.string(forKey: deviceIdKey) {
            return existingId
        }
        let newId = UUID().uuidString
        UserDefaults.standard.set(newId, forKey: deviceIdKey)
        return newId
    }
}

// MARK: - Supporting Types

/// Mesh network peer
struct MeshPeer: Identifiable {
    let id: String
    let name: String
    let endpoint: NWEndpoint
    var capability: ComputeCapability
    var hopCount: Int
    var lastSeen: Date
}

/// Routing table entry
struct RouteEntry {
    let deviceId: String
    let nextHop: String
    let hopCount: Int
    let lastUpdated: Date
}

/// Peer capability classification for speculative decoding
enum PeerCapability {
    case inference      // Any inference capability
    case largeModel     // 7B+ model (high memory)
    case mediumModel    // 3-7B model (moderate memory)
    case smallModel     // 1-3B model (low memory)
}

// MARK: - Note
// PrivateServerManager.serverPeerConnections is now internal for mesh network access
