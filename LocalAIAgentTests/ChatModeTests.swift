import XCTest
@testable import LocalAIAgent

/// Tests for ChatMode, CloudProvider, and InferenceBackend protocol
@MainActor
final class ChatModeTests: XCTestCase {

    // MARK: - ChatMode Tests

    func testChatModeRawValues() {
        XCTAssertEqual(ChatMode.local.rawValue, "local")
        XCTAssertEqual(ChatMode.chatweb.rawValue, "chatweb")
        XCTAssertEqual(ChatMode.privateP2P.rawValue, "private")
        XCTAssertEqual(ChatMode.fast.rawValue, "fast")
        XCTAssertEqual(ChatMode.genius.rawValue, "genius")
        XCTAssertEqual(ChatMode.publicP2P.rawValue, "public")
    }

    func testChatModeFromRawValue() {
        XCTAssertEqual(ChatMode(rawValue: "local"), .local)
        XCTAssertEqual(ChatMode(rawValue: "chatweb"), .chatweb)
        XCTAssertEqual(ChatMode(rawValue: "private"), .privateP2P)
        XCTAssertEqual(ChatMode(rawValue: "fast"), .fast)
        XCTAssertEqual(ChatMode(rawValue: "genius"), .genius)
        XCTAssertEqual(ChatMode(rawValue: "public"), .publicP2P)
        XCTAssertNil(ChatMode(rawValue: "invalid"))
    }

    func testChatModeTokenCost() {
        XCTAssertEqual(ChatMode.local.tokenCost, 0, "Local mode should be free")
        XCTAssertEqual(ChatMode.chatweb.tokenCost, 0, "ChatWeb mode should be free")
        XCTAssertEqual(ChatMode.privateP2P.tokenCost, 0, "Private P2P mode should be free")
        XCTAssertEqual(ChatMode.fast.tokenCost, 1, "Fast mode should cost 1 token")
        XCTAssertEqual(ChatMode.genius.tokenCost, 5, "Genius mode should cost 5 tokens")
        XCTAssertEqual(ChatMode.publicP2P.tokenCost, 2, "Public P2P mode should cost 2 tokens")
    }

    func testChatModeDisplayName() {
        XCTAssertFalse(ChatMode.local.displayName.isEmpty)
        XCTAssertFalse(ChatMode.chatweb.displayName.isEmpty)
        XCTAssertFalse(ChatMode.privateP2P.displayName.isEmpty)
        XCTAssertFalse(ChatMode.fast.displayName.isEmpty)
        XCTAssertFalse(ChatMode.genius.displayName.isEmpty)
        XCTAssertFalse(ChatMode.publicP2P.displayName.isEmpty)
    }

    func testChatModeIcon() {
        XCTAssertFalse(ChatMode.local.icon.isEmpty)
        XCTAssertFalse(ChatMode.chatweb.icon.isEmpty)
        XCTAssertFalse(ChatMode.privateP2P.icon.isEmpty)
        XCTAssertFalse(ChatMode.fast.icon.isEmpty)
        XCTAssertFalse(ChatMode.genius.icon.isEmpty)
        XCTAssertFalse(ChatMode.publicP2P.icon.isEmpty)
    }

    func testChatModeRequiresNetwork() {
        XCTAssertFalse(ChatMode.local.requiresNetwork, "Local mode should not require network")
        XCTAssertTrue(ChatMode.chatweb.requiresNetwork, "ChatWeb mode requires network")
        XCTAssertTrue(ChatMode.privateP2P.requiresNetwork, "Private P2P mode requires network")
        XCTAssertTrue(ChatMode.fast.requiresNetwork, "Fast mode requires network")
        XCTAssertTrue(ChatMode.genius.requiresNetwork, "Genius mode requires network")
        XCTAssertTrue(ChatMode.publicP2P.requiresNetwork, "Public P2P mode requires network")
    }

    func testChatModeRequiresAPIKey() {
        XCTAssertFalse(ChatMode.local.requiresAPIKey, "Local mode should not require API key")
        XCTAssertFalse(ChatMode.chatweb.requiresAPIKey, "ChatWeb mode should not require API key")
        XCTAssertFalse(ChatMode.privateP2P.requiresAPIKey, "Private P2P mode should not require API key")
        XCTAssertTrue(ChatMode.fast.requiresAPIKey, "Fast mode requires API key")
        XCTAssertTrue(ChatMode.genius.requiresAPIKey, "Genius mode requires API key")
        XCTAssertFalse(ChatMode.publicP2P.requiresAPIKey, "Public P2P mode should not require API key")
    }

    func testChatModeCaseIterable() {
        XCTAssertEqual(ChatMode.allCases.count, 6)
        XCTAssertTrue(ChatMode.allCases.contains(.local))
        XCTAssertTrue(ChatMode.allCases.contains(.chatweb))
        XCTAssertTrue(ChatMode.allCases.contains(.privateP2P))
        XCTAssertTrue(ChatMode.allCases.contains(.fast))
        XCTAssertTrue(ChatMode.allCases.contains(.genius))
        XCTAssertTrue(ChatMode.allCases.contains(.publicP2P))
    }

    func testChatModeIdentifiable() {
        XCTAssertEqual(ChatMode.local.id, "local")
        XCTAssertEqual(ChatMode.chatweb.id, "chatweb")
        XCTAssertEqual(ChatMode.privateP2P.id, "private")
        XCTAssertEqual(ChatMode.fast.id, "fast")
        XCTAssertEqual(ChatMode.genius.id, "genius")
        XCTAssertEqual(ChatMode.publicP2P.id, "public")
    }

    func testChatModeIsP2P() {
        XCTAssertFalse(ChatMode.local.isP2P)
        XCTAssertFalse(ChatMode.chatweb.isP2P)
        XCTAssertTrue(ChatMode.privateP2P.isP2P)
        XCTAssertFalse(ChatMode.fast.isP2P)
        XCTAssertFalse(ChatMode.genius.isP2P)
        XCTAssertTrue(ChatMode.publicP2P.isP2P)
    }

    func testChatWebModeProperties() {
        let mode = ChatMode.chatweb
        XCTAssertEqual(mode.rawValue, "chatweb")
        XCTAssertEqual(mode.tokenCost, 0)
        XCTAssertEqual(mode.icon, "cloud.fill")
        XCTAssertTrue(mode.requiresNetwork)
        XCTAssertFalse(mode.requiresAPIKey)
        XCTAssertFalse(mode.isP2P)
    }

    // MARK: - CloudProvider Tests

    func testCloudProviderRawValues() {
        XCTAssertEqual(CloudProvider.openai.rawValue, "openai")
        XCTAssertEqual(CloudProvider.anthropic.rawValue, "anthropic")
        XCTAssertEqual(CloudProvider.google.rawValue, "google")
    }

    func testCloudProviderFromRawValue() {
        XCTAssertEqual(CloudProvider(rawValue: "openai"), .openai)
        XCTAssertEqual(CloudProvider(rawValue: "anthropic"), .anthropic)
        XCTAssertEqual(CloudProvider(rawValue: "google"), .google)
        XCTAssertNil(CloudProvider(rawValue: "invalid"))
    }

    func testCloudProviderDisplayName() {
        XCTAssertFalse(CloudProvider.openai.displayName.isEmpty)
        XCTAssertFalse(CloudProvider.anthropic.displayName.isEmpty)
        XCTAssertFalse(CloudProvider.google.displayName.isEmpty)
    }

    func testCloudProviderModelName() {
        // Model names should be non-empty
        XCTAssertFalse(CloudProvider.openai.defaultModel.isEmpty)
        XCTAssertFalse(CloudProvider.anthropic.defaultModel.isEmpty)
        XCTAssertFalse(CloudProvider.google.defaultModel.isEmpty)
    }

    func testCloudProviderBaseURL() {
        // Verify base URLs are valid HTTPS URLs
        for provider in CloudProvider.allCases {
            XCTAssertTrue(provider.baseURL.hasPrefix("https://"), "\(provider) should have HTTPS URL")
            XCTAssertNotNil(URL(string: provider.baseURL), "\(provider) should have valid URL")
        }
    }

    func testCloudProviderCaseIterable() {
        XCTAssertEqual(CloudProvider.allCases.count, 3)
        XCTAssertTrue(CloudProvider.allCases.contains(.openai))
        XCTAssertTrue(CloudProvider.allCases.contains(.anthropic))
        XCTAssertTrue(CloudProvider.allCases.contains(.google))
    }

    func testCloudProviderIdentifiable() {
        XCTAssertEqual(CloudProvider.openai.id, "openai")
        XCTAssertEqual(CloudProvider.anthropic.id, "anthropic")
        XCTAssertEqual(CloudProvider.google.id, "google")
    }

    // MARK: - InferenceError Tests

    func testInferenceErrorTypes() {
        let notReady = InferenceError.notReady
        let insufficientTokens = InferenceError.insufficientTokens
        let networkError = InferenceError.networkError("Connection failed")
        let apiKeyMissing = InferenceError.apiKeyMissing
        let serverError = InferenceError.serverError(500, "Internal error")
        let invalidResponse = InferenceError.invalidResponse

        // Verify errors are not equal to each other
        XCTAssertNotNil(notReady.errorDescription)
        XCTAssertNotNil(insufficientTokens.errorDescription)
        XCTAssertNotNil(networkError.errorDescription)
        XCTAssertNotNil(apiKeyMissing.errorDescription)
        XCTAssertNotNil(serverError.errorDescription)
        XCTAssertNotNil(invalidResponse.errorDescription)
    }

    func testInferenceErrorDescriptions() {
        let networkError = InferenceError.networkError("Test connection error")
        let serverError = InferenceError.serverError(404, "Not found")

        // Verify error descriptions contain the provided info
        XCTAssertTrue(networkError.errorDescription?.contains("Test connection error") ?? false)
        XCTAssertTrue(serverError.errorDescription?.contains("Not found") ?? false)
    }
}
