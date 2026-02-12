import Foundation
import SwiftUI

/// Manages token balance for the hybrid AI platform
/// - Free users: 100 tokens (initial grant)
/// - Basic: 1,000 tokens/month (¥500)
/// - Pro: 5,000 tokens/month (¥1,500)
/// - P2P Server: Earn 1 token per request served
@MainActor
final class TokenManager: ObservableObject {
    static let shared = TokenManager()

    // MARK: - Published Properties

    @Published private(set) var balance: Int = 100
    @Published private(set) var totalEarned: Int = 0
    @Published private(set) var totalSpent: Int = 0
    @Published private(set) var transactions: [TokenTransaction] = []

    // MARK: - Persistence Keys

    private let balanceKey = "token_balance"
    private let totalEarnedKey = "token_total_earned"
    private let totalSpentKey = "token_total_spent"
    private let transactionsKey = "token_transactions"
    private let initialGrantKey = "token_initial_grant_given"

    // MARK: - Constants

    static let initialGrant = 100
    static let basicMonthlyTokens = 1000
    static let proMonthlyTokens = 5000
    static let p2pEarnRate = 1
    static let relayEarnRate = 1

    private init() {
        loadState()
        grantInitialTokensIfNeeded()
    }

    // MARK: - Public Methods

    /// Check if user can afford a certain cost
    func canAfford(_ cost: Int) -> Bool {
        balance >= cost
    }

    /// Spend tokens for a message
    /// - Throws: InferenceError.insufficientTokens if not enough tokens
    func spend(_ amount: Int, reason: SpendReason) throws {
        guard canAfford(amount) else {
            throw InferenceError.insufficientTokens
        }

        balance -= amount
        totalSpent += amount

        let transaction = TokenTransaction(
            type: .spent,
            amount: amount,
            reason: reason.rawValue,
            timestamp: Date()
        )
        transactions.insert(transaction, at: 0)

        // Keep only last 100 transactions
        if transactions.count > 100 {
            transactions = Array(transactions.prefix(100))
        }

        saveState()
    }

    /// Earn tokens (from P2P serving, etc.)
    func earn(_ amount: Int, reason: EarnReason) {
        balance += amount
        totalEarned += amount

        let transaction = TokenTransaction(
            type: .earned,
            amount: amount,
            reason: reason.rawValue,
            timestamp: Date()
        )
        transactions.insert(transaction, at: 0)

        // Keep only last 100 transactions
        if transactions.count > 100 {
            transactions = Array(transactions.prefix(100))
        }

        saveState()
    }

    /// Grant monthly subscription tokens
    func grantMonthlyTokens(tier: SubscriptionTier) {
        let amount: Int
        switch tier {
        case .free:
            return // No monthly grant for free tier
        case .basic:
            amount = Self.basicMonthlyTokens
        case .pro:
            amount = Self.proMonthlyTokens
        }

        balance += amount
        totalEarned += amount

        let transaction = TokenTransaction(
            type: .earned,
            amount: amount,
            reason: EarnReason.subscription.rawValue,
            timestamp: Date()
        )
        transactions.insert(transaction, at: 0)

        saveState()
    }

    /// Get transactions for the current week
    func weeklyTransactions() -> [TokenTransaction] {
        let calendar = Calendar.current
        let weekAgo = calendar.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        return transactions.filter { $0.timestamp >= weekAgo }
    }

    /// Calculate weekly earnings
    func weeklyEarnings() -> Int {
        weeklyTransactions()
            .filter { $0.type == .earned }
            .reduce(0) { $0 + $1.amount }
    }

    /// Calculate weekly spending
    func weeklySpending() -> Int {
        weeklyTransactions()
            .filter { $0.type == .spent }
            .reduce(0) { $0 + $1.amount }
    }

    // MARK: - Private Methods

    private func loadState() {
        let defaults = UserDefaults.standard
        balance = defaults.integer(forKey: balanceKey)
        totalEarned = defaults.integer(forKey: totalEarnedKey)
        totalSpent = defaults.integer(forKey: totalSpentKey)

        if let data = defaults.data(forKey: transactionsKey),
           let decoded = try? JSONDecoder().decode([TokenTransaction].self, from: data) {
            transactions = decoded
        }
    }

    private func saveState() {
        let defaults = UserDefaults.standard
        defaults.set(balance, forKey: balanceKey)
        defaults.set(totalEarned, forKey: totalEarnedKey)
        defaults.set(totalSpent, forKey: totalSpentKey)

        if let data = try? JSONEncoder().encode(transactions) {
            defaults.set(data, forKey: transactionsKey)
        }
    }

    private func grantInitialTokensIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: initialGrantKey) else { return }

        balance = Self.initialGrant
        let transaction = TokenTransaction(
            type: .earned,
            amount: Self.initialGrant,
            reason: EarnReason.initialGrant.rawValue,
            timestamp: Date()
        )
        transactions.insert(transaction, at: 0)

        defaults.set(true, forKey: initialGrantKey)
        saveState()
    }
}

// MARK: - Supporting Types

struct TokenTransaction: Codable, Identifiable {
    let id: UUID
    let type: TransactionType
    let amount: Int
    let reason: String
    let timestamp: Date

    init(id: UUID = UUID(), type: TransactionType, amount: Int, reason: String, timestamp: Date) {
        self.id = id
        self.type = type
        self.amount = amount
        self.reason = reason
        self.timestamp = timestamp
    }

    enum TransactionType: String, Codable {
        case spent
        case earned
    }
}

enum SpendReason: String {
    case fastMode = "Fast Mode"
    case geniusMode = "Genius Mode"
    case p2pRequest = "P2P Request"
    case skillPurchase = "Skill Purchase"
}

enum EarnReason: String {
    case initialGrant = "Welcome Bonus"
    case subscription = "Monthly Subscription"
    case p2pServing = "P2P Server Reward"
    case relayServing = "Relay Server Reward"
    case referral = "Referral Bonus"
}

enum SubscriptionTier: String, Codable, CaseIterable, Identifiable {
    case free = "free"
    case basic = "basic"
    case pro = "pro"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .free: return String(localized: "subscription.free", defaultValue: "Free")
        case .basic: return String(localized: "subscription.basic", defaultValue: "Basic")
        case .pro: return String(localized: "subscription.pro", defaultValue: "Pro")
        }
    }

    var monthlyTokens: Int {
        switch self {
        case .free: return 0
        case .basic: return TokenManager.basicMonthlyTokens
        case .pro: return TokenManager.proMonthlyTokens
        }
    }

    var monthlyPrice: String {
        switch self {
        case .free: return "¥0"
        case .basic: return "¥500"
        case .pro: return "¥1,500"
        }
    }
}
