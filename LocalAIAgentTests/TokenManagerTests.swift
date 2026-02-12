import XCTest
@testable import LocalAIAgent

/// Tests for TokenManager and related token economy functionality
@MainActor
final class TokenManagerTests: XCTestCase {

    // MARK: - Token Transaction Tests

    func testTokenTransactionCreation() throws {
        let transaction = TokenTransaction(
            type: .earned,
            amount: 100,
            reason: "Test",
            timestamp: Date()
        )

        XCTAssertEqual(transaction.type, .earned)
        XCTAssertEqual(transaction.amount, 100)
        XCTAssertEqual(transaction.reason, "Test")
        XCTAssertNotNil(transaction.id)
    }

    func testTokenTransactionCodable() throws {
        let original = TokenTransaction(
            type: .spent,
            amount: 50,
            reason: "Fast Mode",
            timestamp: Date()
        )

        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(TokenTransaction.self, from: encoded)

        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.type, original.type)
        XCTAssertEqual(decoded.amount, original.amount)
        XCTAssertEqual(decoded.reason, original.reason)
    }

    // MARK: - Spend/Earn Reason Tests

    func testSpendReasonRawValues() {
        XCTAssertEqual(SpendReason.fastMode.rawValue, "Fast Mode")
        XCTAssertEqual(SpendReason.geniusMode.rawValue, "Genius Mode")
        XCTAssertEqual(SpendReason.p2pRequest.rawValue, "P2P Request")
    }

    func testEarnReasonRawValues() {
        XCTAssertEqual(EarnReason.initialGrant.rawValue, "Welcome Bonus")
        XCTAssertEqual(EarnReason.subscription.rawValue, "Monthly Subscription")
        XCTAssertEqual(EarnReason.p2pServing.rawValue, "P2P Server Reward")
        XCTAssertEqual(EarnReason.referral.rawValue, "Referral Bonus")
    }

    // MARK: - Subscription Tier Tests

    func testSubscriptionTierProperties() {
        XCTAssertEqual(SubscriptionTier.free.monthlyTokens, 0)
        XCTAssertEqual(SubscriptionTier.basic.monthlyTokens, 1000)
        XCTAssertEqual(SubscriptionTier.pro.monthlyTokens, 5000)

        XCTAssertEqual(SubscriptionTier.free.monthlyPrice, "¥0")
        XCTAssertEqual(SubscriptionTier.basic.monthlyPrice, "¥500")
        XCTAssertEqual(SubscriptionTier.pro.monthlyPrice, "¥1,500")
    }

    func testSubscriptionTierIdentifiable() {
        XCTAssertEqual(SubscriptionTier.free.id, "free")
        XCTAssertEqual(SubscriptionTier.basic.id, "basic")
        XCTAssertEqual(SubscriptionTier.pro.id, "pro")
    }

    func testSubscriptionTierCaseIterable() {
        XCTAssertEqual(SubscriptionTier.allCases.count, 3)
        XCTAssertTrue(SubscriptionTier.allCases.contains(.free))
        XCTAssertTrue(SubscriptionTier.allCases.contains(.basic))
        XCTAssertTrue(SubscriptionTier.allCases.contains(.pro))
    }

    func testSubscriptionTierDisplayName() {
        // Just verify they return non-empty strings
        XCTAssertFalse(SubscriptionTier.free.displayName.isEmpty)
        XCTAssertFalse(SubscriptionTier.basic.displayName.isEmpty)
        XCTAssertFalse(SubscriptionTier.pro.displayName.isEmpty)
    }

    // MARK: - TokenManager Constants Tests

    func testTokenManagerConstants() {
        XCTAssertEqual(TokenManager.initialGrant, 100)
        XCTAssertEqual(TokenManager.basicMonthlyTokens, 1000)
        XCTAssertEqual(TokenManager.proMonthlyTokens, 5000)
        XCTAssertEqual(TokenManager.p2pEarnRate, 1)
    }

    // MARK: - TokenManager Singleton Tests

    func testTokenManagerSharedInstance() {
        let manager1 = TokenManager.shared
        let manager2 = TokenManager.shared
        XCTAssertTrue(manager1 === manager2, "Should return same instance")
    }

    func testTokenManagerHasBalance() {
        let manager = TokenManager.shared
        XCTAssertGreaterThanOrEqual(manager.balance, 0, "Balance should be non-negative")
    }
}
