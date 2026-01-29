//
//  LLMConversationTests.swift
//  LocalAIAgentUITests
//
//  Simple E2E test: Tutorial -> Model Download -> Chat -> Switch Model -> New Chat
//

import XCTest

@MainActor
final class LLMConversationTests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = true
        app = XCUIApplication()
        app.launch()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Simple E2E Test
    // NOTE: Disabled due to model download timeout on Firebase Test Lab
    // Re-enable when using pre-bundled test model

    func DISABLED_testBasicE2EFlow() throws {
        // 1. Complete tutorial/onboarding
        completeTutorial()
        takeScreenshot("01_AfterTutorial")

        // 2. Wait for model to be ready (download if needed)
        let modelReady = waitForModelReady(timeout: 600)
        XCTAssertTrue(modelReady, "Model should be ready")
        takeScreenshot("02_ModelReady")

        // 3. Have a simple conversation (2-3 turns)
        sendMessage("こんにちは")
        waitForResponse()
        takeScreenshot("03_Chat_Turn1")

        sendMessage("今日の天気を教えて")
        waitForResponse()
        takeScreenshot("04_Chat_Turn2")

        sendMessage("ありがとう")
        waitForResponse()
        takeScreenshot("05_Chat_Turn3")

        // 4. Go to settings and check model info
        openSettings()
        takeScreenshot("06_Settings")
        closeSettings()

        // 5. Start new conversation
        startNewConversation()
        takeScreenshot("07_NewConversation")

        // 6. One more chat
        sendMessage("新しい会話を始めました")
        waitForResponse()
        takeScreenshot("08_NewChat")

        print("E2E Test completed successfully!")
    }

    // MARK: - Helper Methods

    private func completeTutorial() {
        let tutorialButtons = ["スキップ", "Skip", "次へ", "Next", "始める", "Get Started", "OK", "許可", "Allow"]

        for _ in 0..<10 {
            var tapped = false
            for buttonText in tutorialButtons {
                let button = app.buttons[buttonText]
                if button.waitForExistence(timeout: 1) {
                    button.tap()
                    tapped = true
                    sleep(1)
                    break
                }
            }

            // Check springboard for permission dialogs
            let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
            for buttonText in ["許可", "Allow", "OK", "許可しない", "Don't Allow"] {
                let button = springboard.buttons[buttonText]
                if button.waitForExistence(timeout: 0.5) {
                    button.tap()
                    sleep(1)
                }
            }

            // Check if on main chat screen
            if app.textFields.firstMatch.exists && !tapped {
                break
            }
        }

        sleep(2)
    }

    private func waitForModelReady(timeout: TimeInterval) -> Bool {
        let start = Date()

        while Date().timeIntervalSince(start) < timeout {
            let textField = app.textFields.firstMatch
            if textField.waitForExistence(timeout: 5) && textField.isEnabled {
                // Check no loading indicator
                let loading = app.staticTexts.matching(NSPredicate(format: "label CONTAINS '%' OR label CONTAINS 'ロード'")).firstMatch
                if !loading.exists {
                    return true
                }
            }
            sleep(5)
        }
        return false
    }

    private func sendMessage(_ text: String) {
        let textField = app.textFields.firstMatch
        guard textField.waitForExistence(timeout: 10) else { return }

        textField.tap()
        textField.typeText(text)
        sleep(1)

        // Try send button or return key
        let sendButton = app.buttons.matching(NSPredicate(format: "identifier CONTAINS 'send' OR label CONTAINS 'arrow'")).firstMatch
        if sendButton.exists {
            sendButton.tap()
        } else {
            textField.typeText("\n")
        }
    }

    private func waitForResponse() {
        // Wait for typing indicator to appear then disappear
        sleep(2)

        let maxWait: TimeInterval = 120
        let start = Date()

        while Date().timeIntervalSince(start) < maxWait {
            let typing = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Generating' OR label CONTAINS '生成'")).firstMatch
            if !typing.exists {
                sleep(2) // Extra wait for response to render
                return
            }
            sleep(1)
        }
    }

    private func openSettings() {
        let settingsButton = app.buttons["settingsButton"]
        if settingsButton.waitForExistence(timeout: 5) {
            settingsButton.tap()
            sleep(2)
        }
    }

    private func closeSettings() {
        let closeButton = app.buttons["完了"]
        let doneButton = app.buttons["Done"]

        if closeButton.waitForExistence(timeout: 2) {
            closeButton.tap()
        } else if doneButton.waitForExistence(timeout: 2) {
            doneButton.tap()
        } else {
            // Swipe down to dismiss
            app.swipeDown()
        }
        sleep(1)
    }

    private func startNewConversation() {
        let newButton = app.buttons["square.and.pencil"]
        if newButton.waitForExistence(timeout: 5) {
            newButton.tap()
            sleep(2)
        }
    }

    private func takeScreenshot(_ name: String) {
        let screenshot = app.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
