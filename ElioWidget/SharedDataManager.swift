import Foundation

/// Manages shared data between main app and widget extension via App Groups
/// Widget-specific version with only the read methods needed
final class SharedDataManager {
    /// App Group identifier for sharing data between app and widget
    static let appGroupIdentifier = "group.love.elio.app"

    /// Shared container URL for App Group
    static var sharedContainerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)
    }

    /// Fallback to Documents directory if App Group not available
    private static var fallbackURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    /// Base URL for shared storage (prefers App Group, falls back to Documents)
    static var baseURL: URL {
        sharedContainerURL ?? fallbackURL
    }

    /// URL for app state snapshot (for widget display)
    static var appStateSnapshotURL: URL {
        baseURL.appendingPathComponent("app_state_snapshot.json")
    }

    /// URL for pending quick question from widget
    static var pendingQuestionURL: URL {
        baseURL.appendingPathComponent("pending_question.txt")
    }

    // MARK: - App State Snapshot (App -> Widget)

    /// Snapshot of app state for widget display
    struct AppStateSnapshot: Codable {
        let modelName: String?
        let isModelLoaded: Bool
        let recentConversationTitle: String?
        let recentConversationId: UUID?
        let lastUpdated: Date
    }

    /// Load app state snapshot for widget
    static func loadAppStateSnapshot() -> AppStateSnapshot? {
        do {
            let data = try Data(contentsOf: appStateSnapshotURL)
            return try JSONDecoder().decode(AppStateSnapshot.self, from: data)
        } catch {
            return nil
        }
    }

    // MARK: - Quick Question (Widget -> App)

    /// Save a pending question from widget
    static func savePendingQuestion(_ question: String) {
        do {
            try question.write(to: pendingQuestionURL, atomically: true, encoding: .utf8)
        } catch {
            print("Failed to save pending question: \(error)")
        }
    }
}
