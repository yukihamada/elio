import Foundation

// MARK: - EBR Token Gate

/// Verifies EBR token balance on Solana to gate ledger server eligibility.
/// - Minimum 1,000 EBR tokens required for ledger server access
/// - Balance cached for 5 minutes to reduce RPC calls
/// - Phantom Wallet deep link integration for wallet connection
@MainActor
final class EBRTokenGate: ObservableObject {
    static let shared = EBRTokenGate()

    // MARK: - Constants

    /// EBR SPL Token mint address on Solana mainnet
    static let ebrMintAddress = "E1JxwaWRd8nw8vDdWMdqwdbXGBshqDcnTcinHzNMqg2Y"

    /// Minimum EBR balance required for ledger server eligibility
    static let minimumBalance: UInt64 = 1_000

    /// Cache duration in seconds (5 minutes)
    private static let cacheDuration: TimeInterval = 300

    /// Solana mainnet RPC endpoint
    private static let rpcURL = URL(string: "https://api.mainnet-beta.solana.com")!

    /// App callback scheme for Phantom Wallet
    private static let callbackScheme = "elio"

    // MARK: - Published Properties

    @Published private(set) var walletAddress: String?
    @Published private(set) var ebrBalance: UInt64 = 0
    @Published private(set) var isEligible: Bool = false
    @Published private(set) var isVerifying: Bool = false
    @Published private(set) var lastVerification: EBRVerification?
    @Published var errorMessage: String?

    // MARK: - Persistence Keys

    private let walletAddressKey = "ebr_wallet_address"

    // MARK: - Private Properties

    private let urlSession: URLSession
    private var cachedVerification: EBRVerification?

    // MARK: - Initialization

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        urlSession = URLSession(configuration: config)

        // Restore saved wallet address
        walletAddress = UserDefaults.standard.string(forKey: walletAddressKey)
    }

    // MARK: - Public Methods

    /// Set and persist the user's Solana wallet address.
    func setWalletAddress(_ address: String) {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        walletAddress = trimmed
        UserDefaults.standard.set(trimmed, forKey: walletAddressKey)

        // Invalidate cache when address changes
        cachedVerification = nil
        lastVerification = nil
        ebrBalance = 0
        isEligible = false
    }

    /// Clear the stored wallet address and reset state.
    func disconnectWallet() {
        walletAddress = nil
        UserDefaults.standard.removeObject(forKey: walletAddressKey)
        cachedVerification = nil
        lastVerification = nil
        ebrBalance = 0
        isEligible = false
        errorMessage = nil
    }

    /// Verify EBR token balance for the current wallet address.
    /// Returns cached result if still valid (within 5-minute window).
    @discardableResult
    func verifyBalance() async -> EBRVerification? {
        guard let address = walletAddress else {
            errorMessage = "No wallet address configured"
            return nil
        }

        // Return cached result if still valid
        if let cached = cachedVerification,
           Date().timeIntervalSince(cached.timestamp) < Self.cacheDuration {
            return cached
        }

        isVerifying = true
        errorMessage = nil
        defer { isVerifying = false }

        do {
            let balance = try await fetchEBRBalance(for: address)
            let eligible = balance >= Self.minimumBalance

            let verification = EBRVerification(
                timestamp: Date(),
                balance: balance,
                isEligible: eligible,
                walletAddress: address
            )

            ebrBalance = balance
            isEligible = eligible
            lastVerification = verification
            cachedVerification = verification

            return verification
        } catch {
            errorMessage = "Verification failed: \(error.localizedDescription)"
            return nil
        }
    }

    /// Force a fresh balance check, ignoring cache.
    @discardableResult
    func forceRefresh() async -> EBRVerification? {
        cachedVerification = nil
        return await verifyBalance()
    }

    /// Generate a Phantom Wallet deep link URL for wallet connection.
    /// Opens Phantom to authorize the connection and returns to Elio via callback.
    func phantomConnectURL() -> URL? {
        var components = URLComponents()
        components.scheme = "phantom"
        components.host = "v1"
        components.path = "/connect"

        let callbackURL = "\(Self.callbackScheme)://phantom-connect"

        components.queryItems = [
            URLQueryItem(name: "app_url", value: "https://elio.love"),
            URLQueryItem(name: "dapp_encryption_public_key", value: ""),
            URLQueryItem(name: "redirect_link", value: callbackURL),
            URLQueryItem(name: "cluster", value: "mainnet-beta")
        ]

        return components.url
    }

    /// Check whether the cached verification is still valid.
    var isCacheValid: Bool {
        guard let cached = cachedVerification else { return false }
        return Date().timeIntervalSince(cached.timestamp) < Self.cacheDuration
    }

    // MARK: - Private Methods

    /// Fetch EBR token balance from Solana RPC using getTokenAccountsByOwner.
    private func fetchEBRBalance(for ownerAddress: String) async throws -> UInt64 {
        let requestBody: [String: Any] = [
            "jsonrpc": "2.0",
            "id": 1,
            "method": "getTokenAccountsByOwner",
            "params": [
                ownerAddress,
                ["mint": Self.ebrMintAddress],
                ["encoding": "jsonParsed"]
            ]
        ]

        guard let bodyData = try? JSONSerialization.data(withJSONObject: requestBody) else {
            throw EBRTokenGateError.invalidRequest
        }

        var request = URLRequest(url: Self.rpcURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = bodyData

        let (data, response) = try await urlSession.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw EBRTokenGateError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            throw EBRTokenGateError.httpError(statusCode: httpResponse.statusCode)
        }

        let rpcResponse = try JSONDecoder().decode(SolanaRPCResponse.self, from: data)

        if let error = rpcResponse.error {
            throw EBRTokenGateError.rpcError(code: error.code, message: error.message)
        }

        // Sum balances across all token accounts for this mint
        let totalBalance = rpcResponse.result?.value.reduce(UInt64(0)) { sum, account in
            let amount = account.account.data.parsed.info.tokenAmount.amount
            return sum + (UInt64(amount) ?? 0)
        } ?? 0

        return totalBalance
    }
}

// MARK: - Supporting Types

/// Result of an EBR token balance verification.
struct EBRVerification: Codable {
    let timestamp: Date
    let balance: UInt64
    let isEligible: Bool
    let walletAddress: String

    /// Human-readable summary of the verification result.
    var summary: String {
        let status = isEligible ? "Eligible" : "Not eligible"
        return "\(status) — \(balance) EBR (minimum: \(EBRTokenGate.minimumBalance))"
    }
}

// MARK: - Solana RPC Response Types

/// Top-level JSON-RPC response from Solana.
struct SolanaRPCResponse: Codable {
    let jsonrpc: String
    let id: Int
    let result: SolanaRPCResult?
    let error: SolanaRPCError?
}

struct SolanaRPCError: Codable {
    let code: Int
    let message: String
}

struct SolanaRPCResult: Codable {
    let context: SolanaRPCContext
    let value: [TokenAccountEntry]
}

struct SolanaRPCContext: Codable {
    let slot: UInt64
}

struct TokenAccountEntry: Codable {
    let pubkey: String
    let account: TokenAccountData
}

struct TokenAccountData: Codable {
    let data: TokenAccountParsedData
    let lamports: UInt64
    let owner: String
    let executable: Bool
    let rentEpoch: UInt64?
}

struct TokenAccountParsedData: Codable {
    let parsed: TokenAccountParsedInfo
    let program: String
    let space: Int
}

struct TokenAccountParsedInfo: Codable {
    let info: TokenAccountInfo
    let type: String
}

/// Parsed SPL token account information.
struct TokenAccountInfo: Codable {
    let isNative: Bool
    let mint: String
    let owner: String
    let state: String
    let tokenAmount: TokenAmount
}

struct TokenAmount: Codable {
    /// Raw amount as a string (to avoid integer overflow)
    let amount: String
    /// Number of decimals for the token
    let decimals: Int
    /// Human-readable amount as a float
    let uiAmount: Double?
    /// Human-readable amount as a string
    let uiAmountString: String?
}

// MARK: - Errors

enum EBRTokenGateError: Error, LocalizedError {
    case invalidRequest
    case invalidResponse
    case httpError(statusCode: Int)
    case rpcError(code: Int, message: String)
    case noWalletConfigured

    var errorDescription: String? {
        switch self {
        case .invalidRequest:
            return "Failed to construct RPC request"
        case .invalidResponse:
            return "Invalid response from Solana RPC"
        case .httpError(let statusCode):
            return "Solana RPC returned HTTP \(statusCode)"
        case .rpcError(let code, let message):
            return "Solana RPC error \(code): \(message)"
        case .noWalletConfigured:
            return "No Solana wallet address configured"
        }
    }
}
