//
//  SnapshotHelper.swift
//  Fastlane snapshot helper
//
//  Created for Elio App Store screenshots
//

import Foundation
import XCTest

var deviceLanguage = ""
var locale = ""

func setupSnapshot(_ app: XCUIApplication, waitForAnimations: Bool = true) {
    Snapshot.setupSnapshot(app, waitForAnimations: waitForAnimations)
}

func snapshot(_ name: String, waitForLoadingIndicator: Bool) {
    if waitForLoadingIndicator {
        Snapshot.snapshot(name, timeWaitingForIdle: 20)
    } else {
        Snapshot.snapshot(name)
    }
}

enum Snapshot {
    static var app: XCUIApplication?
    static var cacheDirectory: URL?
    static var screenshotsDirectory: URL? {
        return cacheDirectory?.appendingPathComponent("screenshots", isDirectory: true)
    }

    static func setupSnapshot(_ app: XCUIApplication, waitForAnimations: Bool = true) {
        Snapshot.app = app

        do {
            let cacheDir = try FileManager.default.url(
                for: .cachesDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            Snapshot.cacheDirectory = cacheDir
        } catch {
            NSLog("Snapshot: Error getting cache directory: \(error)")
        }

        // Set launch argument to indicate we're running in snapshot mode
        app.launchArguments += ["-FASTLANE_SNAPSHOT", "YES"]
        app.launchArguments += ["-UITest_Screenshots", "YES"]

        // Get device language from simulator
        if let langID = ProcessInfo.processInfo.environment["SIMULATOR_LANGUAGE"] {
            deviceLanguage = langID
            app.launchArguments += ["-AppleLanguages", "(\(langID))"]
            app.launchArguments += ["-AppleLocale", langID]
        }
    }

    static func snapshot(_ name: String, timeWaitingForIdle timeout: TimeInterval = 20) {
        guard let app = Snapshot.app else {
            NSLog("Snapshot: App not set up. Call setupSnapshot() first.")
            return
        }

        // Wait for app to become idle
        sleep(2)

        // Take screenshot using XCTest
        let screenshot = app.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways

        // Add to test
        XCTContext.runActivity(named: "Snapshot: \(name)") { activity in
            activity.add(attachment)
        }

        // Also save to disk for Fastlane
        if let screenshotDir = Snapshot.screenshotsDirectory {
            do {
                try FileManager.default.createDirectory(at: screenshotDir, withIntermediateDirectories: true)
                let imagePath = screenshotDir.appendingPathComponent("\(name).png")
                try screenshot.pngRepresentation.write(to: imagePath)
                NSLog("Snapshot: Saved \(name) to \(imagePath.path)")
            } catch {
                NSLog("Snapshot: Error saving \(name): \(error)")
            }
        }
    }
}
