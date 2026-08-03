import Foundation

/// Manages on-chain reward synchronization for DePIN node operators.
///
/// Rewards earned locally via TokenManager are periodically synced to Solana
/// using batch transactions for gas efficiency (100 queries per tx).
///
/// Flow:
/// 1. Local TokenManager records earnings per query
/// 2. OnChainRewards accumulates pending rewards
/// 3. At batch threshold (100 queries), creates reward proof
/// 4. Submits proof to server-side verifier for EBR token distribution
///
/// Note: Actual token minting requires server-side mint authority validation.
@MainActor
final class OnChainRewards: ObservableObject {
    static let shared = OnChainRewards()

    // MARK: - Constants

    /// EBR token mint address on Solana mainnet
    static let ebrMintAddress = "E1JxwaWRd8nw8vDdWMdqwdbXGBshqDcnTcinHzNMqg2Y"

    /// ENAI token mint address
    static let enaiMintAddress = "8CeusiVAeibuBGv5xcf7kt7JQZzqwTS5pD7u2CfyoWnL"

    /// Treasury wallet for reward distribution
    static let treasuryWallet = "DK29rBGCvP83LUNjUGVM6xt6qPy6rycBFopXbFkg9XvQ"

    /// Number of queries to batch before submitting on-chain
    static let batchThreshold = 100

    /// Reward verification endpoint
    static let verificationEndpoint = "https://api.elio.love/v1/depin/verify-rewards"

    // MARK: - Published Properties

    @Published private(set) var pendingRewards: Int = 0
    @Published private(set) var pendingQueries: Int = 0
    @Published private(set) var totalSynced: Int = 0
    @Published private(set) var lastSyncDate: Date?
    @Published private(set) var syncStatus: SyncStatus = .idle
    @Published private(set) var walletAddress: String?

    // MARK: - Private Properties

    private var pendingProofs: [RewardProof] = []
    private let persistenceKey = "onchain_rewards_state"

    // MARK: - Init

    private init() {
        loadState()
    }

    // MARK: - Public API

    /// Record a completed query for future on-chain sync.
    func recordQueryReward(
        queryHash: String,
        responseHash: String,
        tokensEarned: Int,
        confidence: Double,
        responseTimeMs: Double
    ) {
        let proof = RewardProof(
            queryHash: queryHash,
            responseHash: responseHash,
            tokensEarned: tokensEarned,
            confidence: confidence,
            responseTimeMs: responseTimeMs,
            timestamp: Date(),
            deviceId: DeviceIdentityManager.shared.elioId
        )

        pendingProofs.append(proof)
        pendingRewards += tokensEarned
        pendingQueries += 1

        saveState()

        // Auto-sync when batch threshold is reached
        if pendingQueries >= Self.batchThreshold {
            Task {
                await syncToChain()
            }
        }
    }

    /// Set the user's Solana wallet address for reward receipt.
    func setWalletAddress(_ address: String) {
        walletAddress = address
        UserDefaults.standard.set(address, forKey: "solana_wallet_address")
    }

    /// Manually trigger on-chain sync (regardless of batch threshold).
    func syncToChain() async {
        guard !pendingProofs.isEmpty else { return }
        guard let wallet = walletAddress else {
            syncStatus = .error("No wallet connected")
            return
        }

        syncStatus = .syncing

        do {
            let batch = RewardBatch(
                proofs: pendingProofs,
                totalTokens: pendingRewards,
                walletAddress: wallet,
                batchTimestamp: Date()
            )

            let success = try await submitBatch(batch)

            if success {
                totalSynced += pendingRewards
                lastSyncDate = Date()
                pendingProofs.removeAll()
                pendingRewards = 0
                pendingQueries = 0
                syncStatus = .synced
                saveState()
            } else {
                syncStatus = .error("Verification failed")
            }
        } catch {
            syncStatus = .error(error.localizedDescription)
        }
    }

    // MARK: - Network

    /// Submit a batch of reward proofs to the verification server.
    private func submitBatch(_ batch: RewardBatch) async throws -> Bool {
        guard let url = URL(string: Self.verificationEndpoint) else {
            throw OnChainError.invalidEndpoint
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(batch)
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw OnChainError.invalidResponse
        }

        if httpResponse.statusCode == 200 {
            if let result = try? JSONDecoder().decode(SyncResult.self, from: data) {
                return result.success
            }
            return true
        } else if httpResponse.statusCode == 503 {
            // Service not yet available — store locally for later
            syncStatus = .pendingServerSetup
            return false
        }

        return false
    }

    // MARK: - Persistence

    private func loadState() {
        let defaults = UserDefaults.standard
        totalSynced = defaults.integer(forKey: "\(persistenceKey)_totalSynced")
        pendingRewards = defaults.integer(forKey: "\(persistenceKey)_pendingRewards")
        pendingQueries = defaults.integer(forKey: "\(persistenceKey)_pendingQueries")
        walletAddress = defaults.string(forKey: "solana_wallet_address")

        if let date = defaults.object(forKey: "\(persistenceKey)_lastSync") as? Date {
            lastSyncDate = date
        }

        if let data = defaults.data(forKey: "\(persistenceKey)_proofs"),
           let proofs = try? JSONDecoder().decode([RewardProof].self, from: data) {
            pendingProofs = proofs
        }
    }

    private func saveState() {
        let defaults = UserDefaults.standard
        defaults.set(totalSynced, forKey: "\(persistenceKey)_totalSynced")
        defaults.set(pendingRewards, forKey: "\(persistenceKey)_pendingRewards")
        defaults.set(pendingQueries, forKey: "\(persistenceKey)_pendingQueries")
        defaults.set(lastSyncDate, forKey: "\(persistenceKey)_lastSync")

        if let data = try? JSONEncoder().encode(pendingProofs) {
            defaults.set(data, forKey: "\(persistenceKey)_proofs")
        }
    }
}

// MARK: - Supporting Types

enum SyncStatus: Equatable {
    case idle
    case syncing
    case synced
    case pendingServerSetup
    case error(String)
}

struct RewardProof: Codable {
    let queryHash: String
    let responseHash: String
    let tokensEarned: Int
    let confidence: Double
    let responseTimeMs: Double
    let timestamp: Date
    let deviceId: String
}

struct RewardBatch: Codable {
    let proofs: [RewardProof]
    let totalTokens: Int
    let walletAddress: String
    let batchTimestamp: Date
}

struct SyncResult: Codable {
    let success: Bool
    let txHash: String?
    let message: String?
}

enum OnChainError: Error, LocalizedError {
    case invalidEndpoint
    case invalidResponse
    case serverError(String)

    var errorDescription: String? {
        switch self {
        case .invalidEndpoint: return "Invalid verification endpoint"
        case .invalidResponse: return "Invalid server response"
        case .serverError(let msg): return "Server error: \(msg)"
        }
    }
}
