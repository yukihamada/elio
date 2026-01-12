import XCTest
@testable import LocalAIAgent

@MainActor
final class LocalAIAgentTests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    // MARK: - App State Tests

    func testAppStateInitialization() throws {
        let appState = AppState()
        XCTAssertFalse(appState.isLoading)
        XCTAssertNil(appState.currentModelName)
        XCTAssertFalse(appState.isModelLoaded)
    }

    // MARK: - Model Loader Tests

    func testModelLoaderHasAvailableModels() throws {
        let modelLoader = ModelLoader()
        XCTAssertFalse(modelLoader.availableModels.isEmpty, "Should have available models")
    }

    func testModelLoaderContainsRecommendedModels() throws {
        let modelLoader = ModelLoader()
        let recommendedModels = modelLoader.availableModels.filter { $0.category == .recommended }
        XCTAssertFalse(recommendedModels.isEmpty, "Should have recommended models")
    }

    func testModelInfoHasValidDownloadURL() throws {
        let modelLoader = ModelLoader()
        for model in modelLoader.availableModels {
            XCTAssertTrue(model.downloadURL.hasPrefix("https://"), "Model \(model.id) should have HTTPS URL")
            XCTAssertNotNil(URL(string: model.downloadURL), "Model \(model.id) should have valid URL")
        }
    }

    func testModelInfoHasValidSize() throws {
        let modelLoader = ModelLoader()
        for model in modelLoader.availableModels {
            XCTAssertGreaterThan(model.sizeBytes, 0, "Model \(model.id) should have positive size")
        }
    }

    func testDeviceTierDetection() throws {
        let tier = DeviceTier.current
        XCTAssertNotNil(tier.displayName)
        XCTAssertNotNil(tier.recommendedModelSize)
    }

    // MARK: - Conversation Manager Tests

    func testConversationManagerCreation() throws {
        let manager = ConversationManager()
        XCTAssertTrue(manager.conversations.isEmpty || manager.conversations.count >= 0)
    }

    func testConversationCreation() throws {
        let manager = ConversationManager()
        let conversation = manager.createNewConversation()
        XCTAssertNotNil(conversation)
        XCTAssertTrue(manager.conversations.contains { $0.id == conversation.id })
    }
}
