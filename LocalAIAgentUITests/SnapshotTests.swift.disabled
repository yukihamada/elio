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

    /// Language to use for screenshots - change this for different language runs
    /// Set to "ja" for Japanese, "en" for English
    static let screenshotLanguage: String = "en"

    /// Scenario to capture - change this for different content
    /// Options: schedule, code, translation, travel, creative, privacy
    static var currentScenario: String = "schedule"

    override func setUpWithError() throws {
        continueAfterFailure = true
        app = XCUIApplication()

        // Pass screenshot language and scenario to the app
        app.launchArguments += ["-ScreenshotLanguage", Self.screenshotLanguage]
        app.launchArguments += ["-ScreenshotScenario", Self.currentScenario]
        app.launchEnvironment["SCREENSHOT_LANGUAGE"] = Self.screenshotLanguage

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
            let nextButtonEn = app.buttons["Next"]
            let skipButton = app.buttons["スキップ"]
            let skipButtonEn = app.buttons["Skip"]
            let startButton = app.buttons["始める"]
            let startButtonEn = app.buttons["Get Started"]
            let okButton = app.buttons["OK"]

            if skipButton.waitForExistence(timeout: 1) {
                skipButton.tap()
                sleep(1)
                continue
            }

            if skipButtonEn.waitForExistence(timeout: 0.5) {
                skipButtonEn.tap()
                sleep(1)
                continue
            }

            if nextButton.waitForExistence(timeout: 1) {
                nextButton.tap()
                sleep(1)
                continue
            }

            if nextButtonEn.waitForExistence(timeout: 0.5) {
                nextButtonEn.tap()
                sleep(1)
                continue
            }

            if startButton.waitForExistence(timeout: 1) {
                startButton.tap()
                sleep(1)
                continue
            }

            if startButtonEn.waitForExistence(timeout: 0.5) {
                startButtonEn.tap()
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
        let allowButtonEn = springboard.buttons["Allow"]
        let allowWhileUsingButton = springboard.buttons["Appの使用中は許可"]
        let allowWhileUsingButtonEn = springboard.buttons["Allow While Using App"]
        let dontAllowButton = springboard.buttons["許可しない"]
        let dontAllowButtonEn = springboard.buttons["Don't Allow"]

        if allowButton.waitForExistence(timeout: 2) {
            allowButton.tap()
        }
        if allowButtonEn.waitForExistence(timeout: 1) {
            allowButtonEn.tap()
        }
        if allowWhileUsingButton.waitForExistence(timeout: 1) {
            allowWhileUsingButton.tap()
        }
        if allowWhileUsingButtonEn.waitForExistence(timeout: 1) {
            allowWhileUsingButtonEn.tap()
        }
        if dontAllowButton.waitForExistence(timeout: 1) {
            dontAllowButton.tap()
        }
        if dontAllowButtonEn.waitForExistence(timeout: 1) {
            dontAllowButtonEn.tap()
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

    /// 02. チャット画面 - スケジュール会話
    func testSnapshot02_ChatSchedule() throws {
        Self.currentScenario = "schedule"
        skipOnboarding()
        sleep(2)
        snapshot("02_ChatSchedule", waitForLoadingIndicator: true)
    }

    /// 03. チャット画面 - コーディング支援
    func testSnapshot03_ChatCode() throws {
        Self.currentScenario = "code"
        // Relaunch with new scenario
        app.terminate()
        app = XCUIApplication()
        app.launchArguments += ["-ScreenshotLanguage", Self.screenshotLanguage]
        app.launchArguments += ["-ScreenshotScenario", "code"]
        setupSnapshot(app)
        app.launch()

        skipOnboarding()
        sleep(2)
        snapshot("03_ChatCode", waitForLoadingIndicator: true)
    }

    /// 04. チャット画面 - 旅行プランニング
    func testSnapshot04_ChatTravel() throws {
        app.terminate()
        app = XCUIApplication()
        app.launchArguments += ["-ScreenshotLanguage", Self.screenshotLanguage]
        app.launchArguments += ["-ScreenshotScenario", "travel"]
        setupSnapshot(app)
        app.launch()

        skipOnboarding()
        sleep(2)
        snapshot("04_ChatTravel", waitForLoadingIndicator: true)
    }

    /// 05. チャット画面 - プライバシー（アプリの特徴）
    func testSnapshot05_ChatPrivacy() throws {
        app.terminate()
        app = XCUIApplication()
        app.launchArguments += ["-ScreenshotLanguage", Self.screenshotLanguage]
        app.launchArguments += ["-ScreenshotScenario", "privacy"]
        setupSnapshot(app)
        app.launch()

        skipOnboarding()
        sleep(2)
        snapshot("05_ChatPrivacy", waitForLoadingIndicator: true)
    }

    /// 06. チャット画面 - メール作成
    func testSnapshot06_ChatCreative() throws {
        app.terminate()
        app = XCUIApplication()
        app.launchArguments += ["-ScreenshotLanguage", Self.screenshotLanguage]
        app.launchArguments += ["-ScreenshotScenario", "creative"]
        setupSnapshot(app)
        app.launch()

        skipOnboarding()
        sleep(2)
        snapshot("06_ChatCreative", waitForLoadingIndicator: true)
    }

    /// 07. 設定画面 - カスタマイズ性
    func testSnapshot07_Settings() throws {
        // Relaunch app fresh
        app.terminate()
        app = XCUIApplication()
        app.launchArguments += ["-ScreenshotLanguage", Self.screenshotLanguage]
        app.launchArguments += ["-ScreenshotScenario", "schedule"]
        setupSnapshot(app)
        app.launch()

        skipOnboarding()
        sleep(2)

        // Navigate to settings using accessibility identifier
        let settingsButton = app.buttons["settingsButton"]
        if settingsButton.waitForExistence(timeout: 5) {
            settingsButton.tap()
            sleep(3)
        }

        snapshot("07_Settings", waitForLoadingIndicator: true)
    }

    /// 08. 会話一覧 - 検索機能
    func testSnapshot08_ConversationList() throws {
        // Relaunch app fresh
        app.terminate()
        app = XCUIApplication()
        app.launchArguments += ["-ScreenshotLanguage", Self.screenshotLanguage]
        app.launchArguments += ["-ScreenshotScenario", "schedule"]
        setupSnapshot(app)
        app.launch()

        skipOnboarding()
        // Wait longer to ensure mock data is loaded into appState.conversations
        sleep(5)

        // Open conversation list using accessibility identifier
        let menuButton = app.buttons["menuButton"]
        if menuButton.waitForExistence(timeout: 5) {
            menuButton.tap()
            sleep(3)
        }

        snapshot("08_ConversationList", waitForLoadingIndicator: true)
    }
}
