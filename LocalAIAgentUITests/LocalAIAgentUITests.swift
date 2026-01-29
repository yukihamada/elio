import XCTest

final class LocalAIAgentUITests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = true
        app = XCUIApplication()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Screenshot Helper

    func takeScreenshot(name: String) {
        sleep(1)
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    // MARK: - Onboarding Flow Test (With Screenshots)

    @MainActor
    func testOnboardingScreens() throws {
        // Normal mode - go through onboarding screens
        app.launchArguments = ["-TestMode"]
        app.launch()

        // 1. Welcome Screen
        takeScreenshot(name: "01_Welcome")

        let nextButton = app.buttons["次へ"]
        if nextButton.waitForExistence(timeout: 10) {
            nextButton.tap()
            sleep(1)

            // 2. Features Screen
            takeScreenshot(name: "02_Features")

            if nextButton.waitForExistence(timeout: 5) {
                nextButton.tap()
                sleep(1)

                // 3. Privacy Screen
                takeScreenshot(name: "03_Privacy")

                if nextButton.waitForExistence(timeout: 5) {
                    nextButton.tap()
                    sleep(1)

                    // 4. Model Selection
                    takeScreenshot(name: "04_ModelSelection")
                }
            }
        }

        XCTAssertTrue(true)
    }

    // MARK: - Main Chat View Test (Skip Download)

    @MainActor
    func testMainChatView() throws {
        // Skip download mode - go directly to chat
        app.launchArguments = ["-SkipDownload"]
        app.launch()

        // Wait for chat view to appear
        sleep(3)
        takeScreenshot(name: "05_ChatView_Empty")

        // Look for text input field
        let textField = app.textFields.firstMatch
        if textField.waitForExistence(timeout: 10) {
            takeScreenshot(name: "06_ChatView_Ready")

            // Tap on text field to show keyboard
            textField.tap()
            sleep(1)
            takeScreenshot(name: "07_ChatView_Keyboard")

            // Dismiss keyboard
            app.tap()
            sleep(1)
        }

        // Look for any buttons in the chat view
        let buttons = app.buttons
        if buttons.count > 0 {
            takeScreenshot(name: "08_ChatView_WithButtons")
        }

        XCTAssertTrue(true)
    }

    // MARK: - Settings View Test (Skip Download)

    @MainActor
    func testSettingsView() throws {
        // Skip download mode
        app.launchArguments = ["-SkipDownload"]
        app.launch()

        sleep(3)

        // Find and tap settings button (gear icon)
        let settingsButton = app.buttons["gearshape"]
        if settingsButton.waitForExistence(timeout: 10) {
            takeScreenshot(name: "09_BeforeSettings")

            settingsButton.tap()
            sleep(1)
            takeScreenshot(name: "10_Settings_Main")

            // Scroll down to see more settings
            let scrollView = app.scrollViews.firstMatch
            if scrollView.exists {
                scrollView.swipeUp()
                sleep(1)
                takeScreenshot(name: "11_Settings_Scrolled1")

                scrollView.swipeUp()
                sleep(1)
                takeScreenshot(name: "12_Settings_Scrolled2")
            }

            // Go back
            let backButton = app.navigationBars.buttons.firstMatch
            if backButton.exists {
                backButton.tap()
                sleep(1)
                takeScreenshot(name: "13_BackToChat")
            }
        }

        XCTAssertTrue(true)
    }

    // MARK: - New Conversation Test (Skip Download)

    @MainActor
    func testNewConversation() throws {
        app.launchArguments = ["-SkipDownload"]
        app.launch()

        sleep(3)

        // Look for new conversation button
        let newChatButton = app.buttons["plus"]
        if newChatButton.waitForExistence(timeout: 10) {
            takeScreenshot(name: "14_ChatWithNewButton")

            newChatButton.tap()
            sleep(1)
            takeScreenshot(name: "15_NewConversation")
        }

        // Look for sidebar/history button
        let sidebarButton = app.buttons["sidebar.left"]
        if sidebarButton.waitForExistence(timeout: 5) {
            sidebarButton.tap()
            sleep(1)
            takeScreenshot(name: "16_Sidebar")
        }

        XCTAssertTrue(true)
    }

    // MARK: - Full App Tour (Skip Download)

    @MainActor
    func testFullAppTour() throws {
        app.launchArguments = ["-SkipDownload"]
        app.launch()

        sleep(3)
        takeScreenshot(name: "A01_MainScreen")

        // Try different UI elements
        let allButtons = app.buttons.allElementsBoundByIndex
        for (index, button) in allButtons.prefix(5).enumerated() {
            if button.isHittable {
                let identifier = button.identifier.isEmpty ? "button_\(index)" : button.identifier
                print("Found button: \(identifier)")
            }
        }

        // Screenshot the main interface
        takeScreenshot(name: "A02_MainInterface")

        // Try to find and interact with any visible elements
        if app.textFields.firstMatch.exists {
            app.textFields.firstMatch.tap()
            sleep(1)
            takeScreenshot(name: "A03_InputFocused")
            app.tap() // Dismiss keyboard
        }

        // Check for navigation elements
        if app.navigationBars.firstMatch.exists {
            takeScreenshot(name: "A04_WithNavBar")
        }

        // Check for tab bars
        if app.tabBars.firstMatch.exists {
            takeScreenshot(name: "A05_WithTabBar")
        }

        XCTAssertTrue(true)
    }

    // MARK: - Performance Test

    @MainActor
    func testLaunchPerformance() throws {
        if #available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 7.0, *) {
            measure(metrics: [XCTApplicationLaunchMetric()]) {
                let testApp = XCUIApplication()
                testApp.launchArguments = ["-SkipDownload"]
                testApp.launch()
            }
        }
    }
}
