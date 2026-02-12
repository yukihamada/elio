import Foundation
import StoreKit

/// Manages in-app subscriptions using StoreKit 2
/// - Basic: ¥500/month, 1,000 tokens
/// - Pro: ¥1,500/month, 5,000 tokens
@MainActor
final class SubscriptionManager: ObservableObject {
    static let shared = SubscriptionManager()

    // MARK: - Product IDs

    static let basicProductId = "love.elio.subscription.basic"
    static let proProductId = "love.elio.subscription.pro"

    private let productIds: Set<String> = [
        basicProductId,
        proProductId
    ]

    // MARK: - Published Properties

    @Published private(set) var products: [Product] = []
    @Published private(set) var purchasedSubscriptions: [Product] = []
    @Published private(set) var subscriptionStatus: SubscriptionStatus = .none
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    // MARK: - Private Properties

    private var updateListenerTask: Task<Void, Error>?
    private let tokenManager = TokenManager.shared

    // MARK: - Subscription Status

    enum SubscriptionStatus: Equatable {
        case none
        case basic
        case pro
        case expired

        var tier: SubscriptionTier {
            switch self {
            case .none, .expired: return .free
            case .basic: return .basic
            case .pro: return .pro
            }
        }

        var displayName: String {
            switch self {
            case .none: return String(localized: "subscription.status.none", defaultValue: "No Subscription")
            case .basic: return String(localized: "subscription.status.basic", defaultValue: "Basic")
            case .pro: return String(localized: "subscription.status.pro", defaultValue: "Pro")
            case .expired: return String(localized: "subscription.status.expired", defaultValue: "Expired")
            }
        }
    }

    // MARK: - Initialization

    private init() {
        // Start listening for transaction updates
        updateListenerTask = listenForTransactions()

        // Load products on init
        Task {
            await loadProducts()
            await updateSubscriptionStatus()
        }
    }

    deinit {
        updateListenerTask?.cancel()
    }

    // MARK: - Public Methods

    /// Load available products from App Store
    func loadProducts() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let storeProducts = try await Product.products(for: productIds)
            // Sort by price (Basic first, then Pro)
            products = storeProducts.sorted { $0.price < $1.price }
        } catch {
            errorMessage = "Failed to load products: \(error.localizedDescription)"
        }
    }

    /// Purchase a subscription
    func purchase(_ product: Product) async throws -> Transaction? {
        isLoading = true
        defer { isLoading = false }

        let result = try await product.purchase()

        switch result {
        case .success(let verification):
            let transaction = try checkVerified(verification)

            // Grant tokens based on subscription
            await grantTokensForSubscription(productId: product.id)

            // Finish the transaction
            await transaction.finish()

            // Update status
            await updateSubscriptionStatus()

            return transaction

        case .userCancelled:
            return nil

        case .pending:
            errorMessage = String(localized: "subscription.pending", defaultValue: "Purchase is pending approval")
            return nil

        @unknown default:
            return nil
        }
    }

    /// Restore previous purchases
    func restorePurchases() async {
        isLoading = true
        defer { isLoading = false }

        // Sync with App Store
        try? await AppStore.sync()

        // Update subscription status
        await updateSubscriptionStatus()
    }

    /// Update current subscription status
    func updateSubscriptionStatus() async {
        var newStatus: SubscriptionStatus = .none

        // Check for active subscriptions
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }

            if transaction.productID == Self.proProductId {
                newStatus = .pro
                break // Pro takes precedence
            } else if transaction.productID == Self.basicProductId {
                newStatus = .basic
            }
        }

        subscriptionStatus = newStatus

        // Update purchased products list
        await updatePurchasedProducts()
    }

    /// Get the product for a specific tier
    func product(for tier: SubscriptionTier) -> Product? {
        switch tier {
        case .free: return nil
        case .basic: return products.first { $0.id == Self.basicProductId }
        case .pro: return products.first { $0.id == Self.proProductId }
        }
    }

    // MARK: - Private Methods

    private func listenForTransactions() -> Task<Void, Error> {
        Task.detached {
            // Iterate through any transactions that don't come from a direct call to `purchase()`
            for await result in Transaction.updates {
                do {
                    let transaction = try await self.checkVerified(result)

                    // Grant tokens if this is a renewal
                    await self.grantTokensForSubscription(productId: transaction.productID)

                    // Finish the transaction
                    await transaction.finish()

                    // Update status on main actor
                    await MainActor.run {
                        Task {
                            await self.updateSubscriptionStatus()
                        }
                    }
                } catch {
                    // Transaction failed verification
                    print("Transaction failed verification: \(error)")
                }
            }
        }
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            throw SubscriptionError.verificationFailed
        case .verified(let safe):
            return safe
        }
    }

    private func updatePurchasedProducts() async {
        var purchased: [Product] = []

        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }

            if let product = products.first(where: { $0.id == transaction.productID }) {
                purchased.append(product)
            }
        }

        purchasedSubscriptions = purchased
    }

    private func grantTokensForSubscription(productId: String) async {
        let tier: SubscriptionTier
        if productId == Self.basicProductId {
            tier = .basic
        } else if productId == Self.proProductId {
            tier = .pro
        } else {
            return
        }

        // Grant monthly tokens (local)
        await MainActor.run {
            tokenManager.grantMonthlyTokens(tier: tier)
        }

        // Forward subscription to ChatWeb for credit grant
        await forwardSubscriptionToChatWeb(productId: productId)
    }

    // MARK: - ChatWeb Billing Bridge

    /// Forward subscription verification to ChatWeb's partner API.
    /// Uses the user's ChatWeb auth token to identify the account.
    /// Credits are granted server-side with idempotency protection.
    private func forwardSubscriptionToChatWeb(productId: String) async {
        // Read MainActor-isolated properties
        let (authToken, isLoggedIn, currentCredits) = await MainActor.run {
            let sm = SyncManager.shared
            return (sm.authToken, sm.isLoggedIn, sm.creditsRemaining)
        }

        // Only forward if user is logged in to ChatWeb
        guard let authToken, isLoggedIn else { return }

        // Get the latest verified transaction for this product
        var transactionId: UInt64?
        var originalTransactionId: UInt64?

        for await result in Transaction.currentEntitlements {
            guard case .verified(let tx) = result, tx.productID == productId else { continue }
            transactionId = tx.id
            originalTransactionId = tx.originalID
            break
        }

        guard let txId = transactionId, let origTxId = originalTransactionId else { return }

        let body: [String: Any] = [
            "product_id": productId,
            "transaction_id": String(txId),
            "original_transaction_id": String(origTxId)
        ]

        guard let url = URL(string: "https://api.chatweb.ai/api/v1/partner/verify-subscription"),
              let httpBody = try? JSONSerialization.data(withJSONObject: body) else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Elio Chat iOS", forHTTPHeaderField: "User-Agent")
        request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = httpBody

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let creditsGranted = json["credits_granted"] as? Int {
                    print("[ChatWeb Bridge] Granted \(creditsGranted) credits for \(productId)")

                    // Update local credit display
                    await MainActor.run {
                        SyncManager.shared.updateCreditsFromEvent(
                            credits: currentCredits + creditsGranted
                        )
                    }
                }
            } else {
                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
                print("[ChatWeb Bridge] Failed with status \(statusCode) for \(productId)")
            }
        } catch {
            // Don't block subscription flow on ChatWeb failure
            print("[ChatWeb Bridge] Error: \(error.localizedDescription)")
        }
    }
}

// MARK: - Subscription Errors

enum SubscriptionError: Error, LocalizedError {
    case verificationFailed
    case purchaseFailed
    case productNotFound

    var errorDescription: String? {
        switch self {
        case .verificationFailed:
            return String(localized: "subscription.error.verification", defaultValue: "Purchase verification failed")
        case .purchaseFailed:
            return String(localized: "subscription.error.purchase", defaultValue: "Purchase failed")
        case .productNotFound:
            return String(localized: "subscription.error.product.not.found", defaultValue: "Product not found")
        }
    }
}

// MARK: - Product Extensions

extension Product {
    /// Formatted price string
    var formattedPrice: String {
        displayPrice
    }

    /// Monthly tokens for this subscription
    var monthlyTokens: Int {
        if id == SubscriptionManager.basicProductId {
            return TokenManager.basicMonthlyTokens
        } else if id == SubscriptionManager.proProductId {
            return TokenManager.proMonthlyTokens
        }
        return 0
    }

    /// Subscription tier
    var tier: SubscriptionTier {
        if id == SubscriptionManager.basicProductId {
            return .basic
        } else if id == SubscriptionManager.proProductId {
            return .pro
        }
        return .free
    }
}
