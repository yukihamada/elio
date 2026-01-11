import Foundation

/// セッション中の全ログを記録するシングルトン
final class SessionLogger {
    static let shared = SessionLogger()

    struct LogEntry: Codable {
        let timestamp: Date
        let level: LogLevel
        let category: String
        let message: String
        let metadata: [String: String]?
    }

    enum LogLevel: String, Codable {
        case debug, info, warning, error
    }

    private var entries: [LogEntry] = []
    private let queue = DispatchQueue(label: "session.logger", qos: .utility)
    private let maxEntries = 10000 // メモリ制限

    private init() {}

    func log(_ level: LogLevel, category: String, _ message: String, metadata: [String: String]? = nil) {
        queue.async { [weak self] in
            guard let self = self else { return }

            let entry = LogEntry(
                timestamp: Date(),
                level: level,
                category: category,
                message: message,
                metadata: metadata
            )
            self.entries.append(entry)

            // メモリ制限を超えたら古いエントリを削除
            if self.entries.count > self.maxEntries {
                self.entries.removeFirst(self.entries.count - self.maxEntries)
            }
        }
    }

    /// JSON形式でエクスポート
    func exportAsJSON() -> Data? {
        queue.sync {
            try? JSONEncoder().encode(entries)
        }
    }

    /// テキスト形式でエクスポート
    func exportAsText() -> String {
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        return queue.sync {
            entries.map { entry in
                let meta = entry.metadata?.map { "\($0.key)=\($0.value)" }.joined(separator: ", ") ?? ""
                let metaStr = meta.isEmpty ? "" : " {\(meta)}"
                return "[\(dateFormatter.string(from: entry.timestamp))] [\(entry.level.rawValue.uppercased())] [\(entry.category)] \(entry.message)\(metaStr)"
            }.joined(separator: "\n")
        }
    }

    /// エントリ数を取得
    var count: Int {
        queue.sync { entries.count }
    }

    /// ログをクリア
    func clear() {
        queue.async { [weak self] in
            self?.entries.removeAll()
        }
    }
}

// MARK: - グローバルヘルパー関数

func logDebug(_ category: String, _ message: String, _ metadata: [String: String]? = nil) {
    SessionLogger.shared.log(.debug, category: category, message, metadata: metadata)
    #if DEBUG
    print("[\(category)] \(message)")
    #endif
}

func logInfo(_ category: String, _ message: String, _ metadata: [String: String]? = nil) {
    SessionLogger.shared.log(.info, category: category, message, metadata: metadata)
    print("[\(category)] \(message)")
}

func logWarning(_ category: String, _ message: String, _ metadata: [String: String]? = nil) {
    SessionLogger.shared.log(.warning, category: category, message, metadata: metadata)
    print("⚠️ [\(category)] \(message)")
}

func logError(_ category: String, _ message: String, _ metadata: [String: String]? = nil) {
    SessionLogger.shared.log(.error, category: category, message, metadata: metadata)
    print("❌ [\(category)] \(message)")
}
