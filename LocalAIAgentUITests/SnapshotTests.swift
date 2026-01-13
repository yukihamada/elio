//
//  SnapshotTests.swift
//  LocalAIAgentUITests
//
//  App Store用スクリーンショット自動生成
//

import XCTest

@MainActor
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

    /// Skip onboarding screens
    private func skipOnboarding() {
        // Try to find and tap "次へ" or "Next" button multiple times to skip through onboarding
        for _ in 1...5 {
            let nextButton = app.buttons["次へ"]
            let skipButton = app.buttons["スキップ"]
            let startButton = app.buttons["始める"]
            let okButton = app.buttons["OK"]

            if skipButton.waitForExistence(timeout: 1) {
                skipButton.tap()
                sleep(1)
                continue
            }

            if nextButton.waitForExistence(timeout: 1) {
                nextButton.tap()
                sleep(1)
                continue
            }

            if startButton.waitForExistence(timeout: 1) {
                startButton.tap()
                sleep(1)
                continue
            }

            if okButton.waitForExistence(timeout: 1) {
                okButton.tap()
                sleep(1)
                continue
            }

            // Check if we're on the main chat screen
            let textField = app.textFields.firstMatch
            if textField.exists {
                break
            }
        }

        // Handle any permission dialogs
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allowButton = springboard.buttons["許可"]
        let allowWhileUsingButton = springboard.buttons["Appの使用中は許可"]
        let dontAllowButton = springboard.buttons["許可しない"]

        if allowButton.waitForExistence(timeout: 2) {
            allowButton.tap()
        }
        if allowWhileUsingButton.waitForExistence(timeout: 1) {
            allowWhileUsingButton.tap()
        }
        if dontAllowButton.waitForExistence(timeout: 1) {
            dontAllowButton.tap()
        }

        sleep(2)
    }

    // MARK: - Screenshot Tests

    /// 01. ウェルカム画面 - メイン訴求ポイント
    func testSnapshot01_WelcomeScreen() throws {
        // Wait for app to fully load
        sleep(3)

        // Take screenshot of welcome/main screen (onboarding)
        snapshot("01_WelcomeScreen", waitForLoadingIndicator: true)
    }

    /// 02. チャット画面 - 会話例
    func testSnapshot02_ChatScreen() throws {
        skipOnboarding()
        sleep(2)

        // Take screenshot of the main chat screen
        snapshot("02_ChatScreen", waitForLoadingIndicator: true)
    }

    /// 03. チャット入力中
    func testSnapshot03_ChatInput() throws {
        skipOnboarding()
        sleep(2)

        // Find the text input field and enter a message
        let textField = app.textFields.firstMatch
        if textField.waitForExistence(timeout: 5) {
            textField.tap()
            textField.typeText("今日の天気は？")
            sleep(1)
        }

        snapshot("03_ChatInput", waitForLoadingIndicator: true)
    }

    /// 04. 設定画面 - カスタマイズ性
    func testSnapshot04_Settings() throws {
        skipOnboarding()
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
    func testSnapshot05_ConversationList() throws {
        skipOnboarding()
        sleep(2)

        // Try to open conversation list (sidebar on iPad, sheet on iPhone)
        let listButton = app.buttons["list.bullet"]
        if listButton.waitForExistence(timeout: 3) {
            listButton.tap()
            sleep(2)
        }

        snapshot("05_ConversationList", waitForLoadingIndicator: true)
    }

    /// 06. モデル設定 - プライバシー訴求
    func testSnapshot06_ModelSettings() throws {
        skipOnboarding()
        sleep(2)

        // Navigate to settings to show model settings
        let settingsButton = app.buttons["gearshape"]
        if settingsButton.waitForExistence(timeout: 5) {
            settingsButton.tap()
            sleep(2)

            // Scroll to find model settings
            app.swipeUp()
            sleep(1)
        }

        snapshot("06_ModelSettings", waitForLoadingIndicator: true)
    }
}
