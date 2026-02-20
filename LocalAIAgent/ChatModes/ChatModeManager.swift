import Foundation
import SwiftUI
import Combine

/// Manages chat mode selection and backend routing
@MainActor
final class ChatModeManager: ObservableObject {
    static let shared = ChatModeManager()

    // MARK: - Published Properties

    @Published var currentMode: ChatMode = .local
    @Published var selectedCloudProvider: CloudProvider = .openai
    @Published private(set) var isGenerating = false
    @Published var error: Error?
    @Published var pendingOnboarding: ChatMode?  // Non-nil when onboarding needs to be shown

    // MARK: - Dependencies

    private let tokenManager = TokenManager.shared
    private let keychain = KeychainManager.shared

    // MARK: - Backends

    private var localBackend: LocalBackend?
    var chatwebBackend: ChatWebBackend?
    private var groqBackend: GroqBackend?
    private var cloudBackend: CloudBackend?
    private var p2pBackend: P2PBackend?
    private var meshBackend: MeshP2PManager?
    private var speculativeBackend: SpeculativeBackend?

    /// Whether chatweb.ai mode is currently active
    var isChatWebMode: Bool { currentMode == .chatweb }

    /// Whether conversation sync should be disabled
    var isSyncDisabled: Bool { false }

    // Persistence
    @AppStorage("selectedChatMode") private var savedMode: String = ChatMode.local.rawValue
    @AppStorage("selectedCloudProvider") private var savedProvider: String = CloudProvider.openai.rawValue

    private init() {
        // Restore saved preferences
        currentMode = ChatMode(rawValue: savedMode) ?? .local
        selectedCloudProvider = CloudProvider(rawValue: savedProvider) ?? .openai

        // Initialize cloud backends
        chatwebBackend = ChatWebBackend()
        groqBackend = GroqBackend()
        cloudBackend = CloudBackend()
        p2pBackend = P2PBackend()
        meshBackend = MeshP2PManager.shared
        speculativeBackend = SpeculativeBackend(meshManager: MeshP2PManager.shared)
    }

    // MARK: - Configuration

    /// Set up the local backend with CoreMLInference
    func configureLocalBackend(_ inference: CoreMLInference) {
        localBackend = LocalBackend(inference: inference)
        // Configure P2P server so it can handle inference requests from peers
        PrivateServerManager.shared.configure(backend: localBackend!)
        // Configure mesh backend with local backend
        meshBackend?.setLocalBackend(localBackend)
        // TODO: Configure speculative backend with draft model
        // speculativeBackend?.configureDraftModel(draftModel)
    }

    /// Tear down the local backend and stop P2P server
    func clearLocalBackend() {
        localBackend = nil
        if PrivateServerManager.shared.isRunning {
            PrivateServerManager.shared.stop()
        }
        meshBackend?.setLocalBackend(nil)
    }

    /// Set the current chat mode
    func setMode(_ mode: ChatMode) {
        // Validate mode requirements
        if mode.requiresNetwork && !NetworkMonitor.shared.isConnected {
            error = InferenceError.networkError("No network connection")
            return
        }

        if mode.requiresAPIKey && !hasRequiredAPIKey(for: mode) {
            // Check if user has seen onboarding for this mode
            if !hasSeenOnboarding(for: mode) {
                // Show onboarding instead of error
                pendingOnboarding = mode
                return
            }
            // User has seen onboarding, show error
            error = InferenceError.apiKeyMissing
            return
        }

        currentMode = mode
        savedMode = mode.rawValue
        error = nil
    }

    /// Check if user has seen onboarding for a specific mode
    private func hasSeenOnboarding(for mode: ChatMode) -> Bool {
        UserDefaults.standard.bool(forKey: "onboarding_\(mode.rawValue)")
    }

    /// Set the cloud provider for Genius mode
    func setCloudProvider(_ provider: CloudProvider) {
        selectedCloudProvider = provider
        savedProvider = provider.rawValue
        cloudBackend?.setProvider(provider)
    }

    // MARK: - Backend Access

    /// Get the P2P backend for direct access
    var p2p: P2PBackend? { p2pBackend }

    /// Get the current active backend
    var currentBackend: (any InferenceBackend)? {
        switch currentMode {
        case .local:
            return localBackend
        case .chatweb:
            return chatwebBackend
        case .fast:
            return groqBackend
        case .genius:
            return cloudBackend
        case .privateP2P:
            p2pBackend?.mode = .privateNetwork
            return p2pBackend
        case .publicP2P:
            p2pBackend?.mode = .publicNetwork
            return p2pBackend
        case .p2pMesh:
            return meshBackend
        case .speculative:
            return speculativeBackend
        }
    }

    /// Check if the current mode is ready
    var isCurrentModeReady: Bool {
        switch currentMode {
        case .local:
            return localBackend?.isReady ?? false
        case .chatweb:
            return chatwebBackend?.isReady ?? true
        case .fast:
            return groqBackend?.isReady ?? false
        case .genius:
            return cloudBackend?.isReady ?? false
        case .privateP2P:
            // Ready if connected to a trusted device
            guard let p2p = p2pBackend else { return false }
            return p2p.isReady && p2p.selectedServer.map { p2p.isDeviceTrusted($0) } ?? false
        case .publicP2P:
            return p2pBackend?.isReady ?? false
        case .p2pMesh:
            return meshBackend?.isReady ?? false
        case .speculative:
            return speculativeBackend?.isReady ?? false
        }
    }

    /// Check if a specific mode is available
    func isModeAvailable(_ mode: ChatMode) -> Bool {
        switch mode {
        case .local:
            return localBackend?.isReady ?? false
        case .chatweb:
            return true  // Always available, no API key needed
        case .fast:
            return keychain.hasAPIKey(for: .groq)
        case .genius:
            return hasRequiredAPIKey(for: .genius)
        case .privateP2P:
            // Available if there are trusted servers nearby
            return !(p2pBackend?.trustedServers.isEmpty ?? true)
        case .publicP2P:
            // Available if there are any servers nearby
            return !(p2pBackend?.availableServers.isEmpty ?? true)
        case .p2pMesh:
            // Available if we have local LLM OR connected peers
            return (localBackend?.isReady ?? false) || !(meshBackend?.connectedPeers.isEmpty ?? true)
        case .speculative:
            // Available if we have draft model AND connected peers with large models
            return speculativeBackend?.isReady ?? false
        }
    }

    // MARK: - Generation

    /// Generate a response using the current mode
    func generate(
        messages: [Message],
        systemPrompt: String,
        settings: ModelSettings,
        onToken: @escaping (String) -> Void
    ) async throws -> String {
        guard let backend = currentBackend else {
            throw InferenceError.notReady
        }

        // Check token balance for non-local modes
        let cost = currentMode.tokenCost
        if cost > 0 {
            guard tokenManager.canAfford(cost) else {
                throw InferenceError.insufficientTokens
            }
        }

        isGenerating = true
        defer { isGenerating = false }

        do {
            let response = try await backend.generate(
                messages: messages,
                systemPrompt: systemPrompt,
                settings: settings,
                onToken: onToken
            )

            // Deduct tokens after successful generation
            if cost > 0 {
                let reason: SpendReason
                switch currentMode {
                case .fast: reason = .fastMode
                case .genius: reason = .geniusMode
                case .publicP2P: reason = .p2pRequest
                case .local, .chatweb, .privateP2P, .p2pMesh: reason = .fastMode // Should not happen (all are free)
                case .speculative: reason = .p2pRequest
                }
                try? tokenManager.spend(cost, reason: reason)
            }

            return response
        } catch {
            self.error = error
            throw error
        }
    }

    /// Stop any ongoing generation
    func stopGeneration() {
        currentBackend?.stopGeneration()
        isGenerating = false
    }

    // MARK: - ChatWeb Auth

    /// Set auth token for ChatWeb backend (called by SyncManager)
    func setChatWebAuthToken(_ token: String?) {
        chatwebBackend?.authToken = token
    }

    /// Set device API key for ChatWeb backend
    func setChatWebBackend(deviceAPIKey: String?) {
        chatwebBackend?.setDeviceAPIKey(deviceAPIKey)
    }

    /// Set model for ChatWeb backend (called from Settings)
    func setChatWebModel(_ modelId: String?) {
        chatwebBackend?.setModel(modelId)
    }

    // MARK: - Speculative Decoding Support

    /// Handle speculative verification response from P2P peer
    func handleSpeculativeVerificationResponse(_ response: SpeculativeVerifyResponseWithId) {
        speculativeBackend?.handleVerificationResponse(response)
    }

    // MARK: - Private Helpers

    private func hasRequiredAPIKey(for mode: ChatMode) -> Bool {
        switch mode {
        case .local, .chatweb, .privateP2P, .publicP2P, .p2pMesh, .speculative:
            return true
        case .fast:
            return keychain.hasAPIKey(for: .groq)
        case .genius:
            // Check if we have an API key for the selected provider
            switch selectedCloudProvider {
            case .openai:
                return keychain.hasAPIKey(for: .openai)
            case .anthropic:
                return keychain.hasAPIKey(for: .anthropic)
            case .google:
                return keychain.hasAPIKey(for: .google)
            }
        }
    }
}
