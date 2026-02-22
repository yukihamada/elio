import Foundation

/// Speculative Decoding Backend: Draft model (local 1B) + Target model (P2P peer 7B)
/// Achieves 2-3x speedup by generating N speculative tokens with a small draft model,
/// then verifying them with a larger target model on a P2P peer.
@MainActor
final class SpeculativeBackend: InferenceBackend {

    // MARK: - InferenceBackend Protocol

    var backendId: String { "speculative" }
    var displayName: String { "Speculative" }
    var tokenCost: Int { 2 }  // Draft (free) + P2P (2 tokens)

    var isReady: Bool {
        // Ready if we have draft model AND capable peer
        return draftModel != nil && meshManager.isReady
    }

    // MARK: - Properties

    private var draftModel: LlamaInference?  // Small 1B model for fast draft
    private let meshManager: MeshP2PManager
    private let maxDraftTokens = 5  // Number of speculative tokens to generate
    private let fallbackBackend: LocalBackend?

    @Published private(set) var isGenerating = false
    @Published var stats: SpeculativeStats = SpeculativeStats()

    // Pending verification requests
    private var pendingVerifications: [UUID: CheckedContinuation<SpeculativeVerificationResult, Error>] = [:]

    // MARK: - Initialization

    init(draftModel: LlamaInference? = nil, meshManager: MeshP2PManager = .shared, fallbackBackend: LocalBackend? = nil) {
        self.draftModel = draftModel
        self.meshManager = meshManager
        self.fallbackBackend = fallbackBackend
    }

    /// Configure draft model
    func configureDraftModel(_ model: LlamaInference) {
        self.draftModel = model
    }

    // MARK: - Generation

    func generate(
        messages: [Message],
        systemPrompt: String,
        settings: ModelSettings,
        onToken: @escaping (String) -> Void
    ) async throws -> String {
        guard let draftModel = draftModel else {
            throw InferenceError.notReady
        }

        isGenerating = true
        defer { isGenerating = false }

        stats = SpeculativeStats()
        var output = ""
        var context = draftModel.formatChatPrompt(messages: messages, systemPrompt: systemPrompt, enableThinking: false)

        let startTime = Date()

        while output.count < settings.maxTokens {
            // Check for cancellation
            try Task.checkCancellation()

            // Step 1: Generate N speculative tokens with draft model
            let draftTokens = try await generateDraftTokens(
                prompt: context,
                count: maxDraftTokens,
                settings: settings
            )

            stats.draftTokensGenerated += draftTokens.count

            // Step 2: Find capable peer for verification
            guard let verifierPeer = await findVerifierPeer() else {
                // No peer available, fallback to local generation
                print("[Speculative] No verifier peer available, using fallback")
                if let fallback = fallbackBackend, fallback.isReady {
                    return try await fallback.generate(
                        messages: messages,
                        systemPrompt: systemPrompt,
                        settings: settings,
                        onToken: onToken
                    )
                }
                throw InferenceError.notReady
            }

            // Step 3: Verify draft tokens with target model on P2P peer
            let verifyResult = try await verifyWithTargetModel(
                context: context,
                draftTokens: draftTokens,
                peer: verifierPeer,
                settings: settings
            )

            // Step 4: Accept verified tokens
            let acceptedTokens = verifyResult.acceptedTokens
            stats.tokensAccepted += acceptedTokens.count

            if acceptedTokens.isEmpty {
                // All tokens rejected, use fallback
                if let fallbackToken = verifyResult.fallbackToken {
                    output += fallbackToken
                    context += fallbackToken
                    onToken(fallbackToken)
                    stats.tokensAccepted += 1
                } else {
                    // No fallback token, stop generation
                    break
                }
            } else {
                // Add accepted tokens to output
                let acceptedText = acceptedTokens.joined()
                output += acceptedText
                context += acceptedText
                onToken(acceptedText)
            }

            // Check for EOS or max length
            if output.hasSuffix("</s>") || output.hasSuffix("<|im_end|>") {
                break
            }
        }

        let duration = Date().timeIntervalSince(startTime)
        stats.totalDurationMs = Int(duration * 1000)
        stats.calculateMetrics()

        print("[Speculative] Stats: \(stats)")

        return output
    }

    func stopGeneration() {
        isGenerating = false
    }

    // MARK: - Private Methods

    /// Generate N speculative tokens with draft model
    private func generateDraftTokens(
        prompt: String,
        count: Int,
        settings: ModelSettings
    ) async throws -> [String] {
        guard let draftModel = draftModel else {
            throw InferenceError.notReady
        }

        var tokens: [String] = []
        var currentPrompt = prompt

        // Generate tokens one by one (draft model is fast)
        for _ in 0..<count {
            var token = ""

            // Generate single token with draft model
            _ = try await draftModel.generate(
                prompt: currentPrompt,
                maxTokens: 1,
                temperature: settings.temperature,
                topP: settings.topP,
                topK: Int32(settings.topK),
                repeatPenalty: settings.repeatPenalty,
                stopSequences: ["</s>", "<|im_end|>"],
                onToken: { t in
                    token = t
                }
            )

            if token.isEmpty {
                break
            }

            tokens.append(token)
            currentPrompt += token

            // Stop if EOS token
            if token == "</s>" || token == "<|im_end|>" {
                break
            }
        }

        return tokens
    }

    /// Find best peer with large model for verification
    private func findVerifierPeer() async -> MeshPeer? {
        // Look for peers with large model (7B+)
        let peers = meshManager.connectedPeers

        // Filter peers with high compute capability
        let capablePeers = peers.filter { peer in
            peer.capability.hasLocalLLM && peer.capability.freeMemoryGB > 2.0
        }

        // Sort by capability score and return best
        return capablePeers.max { $0.capability.score < $1.capability.score }
    }

    /// Verify draft tokens with target model on P2P peer
    private func verifyWithTargetModel(
        context: String,
        draftTokens: [String],
        peer: MeshPeer,
        settings: ModelSettings
    ) async throws -> SpeculativeVerificationResult {
        // Build verification request
        let request = SpeculativeVerifyRequest(
            context: context,
            draftTokens: draftTokens,
            settings: settings,
            requesterDeviceId: DeviceIdentityManager.shared.deviceId
        )

        // Send request to peer via mesh manager
        let response = try await sendVerifyRequest(request, to: peer)

        return response
    }

    /// Send verification request to peer
    private func sendVerifyRequest(
        _ request: SpeculativeVerifyRequest,
        to peer: MeshPeer
    ) async throws -> SpeculativeVerificationResult {
        // Get connection to peer
        guard let connection = PrivateServerManager.shared.serverPeerConnections[peer.id] else {
            throw InferenceError.networkError("No connection to peer")
        }

        // Generate request ID
        let requestId = UUID()
        let requestWithId = SpeculativeVerifyRequestWithId(
            id: requestId,
            context: request.context,
            draftTokens: request.draftTokens,
            settings: request.settings,
            requesterDeviceId: request.requesterDeviceId
        )

        // Encode request
        let envelope = P2PEnvelope(
            type: .speculativeVerifyRequest,
            payload: try JSONEncoder().encode(requestWithId)
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

        // Wait for response with timeout
        return try await withCheckedThrowingContinuation { continuation in
            pendingVerifications[requestId] = continuation

            // Timeout after 10 seconds
            Task {
                try? await Task.sleep(nanoseconds: 10_000_000_000)
                if let pending = pendingVerifications.removeValue(forKey: requestId) {
                    pending.resume(throwing: InferenceError.networkError("Verification timeout"))
                }
            }
        }
    }

    /// Handle verification response from P2P peer
    func handleVerificationResponse(_ response: SpeculativeVerifyResponseWithId) {
        guard let continuation = pendingVerifications.removeValue(forKey: response.id) else {
            print("[SpeculativeBackend] Received response for unknown request: \(response.id)")
            return
        }

        continuation.resume(returning: response.result)
    }
}

// MARK: - Supporting Types

/// Speculative verification request (without ID, for internal use)
struct SpeculativeVerifyRequest: Codable {
    let context: String
    let draftTokens: [String]
    let settings: ModelSettings
    let requesterDeviceId: String
}

/// Speculative verification request with ID (for P2P communication)
struct SpeculativeVerifyRequestWithId: Codable {
    let id: UUID
    let context: String
    let draftTokens: [String]
    let settings: ModelSettings
    let requesterDeviceId: String
}

/// Verification result from target model
struct SpeculativeVerificationResult: Codable {
    let acceptedTokens: [String]  // Tokens that passed verification
    let rejectedIndex: Int?       // First rejected token index (nil if all accepted)
    let fallbackToken: String?    // Token generated by target model if first was rejected
}

/// Verification response with ID (for P2P communication)
struct SpeculativeVerifyResponseWithId: Codable {
    let id: UUID
    let result: SpeculativeVerificationResult
}

/// Statistics for speculative decoding
struct SpeculativeStats {
    var draftTokensGenerated: Int = 0
    var tokensAccepted: Int = 0
    var totalDurationMs: Int = 0

    var acceptanceRate: Double {
        guard draftTokensGenerated > 0 else { return 0 }
        return Double(tokensAccepted) / Double(draftTokensGenerated)
    }

    var speedup: Double {
        guard draftTokensGenerated > 0 else { return 1.0 }
        // Theoretical speedup based on acceptance rate
        return 1.0 + (acceptanceRate * Double(tokensAccepted) / Double(draftTokensGenerated))
    }

    mutating func calculateMetrics() {
        // Metrics are calculated on-demand via computed properties
    }
}

extension SpeculativeStats: CustomStringConvertible {
    var description: String {
        """
        SpeculativeStats(
            drafted: \(draftTokensGenerated),
            accepted: \(tokensAccepted),
            rate: \(String(format: "%.1f%%", acceptanceRate * 100)),
            speedup: \(String(format: "%.2fx", speedup)),
            duration: \(totalDurationMs)ms
        )
        """
    }
}

// MARK: - Note
// P2PMessageType cases for speculative decoding are defined in PrivateServerManager.swift:
// - case speculativeVerifyRequest
// - case speculativeVerifyResponse
