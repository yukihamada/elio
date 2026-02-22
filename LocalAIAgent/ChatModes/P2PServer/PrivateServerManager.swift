import Foundation
import Network
import Combine
#if os(iOS)
import UIKit
#endif

/// Manages P2P inference server using Bonjour discovery and WebSocket
/// Users can share their device's inference capability and earn tokens
@MainActor
final class PrivateServerManager: ObservableObject {
    static let shared = PrivateServerManager()

    // MARK: - Constants

    private let serviceType = "_eliochat._tcp"
    private let serviceDomain = "local."
    private let defaultPort: UInt16 = 8765

    // MARK: - Published Properties

    @Published private(set) var isRunning = false
    @Published private(set) var connectedClients: Int = 0
    @Published private(set) var todayRequestsServed: Int = 0
    @Published private(set) var todayTokensEarned: Int = 0
    @Published private(set) var serverAddress: String?
    @Published private(set) var pairingCode: String = ""
    @Published var errorMessage: String?

    // MARK: - Private Properties

    private var listener: NWListener?
    private var bonjourService: NWListener.Service?
    private var connections: [NWConnection] = []
    private var localBackend: LocalBackend?
    private let tokenManager = TokenManager.shared

    // Statistics persistence
    private let statsKey = "p2p_server_stats"
    private var lastStatsDate: Date?

    // Mesh network support
    var serverPeerConnections: [String: NWConnection] = [:]  // deviceId -> connection (internal for MeshP2PManager)
    private var connectedPeers: [P2PPeerDiscovery] = []
    private let deviceIdKey = "p2p_device_id"

    private init() {
        loadTodayStats()
        loadOrGeneratePairingCode()
    }

    // MARK: - Server Control

    /// Configure the local backend for serving inference requests
    func configure(backend: LocalBackend) {
        self.localBackend = backend
    }

    /// Start the P2P server
    func start() async throws {
        guard !isRunning else { return }
        guard localBackend?.isReady == true else {
            throw P2PServerError.backendNotReady
        }

        do {
            // Create WebSocket listener
            let parameters = NWParameters.tcp
            parameters.allowLocalEndpointReuse = true

            listener = try NWListener(using: parameters, on: NWEndpoint.Port(rawValue: defaultPort)!)

            // Set up Bonjour advertising with pairing code in TXT record
            var txtRecord = NWTXTRecord()
            txtRecord["code"] = pairingCode
            txtRecord["version"] = "1"
            listener?.service = NWListener.Service(
                name: getDeviceName(),
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
            isRunning = true

            // Get server address
            updateServerAddress()

        } catch {
            errorMessage = "Failed to start server: \(error.localizedDescription)"
            throw P2PServerError.startFailed(error.localizedDescription)
        }
    }

    /// Stop the P2P server
    func stop() {
        listener?.cancel()
        listener = nil

        // Close all connections
        for connection in connections {
            connection.cancel()
        }
        connections.removeAll()

        isRunning = false
        connectedClients = 0
        serverAddress = nil
    }

    // MARK: - Connection Handling

    private func handleListenerState(_ state: NWListener.State) {
        switch state {
        case .ready:
            print("[P2P Server] Ready and advertising")
            updateServerAddress()
        case .failed(let error):
            errorMessage = "Server error: \(error.localizedDescription)"
            isRunning = false
        case .cancelled:
            isRunning = false
        default:
            break
        }
    }

    private func handleNewConnection(_ connection: NWConnection) {
        connections.append(connection)
        connectedClients = connections.count

        connection.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                self?.handleConnectionState(connection, state: state)
            }
        }

        connection.start(queue: .main)
        receiveMessage(from: connection)
    }

    private func handleConnectionState(_ connection: NWConnection, state: NWConnection.State) {
        switch state {
        case .ready:
            print("[P2P Server] Client connected")
        case .failed, .cancelled:
            removeConnection(connection)
        default:
            break
        }
    }

    private func removeConnection(_ connection: NWConnection) {
        connections.removeAll { $0 === connection }
        connectedClients = connections.count
    }

    // MARK: - Message Handling

    private func receiveMessage(from connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            Task { @MainActor in
                guard let self = self else { return }

                if let data = data, !data.isEmpty {
                    await self.processMessage(data, from: connection)
                }

                if let error = error {
                    print("[P2P Server] Receive error: \(error)")
                    self.removeConnection(connection)
                    return
                }

                if isComplete {
                    self.removeConnection(connection)
                } else {
                    // Continue receiving
                    self.receiveMessage(from: connection)
                }
            }
        }
    }

    private func processMessage(_ data: Data, from connection: NWConnection) async {
        // Try envelope format first (new protocol)
        if let envelope = try? JSONDecoder().decode(P2PEnvelope.self, from: data) {
            switch envelope.type {
            case .inferenceRequest:
                guard let request = try? JSONDecoder().decode(P2PInferenceRequest.self, from: envelope.payload) else {
                    sendError(to: connection, message: "Invalid inference request")
                    return
                }
                await processInferenceRequest(request, from: connection)
            case .relayRequest:
                guard let request = try? JSONDecoder().decode(P2PRelayRequest.self, from: envelope.payload) else {
                    sendError(to: connection, message: "Invalid relay request")
                    return
                }
                await InternetRelayHandler.shared.handleRelayRequest(request, from: connection, sendData: { [weak self] data, conn in
                    self?.sendData(data, to: conn)
                })
                recordSuccessfulRequest(isRelay: true)
            case .relayResponse:
                break // Server doesn't process relay responses
            case .meshForwardRequest:
                guard let request = try? JSONDecoder().decode(P2PMeshForwardRequest.self, from: envelope.payload) else {
                    sendError(to: connection, message: "Invalid mesh forward request")
                    return
                }
                await handleMeshForwardRequest(request, from: connection)
            case .meshForwardResponse:
                break // Server doesn't process mesh forward responses directly
            case .peerDiscovery:
                guard let discovery = try? JSONDecoder().decode(P2PPeerDiscovery.self, from: envelope.payload) else {
                    return
                }
                await handlePeerDiscovery(discovery, from: connection)
            case .topologyUpdate:
                break // Reserved for future topology updates
            case .speculativeVerifyRequest:
                guard let request = try? JSONDecoder().decode(SpeculativeVerifyRequestWithId.self, from: envelope.payload) else {
                    sendError(to: connection, message: "Invalid speculative verify request")
                    return
                }
                await handleSpeculativeVerify(request, from: connection)
            case .speculativeVerifyResponse:
                guard let response = try? JSONDecoder().decode(SpeculativeVerifyResponseWithId.self, from: envelope.payload) else {
                    return
                }
                // Forward to SpeculativeBackend (via ChatModeManager)
                await ChatModeManager.shared.handleSpeculativeVerificationResponse(response)
            case .directMessage:
                guard let message = try? JSONDecoder().decode(DirectMessage.self, from: envelope.payload) else {
                    return
                }
                await MessagingManager.shared.receiveMessage(message)
            case .friendRequest:
                // TODO: Handle friend request
                break
            case .friendAcceptance:
                // TODO: Handle friend acceptance
                break
            }
            return
        }

        // Fallback: legacy format (direct inference request)
        guard let request = try? JSONDecoder().decode(P2PInferenceRequest.self, from: data) else {
            sendError(to: connection, message: "Invalid request format")
            return
        }
        await processInferenceRequest(request, from: connection)
    }

    private func processInferenceRequest(_ request: P2PInferenceRequest, from connection: NWConnection) async {

        // Verify the request has a valid signature/token
        guard verifyRequest(request) else {
            sendError(to: connection, message: "Invalid request signature")
            return
        }

        // Check payment
        guard checkPayment(request) else {
            sendError(to: connection, message: "Insufficient tokens")
            return
        }

        // Process the inference request
        guard let backend = localBackend, backend.isReady else {
            sendError(to: connection, message: "Server not ready")
            return
        }

        do {
            // Generate response with streaming
            var fullResponse = ""
            _ = try await backend.generate(
                messages: request.messages,
                systemPrompt: request.systemPrompt,
                settings: request.settings
            ) { token in
                // Stream tokens back to client
                let chunk = P2PStreamChunk(token: token, isComplete: false)
                if let chunkData = try? JSONEncoder().encode(chunk) {
                    self.sendData(chunkData, to: connection)
                }
                fullResponse += token
            }

            // Send completion message
            let completion = P2PStreamChunk(token: "", isComplete: true, fullResponse: fullResponse)
            if let completionData = try? JSONEncoder().encode(completion) {
                sendData(completionData, to: connection)
            }

            // Record stats and earn token
            recordSuccessfulRequest()

        } catch {
            sendError(to: connection, message: "Inference failed: \(error.localizedDescription)")
        }
    }

    private func sendData(_ data: Data, to connection: NWConnection) {
        // Add newline delimiter for message framing
        var framedData = data
        framedData.append(contentsOf: [0x0A]) // newline

        connection.send(content: framedData, completion: .contentProcessed { error in
            if let error = error {
                print("[P2P Server] Send error: \(error)")
            }
        })
    }

    private func sendError(to connection: NWConnection, message: String) {
        let error = P2PErrorResponse(error: message)
        if let data = try? JSONEncoder().encode(error) {
            sendData(data, to: connection)
        }
    }

    private func verifyRequest(_ request: P2PInferenceRequest) -> Bool {
        let config = InferenceServerConfig.shared

        // Check server mode
        switch config.serverMode {
        case .private:
            // Only allow trusted devices
            // TODO: Implement trust list
            return !request.messages.isEmpty
        case .friendsOnly:
            // Allow friends + trusted
            // TODO: Implement friends list
            return !request.messages.isEmpty
        case .public:
            // Allow anyone
            return !request.messages.isEmpty
        }
    }

    /// Check if requester can afford the request
    private func checkPayment(_ request: P2PInferenceRequest) -> Bool {
        let config = InferenceServerConfig.shared

        // If server is free, no payment check needed
        if config.pricePerRequest == 0 {
            return true
        }

        // TODO: Implement payment verification with TokenManager
        // For now, accept all requests
        return true
    }

    // MARK: - Statistics

    private func recordSuccessfulRequest(isRelay: Bool = false) {
        resetStatsIfNewDay()

        todayRequestsServed += 1

        // Earn tokens based on server configuration
        let config = InferenceServerConfig.shared
        let earnRate: Int
        if isRelay {
            earnRate = TokenManager.relayEarnRate
        } else if config.pricePerRequest > 0 {
            // Use configured price
            earnRate = config.pricePerRequest
        } else {
            // Use default P2P rate
            earnRate = TokenManager.p2pEarnRate
        }

        todayTokensEarned += earnRate

        // Earn token
        tokenManager.earn(earnRate, reason: isRelay ? .relayServing : .p2pServing)

        // Save stats
        saveTodayStats()
    }

    private func loadTodayStats() {
        let defaults = UserDefaults.standard
        guard let data = defaults.data(forKey: statsKey),
              let stats = try? JSONDecoder().decode(P2PServerStats.self, from: data) else {
            return
        }

        // Check if stats are from today
        if Calendar.current.isDateInToday(stats.date) {
            todayRequestsServed = stats.requestsServed
            todayTokensEarned = stats.tokensEarned
            lastStatsDate = stats.date
        }
    }

    private func saveTodayStats() {
        let stats = P2PServerStats(
            date: Date(),
            requestsServed: todayRequestsServed,
            tokensEarned: todayTokensEarned
        )

        if let data = try? JSONEncoder().encode(stats) {
            UserDefaults.standard.set(data, forKey: statsKey)
        }
        lastStatsDate = stats.date
    }

    private func resetStatsIfNewDay() {
        guard let lastDate = lastStatsDate else { return }
        if !Calendar.current.isDateInToday(lastDate) {
            todayRequestsServed = 0
            todayTokensEarned = 0
        }
    }

    // MARK: - Pairing Code

    private let pairingCodeKey = "peer_pairing_code"

    private func loadOrGeneratePairingCode() {
        if let existing = UserDefaults.standard.string(forKey: pairingCodeKey) {
            pairingCode = existing
        } else {
            let code = String(format: "%04d", Int.random(in: 0...9999))
            UserDefaults.standard.set(code, forKey: pairingCodeKey)
            pairingCode = code
        }
    }

    /// Regenerate a new pairing code
    func regeneratePairingCode() {
        let code = String(format: "%04d", Int.random(in: 0...9999))
        UserDefaults.standard.set(code, forKey: pairingCodeKey)
        pairingCode = code

        // If server is running, restart to update the TXT record
        if isRunning {
            stop()
            Task { try? await start() }
        }
    }

    // MARK: - Helpers

    private func getDeviceName() -> String {
        #if os(iOS)
        return UIDevice.current.name
        #else
        return Host.current().localizedName ?? "ElioChat Server"
        #endif
    }

    private func updateServerAddress() {
        // Get local IP address
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?

        if getifaddrs(&ifaddr) == 0 {
            var ptr = ifaddr
            while ptr != nil {
                defer { ptr = ptr?.pointee.ifa_next }

                guard let interface = ptr?.pointee else { continue }
                let addrFamily = interface.ifa_addr.pointee.sa_family

                if addrFamily == UInt8(AF_INET) { // IPv4
                    let name = String(cString: interface.ifa_name)
                    if name == "en0" { // Wi-Fi interface
                        var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                        getnameinfo(interface.ifa_addr, socklen_t(interface.ifa_addr.pointee.sa_len),
                                    &hostname, socklen_t(hostname.count),
                                    nil, socklen_t(0), NI_NUMERICHOST)
                        address = String(cString: hostname)
                    }
                }
            }
            freeifaddrs(ifaddr)
        }

        serverAddress = address.map { "\($0):\(defaultPort)" }
    }

    // MARK: - Mesh Network Support

    /// Get or create unique device ID
    private func getDeviceId() -> String {
        if let existingId = UserDefaults.standard.string(forKey: deviceIdKey) {
            return existingId
        }
        let newId = UUID().uuidString
        UserDefaults.standard.set(newId, forKey: deviceIdKey)
        return newId
    }

    /// Get available memory in GB
    private func getAvailableMemory() -> Float {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }

        if kerr == KERN_SUCCESS {
            let usedMemoryBytes = Float(info.resident_size)
            let usedMemoryGB = usedMemoryBytes / (1024 * 1024 * 1024)

            // Get total physical memory
            let totalMemoryBytes = Float(ProcessInfo.processInfo.physicalMemory)
            let totalMemoryGB = totalMemoryBytes / (1024 * 1024 * 1024)

            return max(0, totalMemoryGB - usedMemoryGB)
        }

        return 1.0 // Default fallback
    }

    /// Get current battery level and charging status
    private func getBatteryInfo() -> (level: Float?, isCharging: Bool) {
        #if os(iOS)
        UIDevice.current.isBatteryMonitoringEnabled = true
        let level = UIDevice.current.batteryLevel
        let isCharging = UIDevice.current.batteryState == .charging || UIDevice.current.batteryState == .full
        return (level >= 0 ? level : nil, isCharging)
        #else
        return (nil, false)
        #endif
    }

    /// Get current compute capability
    func getComputeCapability() -> ComputeCapability {
        let batteryInfo = getBatteryInfo()
        return ComputeCapability(
            hasLocalLLM: localBackend?.isReady ?? false,
            modelName: nil,  // TODO: Get from AppState when available
            freeMemoryGB: getAvailableMemory(),
            batteryLevel: batteryInfo.level,
            isCharging: batteryInfo.isCharging,
            cpuCores: ProcessInfo.processInfo.processorCount
        )
    }

    /// Connect to another P2P server (for mesh networking)
    func connectToServerPeer(_ server: P2PServer) async throws {
        let deviceId = server.id

        // Don't connect if already connected
        if serverPeerConnections[deviceId] != nil {
            return
        }

        let parameters = NWParameters.tcp
        let connection = NWConnection(to: server.endpoint, using: parameters)

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in
                    switch state {
                    case .ready:
                        self?.serverPeerConnections[deviceId] = connection
                        // Send peer discovery
                        Task {
                            try? await self?.sendPeerDiscovery(to: connection)
                        }
                        continuation.resume()
                    case .failed(_):
                        continuation.resume(throwing: P2PServerError.connectionFailed)
                    case .cancelled:
                        continuation.resume(throwing: P2PServerError.connectionFailed)
                    default:
                        break
                    }
                }
            }
            connection.start(queue: .main)
        }

        // Start receiving messages from peer
        receivePeerMessage(from: connection, deviceId: deviceId)
    }

    /// Send peer discovery announcement
    private func sendPeerDiscovery(to connection: NWConnection) async throws {
        let discovery = P2PPeerDiscovery(
            deviceId: getDeviceId(),
            deviceName: getDeviceName(),
            computeCapability: getComputeCapability(),
            connectedPeers: Array(serverPeerConnections.keys)
        )

        let envelope = P2PEnvelope(
            type: .peerDiscovery,
            payload: try JSONEncoder().encode(discovery)
        )

        let data = try JSONEncoder().encode(envelope)
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
    }

    /// Receive messages from peer server
    private func receivePeerMessage(from connection: NWConnection, deviceId: String) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            Task { @MainActor in
                guard let self = self else { return }

                if let data = data, !data.isEmpty {
                    await self.processPeerMessage(data, from: connection, deviceId: deviceId)
                }

                if let error = error {
                    print("[P2P Server] Peer receive error: \(error)")
                    self.serverPeerConnections.removeValue(forKey: deviceId)
                    return
                }

                if isComplete {
                    self.serverPeerConnections.removeValue(forKey: deviceId)
                } else {
                    // Continue receiving
                    self.receivePeerMessage(from: connection, deviceId: deviceId)
                }
            }
        }
    }

    /// Process message from peer server
    private func processPeerMessage(_ data: Data, from connection: NWConnection, deviceId: String) async {
        guard let envelope = try? JSONDecoder().decode(P2PEnvelope.self, from: data) else {
            return
        }

        switch envelope.type {
        case .peerDiscovery:
            guard let discovery = try? JSONDecoder().decode(P2PPeerDiscovery.self, from: envelope.payload) else {
                return
            }
            // Update peer information
            if let index = connectedPeers.firstIndex(where: { $0.deviceId == discovery.deviceId }) {
                connectedPeers[index] = discovery
            } else {
                connectedPeers.append(discovery)
            }

        case .meshForwardRequest:
            guard let request = try? JSONDecoder().decode(P2PMeshForwardRequest.self, from: envelope.payload) else {
                return
            }
            await handleMeshForwardRequest(request, from: connection)

        default:
            break
        }
    }

    /// Handle mesh forward request
    private func handleMeshForwardRequest(_ request: P2PMeshForwardRequest, from connection: NWConnection) async {
        let myDeviceId = getDeviceId()

        // Check for loops
        if request.visitedNodes.contains(myDeviceId) {
            let errorResponse = P2PMeshForwardResponse(
                requestId: request.requestId,
                response: "",
                processingDeviceName: getDeviceName(),
                routePath: request.visitedNodes + [myDeviceId],
                hopCount: request.visitedNodes.count,
                error: "Loop detected"
            )
            await sendMeshResponse(errorResponse, to: connection)
            return
        }

        // Check hop limit
        if request.visitedNodes.count >= request.maxHops {
            let errorResponse = P2PMeshForwardResponse(
                requestId: request.requestId,
                response: "",
                processingDeviceName: getDeviceName(),
                routePath: request.visitedNodes + [myDeviceId],
                hopCount: request.visitedNodes.count,
                error: "Max hops exceeded"
            )
            await sendMeshResponse(errorResponse, to: connection)
            return
        }

        // Try to process locally if we have local LLM
        if let backend = localBackend, backend.isReady {
            do {
                var fullResponse = ""
                _ = try await backend.generate(
                    messages: request.originalRequest.messages,
                    systemPrompt: request.originalRequest.systemPrompt,
                    settings: request.originalRequest.settings
                ) { token in
                    fullResponse += token
                }

                let successResponse = P2PMeshForwardResponse(
                    requestId: request.requestId,
                    response: fullResponse,
                    processingDeviceName: getDeviceName(),
                    routePath: request.visitedNodes + [myDeviceId],
                    hopCount: request.visitedNodes.count,
                    error: nil
                )

                await sendMeshResponse(successResponse, to: connection)

                // Record stats and earn token
                recordSuccessfulRequest()

            } catch {
                // If local processing fails, try forwarding to peers
                await forwardToNextPeer(request, from: connection)
            }
        } else {
            // No local LLM, forward to peers
            await forwardToNextPeer(request, from: connection)
        }
    }

    /// Forward request to next available peer
    private func forwardToNextPeer(_ request: P2PMeshForwardRequest, from originalConnection: NWConnection) async {
        let myDeviceId = getDeviceId()
        let updatedVisited = request.visitedNodes + [myDeviceId]

        // Find best peer to forward to (not in visited list)
        let availablePeers = connectedPeers.filter { !updatedVisited.contains($0.deviceId) }
        guard let bestPeer = availablePeers.max(by: { $0.computeCapability.score < $1.computeCapability.score }) else {
            // No available peers
            let errorResponse = P2PMeshForwardResponse(
                requestId: request.requestId,
                response: "",
                processingDeviceName: getDeviceName(),
                routePath: updatedVisited,
                hopCount: updatedVisited.count - 1,
                error: "No available peers"
            )
            await sendMeshResponse(errorResponse, to: originalConnection)
            return
        }

        guard let peerConnection = serverPeerConnections[bestPeer.deviceId] else {
            let errorResponse = P2PMeshForwardResponse(
                requestId: request.requestId,
                response: "",
                processingDeviceName: getDeviceName(),
                routePath: updatedVisited,
                hopCount: updatedVisited.count - 1,
                error: "Peer connection lost"
            )
            await sendMeshResponse(errorResponse, to: originalConnection)
            return
        }

        // Forward the request
        let forwardedRequest = P2PMeshForwardRequest(
            requestId: request.requestId,
            originalRequest: request.originalRequest,
            visitedNodes: updatedVisited,
            maxHops: request.maxHops
        )

        do {
            let envelope = P2PEnvelope(
                type: .meshForwardRequest,
                payload: try JSONEncoder().encode(forwardedRequest)
            )
            let data = try JSONEncoder().encode(envelope)
            var framedData = data
            framedData.append(contentsOf: [0x0A])

            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                peerConnection.send(content: framedData, completion: .contentProcessed { error in
                    if let error = error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume()
                    }
                })
            }
        } catch {
            let errorResponse = P2PMeshForwardResponse(
                requestId: request.requestId,
                response: "",
                processingDeviceName: getDeviceName(),
                routePath: updatedVisited,
                hopCount: updatedVisited.count - 1,
                error: "Forward failed: \(error.localizedDescription)"
            )
            await sendMeshResponse(errorResponse, to: originalConnection)
        }
    }

    /// Send mesh response back
    private func sendMeshResponse(_ response: P2PMeshForwardResponse, to connection: NWConnection) async {
        do {
            let envelope = P2PEnvelope(
                type: .meshForwardResponse,
                payload: try JSONEncoder().encode(response)
            )
            let data = try JSONEncoder().encode(envelope)
            var framedData = data
            framedData.append(contentsOf: [0x0A])

            connection.send(content: framedData, completion: .contentProcessed { error in
                if let error = error {
                    print("[P2P Server] Failed to send mesh response: \(error)")
                }
            })
        } catch {
            print("[P2P Server] Failed to encode mesh response: \(error)")
        }
    }

    /// Handle peer discovery announcement
    private func handlePeerDiscovery(_ discovery: P2PPeerDiscovery, from connection: NWConnection) async {
        // Store or update peer information
        if let index = connectedPeers.firstIndex(where: { $0.deviceId == discovery.deviceId }) {
            // Update existing peer
            connectedPeers[index] = discovery
        } else {
            // Add new peer
            connectedPeers.append(discovery)
        }

        print("[P2P Server] Peer discovered: \(discovery.deviceName) (LLM: \(discovery.computeCapability.hasLocalLLM))")

        // Store connection for later use
        serverPeerConnections[discovery.deviceId] = connection

        // Send our own discovery back
        do {
            try await sendPeerDiscovery(to: connection)
        } catch {
            print("[P2P Server] Failed to send peer discovery: \(error)")
        }
    }

    // MARK: - Speculative Decoding Support

    /// Handle speculative verification request
    private func handleSpeculativeVerify(
        _ request: SpeculativeVerifyRequestWithId,
        from connection: NWConnection
    ) async {
        guard let backend = localBackend, backend.isReady else {
            sendError(to: connection, message: "Local model not ready")
            return
        }

        // NOTE: This is a simplified implementation that uses LocalBackend's generate method
        // In the future, we should expose LlamaInference directly for token-level verification

        do {
            // For now, use a simplified verification approach:
            // Generate one token with target model and compare with first draft token
            var targetToken = ""
            _ = try await backend.generate(
                messages: [],
                systemPrompt: "",
                settings: request.settings,
                onToken: { token in
                    targetToken = token
                }
            )

            // Simple verification: compare first token
            let acceptedTokens: [String]
            if !request.draftTokens.isEmpty && request.draftTokens[0] == targetToken {
                acceptedTokens = [targetToken]
            } else {
                acceptedTokens = []
            }

            let result = SpeculativeVerificationResult(
                acceptedTokens: acceptedTokens,
                rejectedIndex: acceptedTokens.isEmpty ? 0 : nil,
                fallbackToken: acceptedTokens.isEmpty ? targetToken : nil
            )

            // Send result back
            let response = SpeculativeVerifyResponseWithId(id: request.id, result: result)
            let envelope = P2PEnvelope(
                type: .speculativeVerifyResponse,
                payload: try JSONEncoder().encode(response)
            )
            let data = try JSONEncoder().encode(envelope)
            sendData(data, to: connection)

            // Record stats and earn token
            recordSuccessfulRequest()

        } catch {
            sendError(to: connection, message: "Verification failed: \(error.localizedDescription)")
        }
    }
}

// MARK: - P2P Protocol Types

enum P2PMessageType: String, Codable {
    case inferenceRequest
    case relayRequest
    case relayResponse
    case meshForwardRequest  // Mesh forwarding request
    case meshForwardResponse // Mesh forwarding response
    case peerDiscovery       // Peer discovery announcement
    case topologyUpdate      // Network topology update
    case speculativeVerifyRequest  // Speculative decoding verification request
    case speculativeVerifyResponse // Speculative decoding verification response
    case directMessage       // Direct message to friend
    case friendRequest       // Friend request
    case friendAcceptance    // Friend request acceptance
}

struct P2PEnvelope: Codable {
    let type: P2PMessageType
    let payload: Data
}

struct P2PInferenceRequest: Codable {
    let messages: [Message]
    let systemPrompt: String
    let settings: ModelSettings
    let clientId: String
    let signature: String?
}

struct P2PRelayRequest: Codable {
    let id: String
    let url: String
    let method: String
    let headers: [String: String]?
    let body: Data?
    let clientId: String
}

struct P2PRelayResponse: Codable {
    let id: String
    let statusCode: Int
    let headers: [String: String]?
    let body: Data?
    let error: String?
}

struct P2PStreamChunk: Codable {
    let token: String
    let isComplete: Bool
    var fullResponse: String?
}

struct P2PErrorResponse: Codable {
    let error: String
}

struct P2PServerStats: Codable {
    let date: Date
    let requestsServed: Int
    let tokensEarned: Int
}

// MARK: - P2P Mesh Protocol Types

/// Mesh forward request - relays inference request through mesh network
struct P2PMeshForwardRequest: Codable {
    let requestId: UUID
    let originalRequest: P2PInferenceRequest
    let visitedNodes: [String]    // Loop detection
    let maxHops: Int
    let timestamp: Date

    init(
        requestId: UUID = UUID(),
        originalRequest: P2PInferenceRequest,
        visitedNodes: [String] = [],
        maxHops: Int = 5,
        timestamp: Date = Date()
    ) {
        self.requestId = requestId
        self.originalRequest = originalRequest
        self.visitedNodes = visitedNodes
        self.maxHops = maxHops
        self.timestamp = timestamp
    }
}

/// Mesh forward response - returns inference result through mesh
struct P2PMeshForwardResponse: Codable {
    let requestId: UUID
    let response: String
    let processingDeviceName: String
    let routePath: [String]
    let hopCount: Int
    let error: String?
}

/// Peer discovery announcement - broadcast device capabilities
struct P2PPeerDiscovery: Codable {
    let deviceId: String
    let deviceName: String
    let computeCapability: ComputeCapability
    let connectedPeers: [String]
    let timestamp: Date

    init(
        deviceId: String,
        deviceName: String,
        computeCapability: ComputeCapability,
        connectedPeers: [String] = [],
        timestamp: Date = Date()
    ) {
        self.deviceId = deviceId
        self.deviceName = deviceName
        self.computeCapability = computeCapability
        self.connectedPeers = connectedPeers
        self.timestamp = timestamp
    }
}

/// Device compute capability information
struct ComputeCapability: Codable {
    let hasLocalLLM: Bool
    let modelName: String?
    let freeMemoryGB: Float
    let batteryLevel: Float?
    let isCharging: Bool
    let cpuCores: Int?

    init(
        hasLocalLLM: Bool,
        modelName: String? = nil,
        freeMemoryGB: Float,
        batteryLevel: Float? = nil,
        isCharging: Bool = false,
        cpuCores: Int? = nil
    ) {
        self.hasLocalLLM = hasLocalLLM
        self.modelName = modelName
        self.freeMemoryGB = freeMemoryGB
        self.batteryLevel = batteryLevel
        self.isCharging = isCharging
        self.cpuCores = cpuCores
    }

    /// Calculate a score for peer selection (higher is better)
    var score: Float {
        var s: Float = 0

        // Local LLM is primary factor
        if hasLocalLLM {
            s += 100
        }

        // Memory availability
        s += freeMemoryGB * 10

        // Battery level (if available)
        if let battery = batteryLevel {
            if isCharging {
                s += 50  // Charging device is preferred
            } else {
                s += battery * 0.5  // Consider battery level
            }
        }

        return s
    }
}

// MARK: - P2P Server Errors

enum P2PServerError: Error, LocalizedError {
    case backendNotReady
    case startFailed(String)
    case connectionFailed

    var errorDescription: String? {
        switch self {
        case .backendNotReady:
            return String(localized: "p2p.error.backend.not.ready", defaultValue: "Local model not loaded")
        case .startFailed(let reason):
            return String(localized: "p2p.error.start.failed", defaultValue: "Failed to start server: \(reason)")
        case .connectionFailed:
            return String(localized: "p2p.error.connection.failed", defaultValue: "Connection failed")
        }
    }
}
