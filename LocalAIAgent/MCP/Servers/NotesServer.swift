import Foundation

/// A simple note structure for in-app note management
struct AppNote: Codable, Identifiable {
    let id: UUID
    var title: String
    var content: String
    var createdAt: Date
    var updatedAt: Date
    var tags: [String]

    init(id: UUID = UUID(), title: String, content: String, tags: [String] = []) {
        self.id = id
        self.title = title
        self.content = content
        self.createdAt = Date()
        self.updatedAt = Date()
        self.tags = tags
    }
}

/// MCP Server for Notes - In-app note management
final class NotesServer: MCPServer {
    let id = "notes"
    let name = "メモ"
    let serverDescription = "メモの作成・管理を行います"
    let icon = "note.text"

    private let userDefaultsKey = "elio_notes"

    func listTools() -> [MCPTool] {
        [
            MCPTool(
                name: "create_note",
                description: "新しいメモを作成します",
                inputSchema: MCPInputSchema(
                    properties: [
                        "title": MCPPropertySchema(type: "string", description: "メモのタイトル"),
                        "content": MCPPropertySchema(type: "string", description: "メモの内容"),
                        "tags": MCPPropertySchema(type: "array", description: "タグ（カンマ区切り）")
                    ],
                    required: ["title", "content"]
                )
            ),
            MCPTool(
                name: "list_notes",
                description: "保存されているメモの一覧を取得します",
                inputSchema: MCPInputSchema(
                    properties: [
                        "limit": MCPPropertySchema(type: "integer", description: "取得する件数（デフォルト: 10）"),
                        "tag": MCPPropertySchema(type: "string", description: "タグでフィルター")
                    ],
                    required: []
                )
            ),
            MCPTool(
                name: "search_notes",
                description: "メモをキーワードで検索します",
                inputSchema: MCPInputSchema(
                    properties: [
                        "query": MCPPropertySchema(type: "string", description: "検索キーワード")
                    ],
                    required: ["query"]
                )
            ),
            MCPTool(
                name: "get_note",
                description: "指定したIDのメモを取得します",
                inputSchema: MCPInputSchema(
                    properties: [
                        "id": MCPPropertySchema(type: "string", description: "メモのID")
                    ],
                    required: ["id"]
                )
            ),
            MCPTool(
                name: "update_note",
                description: "メモを更新します",
                inputSchema: MCPInputSchema(
                    properties: [
                        "id": MCPPropertySchema(type: "string", description: "メモのID"),
                        "title": MCPPropertySchema(type: "string", description: "新しいタイトル"),
                        "content": MCPPropertySchema(type: "string", description: "新しい内容"),
                        "tags": MCPPropertySchema(type: "array", description: "新しいタグ")
                    ],
                    required: ["id"]
                )
            ),
            MCPTool(
                name: "delete_note",
                description: "メモを削除します",
                inputSchema: MCPInputSchema(
                    properties: [
                        "id": MCPPropertySchema(type: "string", description: "メモのID")
                    ],
                    required: ["id"]
                )
            ),
            MCPTool(
                name: "list_tags",
                description: "使用されているタグの一覧を取得します",
                inputSchema: MCPInputSchema()
            )
        ]
    }

    func listPrompts() -> [MCPPrompt] {
        [
            MCPPrompt(
                name: "quick_note",
                description: "素早くメモを作成します",
                descriptionEn: "Quickly create a note",
                arguments: [
                    MCPPromptArgument(name: "content", description: "メモの内容", descriptionEn: "Note content", required: true)
                ]
            ),
            MCPPrompt(
                name: "daily_summary",
                description: "今日のメモをまとめます",
                descriptionEn: "Summarize today's notes",
                arguments: []
            )
        ]
    }

    func getPrompt(name: String, arguments: [String: String]) -> MCPPromptResult? {
        switch name {
        case "quick_note":
            let content = arguments["content"] ?? ""
            return MCPPromptResult(messages: [
                MCPPromptMessage(role: "user", content: .text("「\(content)」をメモに保存してください。"))
            ])
        case "daily_summary":
            return MCPPromptResult(messages: [
                MCPPromptMessage(role: "user", content: .text("今日作成したメモをまとめてください。"))
            ])
        default:
            return nil
        }
    }

    func callTool(name: String, arguments: [String: JSONValue]) async throws -> MCPResult {
        switch name {
        case "create_note":
            return try createNote(arguments: arguments)
        case "list_notes":
            return listNotes(arguments: arguments)
        case "search_notes":
            return try searchNotes(arguments: arguments)
        case "get_note":
            return try getNote(arguments: arguments)
        case "update_note":
            return try updateNote(arguments: arguments)
        case "delete_note":
            return try deleteNote(arguments: arguments)
        case "list_tags":
            return listTags()
        default:
            throw MCPClientError.toolNotFound(name)
        }
    }

    // MARK: - Storage

    private func loadNotes() -> [AppNote] {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
              let notes = try? JSONDecoder().decode([AppNote].self, from: data) else {
            return []
        }
        return notes
    }

    private func saveNotes(_ notes: [AppNote]) {
        if let data = try? JSONEncoder().encode(notes) {
            UserDefaults.standard.set(data, forKey: userDefaultsKey)
        }
    }

    // MARK: - Tool Implementations

    private func createNote(arguments: [String: JSONValue]) throws -> MCPResult {
        guard let title = arguments["title"]?.stringValue else {
            throw MCPClientError.invalidArguments("タイトルを指定してください")
        }
        guard let content = arguments["content"]?.stringValue else {
            throw MCPClientError.invalidArguments("内容を指定してください")
        }

        var tags: [String] = []
        if let tagsValue = arguments["tags"] {
            switch tagsValue {
            case .string(let s):
                tags = s.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
            case .array(let arr):
                tags = arr.compactMap { $0.stringValue }
            default:
                break
            }
        }

        let note = AppNote(title: title, content: content, tags: tags)

        var notes = loadNotes()
        notes.insert(note, at: 0)
        saveNotes(notes)

        var result = "📝 メモを作成しました\n\n"
        result += "タイトル: \(title)\n"
        result += "内容: \(content.prefix(100))\(content.count > 100 ? "..." : "")\n"
        if !tags.isEmpty {
            result += "タグ: \(tags.joined(separator: ", "))\n"
        }
        result += "\nID: \(note.id.uuidString)"

        return MCPResult(content: [.text(result)])
    }

    private func listNotes(arguments: [String: JSONValue]) -> MCPResult {
        var notes = loadNotes()

        // Filter by tag if specified
        if let tag = arguments["tag"]?.stringValue {
            notes = notes.filter { $0.tags.contains(tag) }
        }

        // Limit results
        var limit = 10
        if case .int(let l) = arguments["limit"] {
            limit = l
        }
        notes = Array(notes.prefix(limit))

        if notes.isEmpty {
            return MCPResult(content: [.text("📝 メモはありません")])
        }

        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "ja_JP")
        dateFormatter.dateFormat = "yyyy/MM/dd HH:mm"

        var result = "📝 メモ一覧（\(notes.count)件）\n\n"

        for (index, note) in notes.enumerated() {
            result += "\(index + 1). **\(note.title)**\n"
            result += "   \(note.content.prefix(50))\(note.content.count > 50 ? "..." : "")\n"
            result += "   作成: \(dateFormatter.string(from: note.createdAt))\n"
            if !note.tags.isEmpty {
                result += "   タグ: \(note.tags.joined(separator: ", "))\n"
            }
            result += "   ID: \(note.id.uuidString.prefix(8))...\n\n"
        }

        return MCPResult(content: [.text(result)])
    }

    private func searchNotes(arguments: [String: JSONValue]) throws -> MCPResult {
        guard let query = arguments["query"]?.stringValue, !query.isEmpty else {
            throw MCPClientError.invalidArguments("検索キーワードを指定してください")
        }

        let notes = loadNotes()
        let lowercasedQuery = query.lowercased()

        let matched = notes.filter { note in
            note.title.lowercased().contains(lowercasedQuery) ||
            note.content.lowercased().contains(lowercasedQuery) ||
            note.tags.contains { $0.lowercased().contains(lowercasedQuery) }
        }

        if matched.isEmpty {
            return MCPResult(content: [.text("🔍 「\(query)」に一致するメモは見つかりませんでした")])
        }

        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "ja_JP")
        dateFormatter.dateFormat = "yyyy/MM/dd HH:mm"

        var result = "🔍 検索結果: 「\(query)」（\(matched.count)件）\n\n"

        for (index, note) in matched.prefix(10).enumerated() {
            result += "\(index + 1). **\(note.title)**\n"
            result += "   \(note.content.prefix(50))\(note.content.count > 50 ? "..." : "")\n"
            result += "   作成: \(dateFormatter.string(from: note.createdAt))\n"
            result += "   ID: \(note.id.uuidString.prefix(8))...\n\n"
        }

        return MCPResult(content: [.text(result)])
    }

    private func getNote(arguments: [String: JSONValue]) throws -> MCPResult {
        guard let idString = arguments["id"]?.stringValue,
              let id = UUID(uuidString: idString) else {
            throw MCPClientError.invalidArguments("有効なIDを指定してください")
        }

        let notes = loadNotes()
        guard let note = notes.first(where: { $0.id == id }) else {
            throw MCPClientError.executionFailed("指定されたIDのメモが見つかりません")
        }

        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "ja_JP")
        dateFormatter.dateFormat = "yyyy/MM/dd HH:mm"

        var result = "📝 メモ詳細\n\n"
        result += "タイトル: \(note.title)\n"
        result += "作成日時: \(dateFormatter.string(from: note.createdAt))\n"
        result += "更新日時: \(dateFormatter.string(from: note.updatedAt))\n"
        if !note.tags.isEmpty {
            result += "タグ: \(note.tags.joined(separator: ", "))\n"
        }
        result += "\n--- 内容 ---\n\(note.content)\n"
        result += "\nID: \(note.id.uuidString)"

        return MCPResult(content: [.text(result)])
    }

    private func updateNote(arguments: [String: JSONValue]) throws -> MCPResult {
        guard let idString = arguments["id"]?.stringValue,
              let id = UUID(uuidString: idString) else {
            throw MCPClientError.invalidArguments("有効なIDを指定してください")
        }

        var notes = loadNotes()
        guard let index = notes.firstIndex(where: { $0.id == id }) else {
            throw MCPClientError.executionFailed("指定されたIDのメモが見つかりません")
        }

        if let title = arguments["title"]?.stringValue {
            notes[index].title = title
        }
        if let content = arguments["content"]?.stringValue {
            notes[index].content = content
        }
        if let tagsValue = arguments["tags"] {
            switch tagsValue {
            case .string(let s):
                notes[index].tags = s.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
            case .array(let arr):
                notes[index].tags = arr.compactMap { $0.stringValue }
            default:
                break
            }
        }
        notes[index].updatedAt = Date()

        saveNotes(notes)

        return MCPResult(content: [.text("✅ メモを更新しました: \(notes[index].title)")])
    }

    private func deleteNote(arguments: [String: JSONValue]) throws -> MCPResult {
        guard let idString = arguments["id"]?.stringValue,
              let id = UUID(uuidString: idString) else {
            throw MCPClientError.invalidArguments("有効なIDを指定してください")
        }

        var notes = loadNotes()
        guard let index = notes.firstIndex(where: { $0.id == id }) else {
            throw MCPClientError.executionFailed("指定されたIDのメモが見つかりません")
        }

        let deletedTitle = notes[index].title
        notes.remove(at: index)
        saveNotes(notes)

        return MCPResult(content: [.text("🗑️ メモを削除しました: \(deletedTitle)")])
    }

    private func listTags() -> MCPResult {
        let notes = loadNotes()
        var tagCounts: [String: Int] = [:]

        for note in notes {
            for tag in note.tags {
                tagCounts[tag, default: 0] += 1
            }
        }

        if tagCounts.isEmpty {
            return MCPResult(content: [.text("🏷️ タグはありません")])
        }

        let sortedTags = tagCounts.sorted { $0.value > $1.value }

        var result = "🏷️ タグ一覧\n\n"
        for (tag, count) in sortedTags {
            result += "• \(tag) (\(count)件)\n"
        }

        return MCPResult(content: [.text(result)])
    }
}
