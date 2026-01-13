//
//  SnapshotTests.swift
//  LocalAIAgentUITests
//
//  App Store用スクリーンショット自動生成
//

import XCTest

final class SnapshotTests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = true
        app = XCUIApplication()
        setupSnapshot(app)
        app.launch()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Screenshot Tests

    /// 01. ウェルカム画面 - メイン訴求ポイント
    @MainActor
    func testSnapshot01_WelcomeScreen() throws {
        // Wait for app to fully load
        sleep(3)

        // Take screenshot of welcome/main screen
        snapshot("01_WelcomeScreen", waitForLoadingIndicator: true)
    }

    /// 02. チャット画面 - 会話例
    @MainActor
    func testSnapshot02_ChatConversation() throws {
        sleep(2)

        // Find the text input field and enter a message
        let textField = app.textFields.firstMatch
        if textField.waitForExistence(timeout: 5) {
            textField.tap()
            textField.typeText("今日の予定を教えて")

            // Send the message
            let sendButton = app.buttons["arrow.up.circle.fill"]
            if sendButton.exists {
                sendButton.tap()
            }

            // Wait for AI response
            sleep(5)
        }

        snapshot("02_ChatConversation", waitForLoadingIndicator: true)
    }

    /// 03. カレンダー連携 - 予定確認機能
    @MainActor
    func testSnapshot03_CalendarIntegration() throws {
        sleep(2)

        let textField = app.textFields.firstMatch
        if textField.waitForExistence(timeout: 5) {
            textField.tap()
            textField.typeText("明日の予定は？")

            let sendButton = app.buttons["arrow.up.circle.fill"]
            if sendButton.exists {
                sendButton.tap()
            }

            sleep(5)
        }

        snapshot("03_CalendarIntegration", waitForLoadingIndicator: true)
    }

    /// 04. 設定画面 - カスタマイズ性
    @MainActor
    func testSnapshot04_Settings() throws {
        sleep(2)

        // Navigate to settings
        let settingsButton = app.buttons["gearshape"]
        if settingsButton.waitForExistence(timeout: 5) {
            settingsButton.tap()
            sleep(2)
        }

        snapshot("04_Settings", waitForLoadingIndicator: true)
    }

    /// 05. 会話一覧 - 検索機能
    @MainActor
    func testSnapshot05_ConversationList() throws {
        sleep(2)

        // Try to open conversation list (sidebar on iPad, sheet on iPhone)
        let listButton = app.buttons["list.bullet"]
        if listButton.waitForExistence(timeout: 3) {
            listButton.tap()
            sleep(2)
        }

        snapshot("05_ConversationList", waitForLoadingIndicator: true)
    }

    /// 06. オフライン表示 - プライバシー訴求
    @MainActor
    func testSnapshot06_PrivacyFeature() throws {
        sleep(2)

        // Navigate to settings to show privacy features
        let settingsButton = app.buttons["gearshape"]
        if settingsButton.waitForExistence(timeout: 5) {
            settingsButton.tap()
            sleep(2)

            // Scroll to privacy section if needed
            app.swipeUp()
            sleep(1)
        }

        snapshot("06_PrivacyFeature", waitForLoadingIndicator: true)
    }
}
