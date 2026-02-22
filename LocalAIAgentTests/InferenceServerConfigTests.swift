import XCTest
@testable import LocalAIAgent

@MainActor
final class InferenceServerConfigTests: XCTestCase {

    // MARK: - Singleton

    func testConfigSingleton() throws {
        let config = InferenceServerConfig.shared
        XCTAssertNotNil(config)
    }

    // MARK: - Valid Values (singleton persists on real devices)

    func testServerModeIsValid() throws {
        let config = InferenceServerConfig.shared
        let validModes: [ServerMode] = [.private, .friendsOnly, .public]
        XCTAssertTrue(validModes.contains(config.serverMode), "Server mode should be a valid value")
    }

    func testPriceIsNonNegative() throws {
        let config = InferenceServerConfig.shared
        XCTAssertGreaterThanOrEqual(config.pricePerRequest, 0)
    }

    // MARK: - Server Mode

    func testServerModeUpdate() throws {
        let config = InferenceServerConfig.shared
        let original = config.serverMode

        config.serverMode = .public
        XCTAssertEqual(config.serverMode, .public)

        config.serverMode = .friendsOnly
        XCTAssertEqual(config.serverMode, .friendsOnly)

        // Restore
        config.serverMode = original
    }
}
