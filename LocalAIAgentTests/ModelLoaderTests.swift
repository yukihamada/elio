import XCTest
@testable import LocalAIAgent

@MainActor
final class ModelLoaderTests: XCTestCase {

    var modelLoader: ModelLoader!

    override func setUp() {
        super.setUp()
        modelLoader = ModelLoader()
    }

    override func tearDown() {
        modelLoader = nil
        super.tearDown()
    }

    // MARK: - Available Models Tests

    func testAvailableModelsNotEmpty() throws {
        XCTAssertFalse(modelLoader.availableModels.isEmpty, "Should have available models")
    }

    func testAllModelsHaveUniqueIds() throws {
        let ids = modelLoader.availableModels.map { $0.id }
        let uniqueIds = Set(ids)
        XCTAssertEqual(ids.count, uniqueIds.count, "All model IDs should be unique")
    }

    func testAllModelsHaveValidDownloadURL() throws {
        for model in modelLoader.availableModels {
            XCTAssertTrue(
                model.downloadURL.hasPrefix("https://"),
                "Model \(model.id) should have HTTPS URL"
            )
            XCTAssertNotNil(
                URL(string: model.downloadURL),
                "Model \(model.id) should have valid URL"
            )
        }
    }

    func testAllModelsHavePositiveSize() throws {
        for model in modelLoader.availableModels {
            XCTAssertGreaterThan(
                model.sizeBytes,
                0,
                "Model \(model.id) should have positive size"
            )
        }
    }

    func testAllModelsHaveNonEmptyName() throws {
        for model in modelLoader.availableModels {
            XCTAssertFalse(model.name.isEmpty, "Model \(model.id) should have a name")
        }
    }

    func testAllModelsHaveDescription() throws {
        for model in modelLoader.availableModels {
            XCTAssertFalse(
                model.description.isEmpty,
                "Model \(model.id) should have a description"
            )
        }
    }

    // MARK: - Category Tests

    func testHasRecommendedModels() throws {
        let recommendedModels = modelLoader.availableModels.filter { $0.category == .recommended }
        XCTAssertFalse(recommendedModels.isEmpty, "Should have recommended models")
    }

    func testCategoriesAreValid() throws {
        for model in modelLoader.availableModels {
            XCTAssertNotNil(model.category, "Model \(model.id) should have a category")
        }
    }

    // MARK: - Device Tier Tests

    func testDeviceTierHasDisplayName() throws {
        let tier = DeviceTier.current
        XCTAssertFalse(tier.displayName.isEmpty, "Device tier should have display name")
    }

    func testDeviceTierHasRecommendedModelSize() throws {
        let tier = DeviceTier.current
        XCTAssertFalse(
            tier.recommendedModelSize.isEmpty,
            "Device tier should have recommended model size"
        )
    }

    func testAllDeviceTiersHaveDisplayNames() throws {
        let tiers: [DeviceTier] = [.low, .medium, .high, .ultra]
        for tier in tiers {
            XCTAssertFalse(tier.displayName.isEmpty, "Tier \(tier) should have display name")
        }
    }

    // MARK: - Vision Model Tests

    func testVisionModelsExist() throws {
        let visionModels = modelLoader.availableModels.filter { $0.supportsVision }
        XCTAssertFalse(visionModels.isEmpty, "Should have vision-capable models")
    }

    func testVisionModelRecommendation() throws {
        let tier = DeviceTier.current
        let recommended = modelLoader.getRecommendedVisionModel(for: tier)
        if let model = recommended {
            XCTAssertTrue(model.supportsVision, "Recommended vision model should support vision")
        }
    }

    // MARK: - Model Too Heavy Tests

    func testModelTooHeavyForLowTier() throws {
        for model in modelLoader.availableModels {
            let isTooHeavy = model.isTooHeavy(for: .low)
            if model.sizeBytes > 3_000_000_000 {
                XCTAssertTrue(isTooHeavy, "Large model \(model.id) should be too heavy for low tier")
            }
        }
    }

    func testNoModelTooHeavyForUltraTier() throws {
        for model in modelLoader.availableModels {
            let isTooHeavy = model.isTooHeavy(for: .ultra)
            XCTAssertFalse(isTooHeavy, "No model should be too heavy for ultra tier")
        }
    }

    // MARK: - Model Config Tests

    func testModelConfigHasValidContextLength() throws {
        for model in modelLoader.availableModels {
            XCTAssertGreaterThan(
                model.config.maxContextLength,
                0,
                "Model \(model.id) should have positive context length"
            )
        }
    }

    // MARK: - Size Formatting Tests

    func testModelSizeFormatting() throws {
        for model in modelLoader.availableModels {
            let size = model.size
            XCTAssertFalse(size.isEmpty, "Model \(model.id) should have formatted size")
            XCTAssertTrue(
                size.contains("GB") || size.contains("MB"),
                "Size should be in GB or MB format"
            )
        }
    }

    // MARK: - Download State Tests

    func testInitialDownloadState() throws {
        for model in modelLoader.availableModels {
            let progress = modelLoader.downloadProgress[model.id]
            XCTAssertNil(progress, "Initial download progress should be nil")
        }
    }
}
