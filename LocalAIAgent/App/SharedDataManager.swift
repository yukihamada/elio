import Foundation

/// Manages shared data between main app and widget extension via App Groups
final class SharedDataManager {
    static let shared = SharedDataManager()

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

    /// URL for conversations storage
    static var conversationsURL: URL {
        baseURL.appendingPathComponent("conversations.json")
    }

    /// URL for pending quick question from widget
    static var pendingQuestionURL: URL {
        baseURL.appendingPathComponent("pending_question.txt")
    }

    /// URL for app state snapshot (for widget display)
    static var appStateSnapshotURL: URL {
        baseURL.appendingPathComponent("app_state_snapshot.json")
    }

    /// Shared UserDefaults suite for App Group
    static var sharedDefaults: UserDefaults {
        UserDefaults(suiteName: appGroupIdentifier) ?? .standard
    }

    // MARK: - Conversation Management

    /// Save conversations to shared storage (synchronous - use async version when possible)
    static func saveConversations(_ conversations: [Conversation]) {
        do {
            let data = try JSONEncoder().encode(conversations)
            try data.write(to: conversationsURL, options: .atomic)
        } catch {
            print("Failed to save conversations: \(error)")
        }
    }

    /// Save conversations asynchronously (non-blocking)
    static func saveConversationsAsync(_ conversations: [Conversation]) {
        DispatchQueue.global(qos: .utility).async {
            do {
                let data = try JSONEncoder().encode(conversations)
                try data.write(to: conversationsURL, options: .atomic)
            } catch {
                print("Failed to save conversations: \(error)")
            }
        }
    }

    /// Load conversations from shared storage (synchronous)
    static func loadConversations() -> [Conversation] {
        do {
            let data = try Data(contentsOf: conversationsURL)
            return try JSONDecoder().decode([Conversation].self, from: data)
        } catch {
            return []
        }
    }

    /// Load conversations asynchronously
    static func loadConversationsAsync() async -> [Conversation] {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let result = loadConversations()
                continuation.resume(returning: result)
            }
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

    /// Load and clear pending question
    static func loadPendingQuestion() -> String? {
        do {
            let question = try String(contentsOf: pendingQuestionURL, encoding: .utf8)
            clearPendingQuestion()
            return question.isEmpty ? nil : question
        } catch {
            return nil
        }
    }

    /// Clear pending question
    static func clearPendingQuestion() {
        try? FileManager.default.removeItem(at: pendingQuestionURL)
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

    /// Save app state snapshot for widget
    static func saveAppStateSnapshot(
        modelName: String?,
        isModelLoaded: Bool,
        recentConversation: Conversation?
    ) {
        let snapshot = AppStateSnapshot(
            modelName: modelName,
            isModelLoaded: isModelLoaded,
            recentConversationTitle: recentConversation?.title,
            recentConversationId: recentConversation?.id,
            lastUpdated: Date()
        )

        do {
            let data = try JSONEncoder().encode(snapshot)
            try data.write(to: appStateSnapshotURL, options: .atomic)
        } catch {
            print("Failed to save app state snapshot: \(error)")
        }
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

    // MARK: - Migration

    /// Migrate existing conversations from old location to shared container
    static func migrateIfNeeded() {
        let oldURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("conversations.json")

        // Only migrate if App Group is available and old file exists
        guard sharedContainerURL != nil,
              FileManager.default.fileExists(atPath: oldURL.path),
              !FileManager.default.fileExists(atPath: conversationsURL.path) else {
            return
        }

        do {
            try FileManager.default.copyItem(at: oldURL, to: conversationsURL)
            print("Migrated conversations to shared container")
        } catch {
            print("Migration failed: \(error)")
        }
    }
}
