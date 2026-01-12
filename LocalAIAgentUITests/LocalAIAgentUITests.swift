import XCTest

final class LocalAIAgentUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
        // Put teardown code here.
    }

    // MARK: - App Launch Tests

    @MainActor
    func testAppLaunch() throws {
        let app = XCUIApplication()
        app.launch()

        // Wait for app to load
        let timeout: TimeInterval = 10

        // Check that the app launched successfully
        // The app should show either onboarding or main chat view
        let chatExists = app.textFields.firstMatch.waitForExistence(timeout: timeout)
        let onboardingExists = app.buttons["スキップ"].waitForExistence(timeout: timeout)

        XCTAssertTrue(chatExists || onboardingExists, "App should show chat or onboarding")
    }

    // MARK: - Settings Navigation Tests

    @MainActor
    func testSettingsNavigation() throws {
        let app = XCUIApplication()
        app.launch()

        // Wait for app to load
        sleep(3)

        // Try to find and tap settings button
        let settingsButton = app.buttons["gearshape"]
        if settingsButton.exists {
            settingsButton.tap()

            // Check settings view appeared
            let settingsTitle = app.navigationBars.staticTexts["設定"]
            XCTAssertTrue(settingsTitle.waitForExistence(timeout: 5), "Settings view should appear")
        }
    }

    // MARK: - Performance Tests

    @MainActor
    func testLaunchPerformance() throws {
        if #available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 7.0, *) {
            measure(metrics: [XCTApplicationLaunchMetric()]) {
                XCUIApplication().launch()
            }
        }
    }
}
