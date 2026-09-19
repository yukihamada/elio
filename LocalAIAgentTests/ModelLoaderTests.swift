import XCTest
import Combine
import CryptoKit
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

    /// Opt-in only: the workflow injects this flag into the simulator xctestrun.
    func testRealModelDownloadLoadAndInference() async throws {
        #if targetEnvironment(simulator)
        guard ProcessInfo.processInfo.environment["ELIO_CI_FULL_MODEL"] == "1" else {
            throw XCTSkip("Real 1.26 GB download is allowed only in the explicit CI job")
        }
        continueAfterFailure = false
        executionTimeAllowance = 1200
        let model = try XCTUnwrap(modelLoader.getModelInfo("eliochat-1.7b-v3"))
        let expectedBytes: Int64 = 1_257_875_104
        let expectedSHA = "82652c12c33044a23e66f55fc8ecdb67bd05bb5a968b7a1f4134ee086ba5638a"
        let evidenceURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("full-model-evidence.json")
        var evidence: [String: Any] = [
            "model": model.id, "url": model.downloadURL,
            "expectedBytes": expectedBytes, "expectedSHA256": expectedSHA,
            "environment": "iOS Simulator; production auto inference mode",
            "physicalMemory": ProcessInfo.processInfo.physicalMemory,
            "os": ProcessInfo.processInfo.operatingSystemVersionString,
            "physicalDeviceVerified": false, "resumeVerified": false,
            "uiVerified": false, "testFlightBinaryVerified": false
        ]
        func checkpoint(_ stage: String) throws {
            evidence["stage"] = stage
            let data = try JSONSerialization.data(withJSONObject: evidence, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: evidenceURL, options: .atomic)
            print("FULL_MODEL_STAGE: \(stage)")
        }
        defer {
            if let data = try? Data(contentsOf: evidenceURL) {
                let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
                attachment.name = "full-model-evidence.json"
                attachment.lifetime = .keepAlways
                add(attachment)
            }
        }
        XCTAssertFalse(modelLoader.isModelDownloaded(model.id), "Requires a fresh simulator, not a cached model")
        try checkpoint("download_started")
        let start = Date()
        var milestones: [[String: Any]] = []
        var lastBucket = -1
        let observation = modelLoader.$downloadProgressInfo.sink { info in
            guard let progress = info[model.id] else { return }
            let bucket = Int(progress.progress * 100)
            if bucket >= 90 && bucket > lastBucket {
                lastBucket = bucket
                milestones.append(["percent": progress.progress * 100,
                                   "bytes": progress.bytesDownloaded,
                                   "total": progress.totalBytes,
                                   "seconds": Date().timeIntervalSince(start)])
                print("FULL_MODEL_PROGRESS: \(bucket)% bytes=\(progress.bytesDownloaded) total=\(progress.totalBytes)")
            }
        }
        defer { observation.cancel() }
        try await modelLoader.downloadModel(model)
        evidence["downloadSeconds"] = Date().timeIntervalSince(start)
        evidence["progressMilestones"] = milestones
        evidence["completionProgress"] = modelLoader.downloadProgress[model.id]
        XCTAssertTrue(modelLoader.isModelDownloaded(model.id))
        XCTAssertFalse(modelLoader.isDownloading)
        let path = try XCTUnwrap(modelLoader.getModelPath(model.id))
        let bytes = try XCTUnwrap(try FileManager.default.attributesOfItem(atPath: path.path)[.size] as? NSNumber).int64Value
        evidence["actualBytes"] = bytes
        try checkpoint("download_completed")
        XCTAssertEqual(bytes, expectedBytes)
        let handle = try FileHandle(forReadingFrom: path)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 4 * 1024 * 1024), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        let sha = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        evidence["actualSHA256"] = sha
        try checkpoint("hash_computed")
        XCTAssertEqual(sha, expectedSHA)
        let loadStart = Date()
        try checkpoint("load_started")
        let inference = try await modelLoader.loadModel(named: model.id)
        defer { inference.unload() }
        evidence["loadSeconds"] = Date().timeIntervalSince(loadStart)
        XCTAssertTrue(inference.isLoaded)
        try checkpoint("load_completed")
        let prompt = "<|im_start|>system\nAnswer briefly. /no_think<|im_end|>\n<|im_start|>user\nWhat is 2 + 2? Reply with the number only.<|im_end|>\n<|im_start|>assistant\n"
        evidence["prompt"] = prompt
        let generationStart = Date()
        var streamed = ""
        var callbacks = 0
        var firstTokenSeconds: Double?
        try checkpoint("inference_started")
        let output = try await inference.generate(prompt: prompt, maxTokens: 64, temperature: 0,
                                                  stopSequences: ["<|im_end|>"]) { token in
            if firstTokenSeconds == nil { firstTokenSeconds = Date().timeIntervalSince(generationStart) }
            streamed += token
            callbacks += 1
            print("FULL_MODEL_TOKEN: callback=\(callbacks) elapsed=\(Date().timeIntervalSince(generationStart)) text=\(token)")
        }
        evidence["inferenceSeconds"] = Date().timeIntervalSince(generationStart)
        evidence["firstTokenSeconds"] = firstTokenSeconds
        evidence["output"] = output
        evidence["streamedOutput"] = streamed
        evidence["streamCallbacks"] = callbacks
        try checkpoint("inference_completed")
        // Async XCTest assertions do not reliably stop control flow even with
        // continueAfterFailure=false. Never persist "passed" after an issue.
        guard !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              callbacks > 0, output.contains("4"), testRun?.failureCount == 0 else {
            try checkpoint("validation_failed")
            throw NSError(domain: "ElioFullModelVerification", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Generated output failed the arithmetic smoke check; inspect evidence"])
        }
        try checkpoint("passed")
        print("FULL_MODEL_RESULT: \(String(data: try Data(contentsOf: evidenceURL), encoding: .utf8)!)")
        #else
        throw XCTSkip("CI iOS Simulator only")
        #endif
    }

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
            if model.isMLX {
                XCTAssertFalse(model.mlxHubId?.isEmpty ?? true, "MLX model \(model.id) needs a Hub ID")
                continue
            }
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
