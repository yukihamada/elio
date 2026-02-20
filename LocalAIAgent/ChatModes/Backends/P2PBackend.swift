import Foundation
import Network

/// P2P connection mode
enum P2PMode {
    case privateNetwork   // Trusted devices only
    case publicNetwork    // Any P2P server
}

/// P2P inference backend - connects to other users' devices for inference
/// Private mode: Free (trusted devices)
/// Public mode: 2 tokens per message
@MainActor
final class P2PBackend: InferenceBackend, ObservableObject {
    private var connection: NWConnection?
    private var browser: NWBrowser?

    @Published private(set) var isGenerating = false
    @Published private(set) var availableServers: [P2PServer] = []
    @Published private(set) var trustedServers: [P2PServer] = []  // Permitted devices
    @Published var selectedServer: P2PServer?
    @Published var mode: P2PMode = .privateNetwork

    // Trusted device IDs (stored in UserDefaults)
    @Published private(set) var trustedDeviceIds: Set<String> = []

    var backendId: String { mode == .privateNetwork ? "private_p2p" : "public_p2p" }
    var displayName: String { mode == .privateNetwork ? ChatMode.privateP2P.displayName : ChatMode.publicP2P.displayName }
    var tokenCost: Int { mode == .privateNetwork ? 0 : 2 }

    var isReady: Bool {
        selectedServer != nil && connection?.state == .ready
    }

    // MARK: - Server Discovery

    /// Start browsing for available P2P servers
    func startBrowsing() {
        let parameters = NWParameters()
        parameters.includePeerToPeer = true

        browser = NWBrowser(for: .bonjour(type: "_eliochat._tcp", domain: "local."), using: parameters)

        browser?.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                switch state {
                case .ready:
                    print("[P2P Client] Browser ready")
                case .failed(let error):
                    print("[P2P Client] Browser failed: \(error)")
                default:
                    break
                }
            }
        }

        browser?.browseResultsChangedHandler = { [weak self] results, changes in
            Task { @MainActor in
                self?.updateAvailableServers(results)
            }
        }

        browser?.start(queue: .main)
    }

    /// Stop browsing for servers
    func stopBrowsing() {
        browser?.cancel()
        browser = nil
    }

    private func updateAvailableServers(_ results: Set<NWBrowser.Result>) {
        availableServers = results.compactMap { result -> P2PServer? in
            guard case .service(let name, let type, let domain, _) = result.endpoint else {
                return nil
            }

            // Extract pairing code from TXT record
            var code: String?
            if case .bonjour(let txtRecord) = result.metadata {
                code = txtRecord["code"]
            }

            return P2PServer(
                id: "\(name).\(type).\(domain)",
                name: name,
                endpoint: result.endpoint,
                pairingCode: code
            )
        }
        // Also update the trusted servers list
        updateTrustedServers()
    }

    /// Find a server by its 4-digit pairing code
    func findServer(byPairingCode code: String) -> P2PServer? {
        availableServers.first { $0.pairingCode == code }
    }

    // MARK: - Connection

    /// Connect to a specific server
    func connect(to server: P2PServer) async throws {
        disconnect()

        let parameters = NWParameters.tcp
        connection = NWConnection(to: server.endpoint, using: parameters)

        return try await withCheckedThrowingContinuation { continuation in
            connection?.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in
                    switch state {
                    case .ready:
                        self?.selectedServer = server
                        continuation.resume()
                    case .failed(let error):
                        self?.selectedServer = nil
                        continuation.resume(throwing: InferenceError.networkError(error.localizedDescription))
                    case .cancelled:
                        self?.selectedServer = nil
                    default:
                        break
                    }
                }
            }

            connection?.start(queue: .main)
        }
    }

    /// Disconnect from current server
    func disconnect() {
        connection?.cancel()
        connection = nil
        selectedServer = nil
    }

    // MARK: - InferenceBackend

    func generate(
        messages: [Message],
        systemPrompt: String,
        settings: ModelSettings,
        onToken: @escaping (String) -> Void
    ) async throws -> String {
        guard let connection = connection, connection.state == .ready else {
            throw InferenceError.notReady
        }

        isGenerating = true
        defer { isGenerating = false }

        // Build request
        let request = P2PInferenceRequest(
            messages: messages,
            systemPrompt: systemPrompt,
            settings: settings,
            clientId: getClientId(),
            signature: nil // TODO: Add signing
        )

        guard let requestData = try? JSONEncoder().encode(request) else {
            throw InferenceError.invalidResponse
        }

        // Send request
        var framedData = requestData
        framedData.append(contentsOf: [0x0A]) // newline delimiter

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: framedData, completion: .contentProcessed { error in
                if let error = error {
                    continuation.resume(throwing: InferenceError.networkError(error.localizedDescription))
                } else {
                    continuation.resume()
                }
            })
        }

        // Receive streaming response
        return try await receiveStreamingResponse(from: connection, onToken: onToken)
    }

    func stopGeneration() {
        // Cancel the connection to stop generation
        disconnect()
        isGenerating = false
    }

    // MARK: - Private

    private func receiveStreamingResponse(
        from connection: NWConnection,
        onToken: @escaping (String) -> Void
    ) async throws -> String {
        var fullResponse = ""
        var buffer = Data()

        while true {
            try Task.checkCancellation()

            let data = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
                connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, isComplete, error in
                    if let error = error {
                        continuation.resume(throwing: InferenceError.networkError(error.localizedDescription))
                    } else if let data = data {
                        continuation.resume(returning: data)
                    } else if isComplete {
                        continuation.resume(returning: Data())
                    } else {
                        continuation.resume(returning: Data())
                    }
                }
            }

            if data.isEmpty {
                break
            }

            buffer.append(data)

            // Process complete messages (delimited by newline)
            while let newlineIndex = buffer.firstIndex(of: 0x0A) {
                let messageData = buffer.prefix(upTo: newlineIndex)
                buffer = Data(buffer.suffix(from: buffer.index(after: newlineIndex)))

                // Parse chunk
                if let chunk = try? JSONDecoder().decode(P2PStreamChunk.self, from: messageData) {
                    if !chunk.token.isEmpty {
                        onToken(chunk.token)
                        fullResponse += chunk.token
                    }

                    if chunk.isComplete {
                        return chunk.fullResponse ?? fullResponse
                    }
                } else if let errorResponse = try? JSONDecoder().decode(P2PErrorResponse.self, from: messageData) {
                    throw InferenceError.serverError(500, errorResponse.error)
                }
            }
        }

        return fullResponse
    }

    private func getClientId() -> String {
        // Generate or retrieve a unique client ID
        let key = "p2p_client_id"
        if let existingId = UserDefaults.standard.string(forKey: key) {
            return existingId
        }
        let newId = UUID().uuidString
        UserDefaults.standard.set(newId, forKey: key)
        return newId
    }

    // MARK: - Trusted Device Management

    private let trustedDevicesKey = "p2p_trusted_devices"

    init() {
        loadTrustedDevices()
    }

    /// Load trusted device IDs from storage
    private func loadTrustedDevices() {
        if let ids = UserDefaults.standard.stringArray(forKey: trustedDevicesKey) {
            trustedDeviceIds = Set(ids)
        }
    }

    /// Save trusted device IDs to storage
    private func saveTrustedDevices() {
        UserDefaults.standard.set(Array(trustedDeviceIds), forKey: trustedDevicesKey)
    }

    /// Add a device to trusted list
    func trustDevice(_ server: P2PServer) {
        trustedDeviceIds.insert(server.id)
        saveTrustedDevices()
        updateTrustedServers()
    }

    /// Remove a device from trusted list
    func untrustDevice(_ server: P2PServer) {
        trustedDeviceIds.remove(server.id)
        saveTrustedDevices()
        updateTrustedServers()
    }

    /// Check if a device is trusted
    func isDeviceTrusted(_ server: P2PServer) -> Bool {
        trustedDeviceIds.contains(server.id)
    }

    /// Update the filtered list of trusted servers
    private func updateTrustedServers() {
        trustedServers = availableServers.filter { trustedDeviceIds.contains($0.id) }
        autoConnectToTrustedServer()
    }

    /// Automatically connect to a trusted server when discovered
    private func autoConnectToTrustedServer() {
        // Skip if already connected
        guard selectedServer == nil || connection?.state != .ready else { return }
        guard mode == .privateNetwork else { return }
        guard let server = trustedServers.first else { return }

        Task {
            do {
                try await connect(to: server)
                print("[P2P Client] Auto-connected to trusted server: \(server.name)")
                // Only auto-switch if currently in local mode (don't interrupt cloud usage)
                if ChatModeManager.shared.currentMode == .local {
                    ChatModeManager.shared.setMode(.privateP2P)
                }
            } catch {
                print("[P2P Client] Auto-connect failed: \(error)")
            }
        }
    }

    // MARK: - Internet Relay

    /// Relay an HTTP request through the P2P server (for iPhones without internet)
    func relayHTTPRequest(
        url: String,
        method: String = "POST",
        headers: [String: String]? = nil,
        body: Data? = nil
    ) async throws -> (statusCode: Int, headers: [String: String]?, body: Data?) {
        guard let connection = connection, connection.state == .ready else {
            throw InferenceError.notReady
        }

        let relayRequest = P2PRelayRequest(
            id: UUID().uuidString,
            url: url,
            method: method,
            headers: headers,
            body: body,
            clientId: getClientId()
        )

        guard let payload = try? JSONEncoder().encode(relayRequest) else {
            throw InferenceError.invalidResponse
        }

        let envelope = P2PEnvelope(type: .relayRequest, payload: payload)
        guard let envelopeData = try? JSONEncoder().encode(envelope) else {
            throw InferenceError.invalidResponse
        }

        // Send request
        var framedData = envelopeData
        framedData.append(contentsOf: [0x0A])

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: framedData, completion: .contentProcessed { error in
                if let error = error {
                    continuation.resume(throwing: InferenceError.networkError(error.localizedDescription))
                } else {
                    continuation.resume()
                }
            })
        }

        // Receive relay response
        let responseData = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
            connection.receive(minimumIncompleteLength: 1, maximumLength: 1_048_576) { data, _, _, error in
                if let error = error {
                    continuation.resume(throwing: InferenceError.networkError(error.localizedDescription))
                } else if let data = data {
                    continuation.resume(returning: data)
                } else {
                    continuation.resume(returning: Data())
                }
            }
        }

        // Parse envelope
        guard let responseEnvelope = try? JSONDecoder().decode(P2PEnvelope.self, from: responseData),
              responseEnvelope.type == .relayResponse,
              let relayResponse = try? JSONDecoder().decode(P2PRelayResponse.self, from: responseEnvelope.payload) else {
            throw InferenceError.invalidResponse
        }

        if let error = relayResponse.error {
            throw InferenceError.serverError(relayResponse.statusCode, error)
        }

        return (relayResponse.statusCode, relayResponse.headers, relayResponse.body)
    }

    /// Get servers based on current mode
    var serversForCurrentMode: [P2PServer] {
        switch mode {
        case .privateNetwork:
            return trustedServers
        case .publicNetwork:
            return availableServers
        }
    }
}

// MARK: - P2P Server Info

struct P2PServer: Identifiable, Equatable {
    let id: String
    let name: String
    let endpoint: NWEndpoint
    let pairingCode: String?

    static func == (lhs: P2PServer, rhs: P2PServer) -> Bool {
        lhs.id == rhs.id
    }
}
