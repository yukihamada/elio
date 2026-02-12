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

        // Process the inference request
        guard let backend = localBackend, backend.isReady else {
            sendError(to: connection, message: "Server not ready")
            return
        }

        do {
            // Generate response with streaming
            var fullResponse = ""
            let response = try await backend.generate(
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
        // TODO: Implement proper signature verification
        // For now, just check that the request has required fields
        return !request.messages.isEmpty
    }

    // MARK: - Statistics

    private func recordSuccessfulRequest(isRelay: Bool = false) {
        resetStatsIfNewDay()

        todayRequestsServed += 1
        let earnRate = isRelay ? TokenManager.relayEarnRate : TokenManager.p2pEarnRate
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
}

// MARK: - P2P Protocol Types

enum P2PMessageType: String, Codable {
    case inferenceRequest
    case relayRequest
    case relayResponse
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
