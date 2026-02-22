import Foundation
import SQLite3

/// Full-text search engine for emergency knowledge base using SQLite FTS5
/// Provides fast keyword-based search (<50ms) and RAG formatting for LLM context injection
@MainActor
final class KnowledgeBaseSearchEngine {
    static let shared = KnowledgeBaseSearchEngine()

    private var database: OpaquePointer?
    private let dbPath: URL
    private let fileManager = FileManager.default

    /// Knowledge base directory path
    private var kbDirectory: URL {
        let dir = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("KnowledgeBase", isDirectory: true)

        if !fileManager.fileExists(atPath: dir.path) {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }

        return dir
    }

    init() {
        self.dbPath = kbDirectory.appendingPathComponent("kb_search.db")
        openDatabase()
    }

    deinit {
        closeDatabase()
    }

    // MARK: - Database Management

    private func openDatabase() {
        if sqlite3_open(dbPath.path, &database) != SQLITE_OK {
            print("[KBSearch] Error opening database")
            return
        }

        createFTS5Table()
    }

    nonisolated private func closeDatabase() {
        if database != nil {
            sqlite3_close(database)
            database = nil
        }
    }

    private func createFTS5Table() {
        let createTableQuery = """
        CREATE VIRTUAL TABLE IF NOT EXISTS kb_search USING fts5(
            category,
            title,
            content,
            language,
            tokenize='unicode61 remove_diacritics 2'
        );
        """

        var statement: OpaquePointer?
        if sqlite3_prepare_v2(database, createTableQuery, -1, &statement, nil) == SQLITE_OK {
            if sqlite3_step(statement) == SQLITE_DONE {
                print("[KBSearch] FTS5 table created successfully")
            } else {
                print("[KBSearch] Error creating FTS5 table")
            }
        }
        sqlite3_finalize(statement)
    }

    // MARK: - Indexing

    /// Index knowledge base from JSON data
    /// - Parameters:
    ///   - kbData: Knowledge base JSON dictionary
    ///   - language: Language code (ja, en, etc.)
    func indexKnowledgeBase(_ kbData: [String: Any], language: String) throws {
        guard let locales = kbData["locales"] as? [String: Any],
              let localeData = locales[language] as? [String: Any] else {
            throw KBSearchError.invalidData
        }

        // Clear existing data for this language
        clearLanguage(language)

        var indexedCount = 0

        // Iterate through categories
        for (categoryKey, categoryValue) in localeData {
            guard let category = categoryValue as? [String: Any],
                  let categoryTitle = category["title"] as? String,
                  let items = category["items"] as? [String: Any] else {
                continue
            }

            // Iterate through items in category
            for (_, itemValue) in items {
                guard let item = itemValue as? [String: Any],
                      let title = item["title"] as? String else {
                    continue
                }

                var content = title + "\n"

                // Extract steps
                if let steps = item["steps"] as? [String] {
                    content += steps.joined(separator: "\n") + "\n"
                }

                // Extract entries
                if let entries = item["entries"] as? [[String: String]] {
                    for entry in entries {
                        let number = entry["number"] ?? ""
                        let description = entry["description"] ?? ""
                        content += "\(number): \(description)\n"
                    }
                }

                // Insert into FTS5
                if insertEntry(category: categoryKey, categoryTitle: categoryTitle, title: title, content: content, language: language) {
                    indexedCount += 1
                }
            }
        }

        print("[KBSearch] Indexed \(indexedCount) entries for language: \(language)")
    }

    private func insertEntry(category: String, categoryTitle: String, title: String, content: String, language: String) -> Bool {
        let insertQuery = "INSERT INTO kb_search (category, title, content, language) VALUES (?, ?, ?, ?);"

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, insertQuery, -1, &statement, nil) == SQLITE_OK else {
            print("[KBSearch] Error preparing insert statement")
            return false
        }

        // Use categoryTitle for better search results
        let categoryWithTitle = "\(categoryTitle) > \(category)"

        sqlite3_bind_text(statement, 1, (categoryWithTitle as NSString).utf8String, -1, nil)
        sqlite3_bind_text(statement, 2, (title as NSString).utf8String, -1, nil)
        sqlite3_bind_text(statement, 3, (content as NSString).utf8String, -1, nil)
        sqlite3_bind_text(statement, 4, (language as NSString).utf8String, -1, nil)

        let result = sqlite3_step(statement) == SQLITE_DONE
        sqlite3_finalize(statement)

        return result
    }

    private func clearLanguage(_ language: String) {
        let deleteQuery = "DELETE FROM kb_search WHERE language = ?;"

        var statement: OpaquePointer?
        if sqlite3_prepare_v2(database, deleteQuery, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, (language as NSString).utf8String, -1, nil)
            sqlite3_step(statement)
        }
        sqlite3_finalize(statement)
    }

    // MARK: - Search

    /// Search knowledge base with keyword matching
    /// - Parameters:
    ///   - query: Search query string
    ///   - language: Language code
    ///   - limit: Maximum number of results (default: 5)
    /// - Returns: Array of search results, ordered by relevance
    func search(query: String, language: String, limit: Int = 5) -> [KBSearchResult] {
        let startTime = Date()

        // Prepare FTS5 query
        let searchQuery = """
        SELECT category, title, content, rank
        FROM kb_search
        WHERE kb_search MATCH ? AND language = ?
        ORDER BY rank
        LIMIT ?;
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, searchQuery, -1, &statement, nil) == SQLITE_OK else {
            print("[KBSearch] Error preparing search query")
            return []
        }

        // FTS5 query syntax: simple keyword search
        let ftsQuery = query.lowercased()
        sqlite3_bind_text(statement, 1, (ftsQuery as NSString).utf8String, -1, nil)
        sqlite3_bind_text(statement, 2, (language as NSString).utf8String, -1, nil)
        sqlite3_bind_int(statement, 3, Int32(limit))

        var results: [KBSearchResult] = []

        while sqlite3_step(statement) == SQLITE_ROW {
            let category = String(cString: sqlite3_column_text(statement, 0))
            let title = String(cString: sqlite3_column_text(statement, 1))
            let content = String(cString: sqlite3_column_text(statement, 2))
            let rank = sqlite3_column_double(statement, 3)

            let result = KBSearchResult(
                category: category,
                title: title,
                content: content,
                relevanceScore: abs(rank) // FTS5 rank is negative, lower is better
            )
            results.append(result)
        }

        sqlite3_finalize(statement)

        let elapsed = Date().timeIntervalSince(startTime) * 1000
        print("[KBSearch] Search completed in \(String(format: "%.1f", elapsed))ms, found \(results.count) results")

        return results
    }

    // MARK: - RAG Formatting

    /// Format search results for RAG context injection into LLM
    /// - Parameter results: Array of search results
    /// - Returns: Formatted string for system prompt injection
    func formatForRAG(_ results: [KBSearchResult]) -> String {
        guard !results.isEmpty else {
            return ""
        }

        var formatted = "# 緊急ナレッジベースからの関連情報\n\n"

        for (index, result) in results.enumerated() {
            formatted += "## \(index + 1). \(result.title)\n"
            formatted += "📁 カテゴリ: \(result.category)\n\n"

            // Add content, limiting to first 500 characters if too long
            let contentLimit = 500
            if result.content.count > contentLimit {
                let truncated = String(result.content.prefix(contentLimit))
                formatted += "\(truncated)...\n\n"
            } else {
                formatted += "\(result.content)\n\n"
            }

            formatted += "---\n\n"
        }

        return formatted
    }

    // MARK: - Utility

    /// Check if database is ready
    func isDatabaseReady() -> Bool {
        return database != nil
    }

    /// Get number of indexed entries for a language
    func getIndexedCount(for language: String) -> Int {
        let countQuery = "SELECT COUNT(*) FROM kb_search WHERE language = ?;"

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, countQuery, -1, &statement, nil) == SQLITE_OK else {
            return 0
        }

        sqlite3_bind_text(statement, 1, (language as NSString).utf8String, -1, nil)

        var count = 0
        if sqlite3_step(statement) == SQLITE_ROW {
            count = Int(sqlite3_column_int(statement, 0))
        }

        sqlite3_finalize(statement)
        return count
    }

    /// Rebuild index from scratch
    func rebuildIndex() {
        closeDatabase()

        // Delete old database
        if fileManager.fileExists(atPath: dbPath.path) {
            try? fileManager.removeItem(at: dbPath)
        }

        openDatabase()
    }
}

// MARK: - Search Result Model

struct KBSearchResult: Identifiable {
    let id = UUID()
    let category: String        // e.g., "応急処置 > first_aid"
    let title: String           // e.g., "心肺蘇生法 (CPR)"
    let content: String         // Full text with steps
    let relevanceScore: Double  // FTS5 rank score (lower is better)
}

// MARK: - Errors

enum KBSearchError: Error, LocalizedError {
    case invalidData
    case databaseError
    case indexingFailed

    var errorDescription: String? {
        switch self {
        case .invalidData:
            return "ナレッジベースのデータが無効です"
        case .databaseError:
            return "データベースエラーが発生しました"
        case .indexingFailed:
            return "インデックス作成に失敗しました"
        }
    }
}
