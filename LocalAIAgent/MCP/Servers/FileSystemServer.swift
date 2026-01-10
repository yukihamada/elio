import Foundation

final class FileSystemServer: MCPServer {
    let id = "filesystem"
    let name = "ファイルシステム"
    let serverDescription = "アプリ内のファイル操作を行います"
    let icon = "folder"

    private let fileManager = FileManager.default

    private var documentsDirectory: URL {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    func listTools() -> [MCPTool] {
        [
            MCPTool(
                name: "read_file",
                description: "ファイルの内容を読み取ります",
                inputSchema: MCPInputSchema(
                    properties: [
                        "path": MCPPropertySchema(type: "string", description: "読み取るファイルのパス")
                    ],
                    required: ["path"]
                )
            ),
            MCPTool(
                name: "write_file",
                description: "ファイルに内容を書き込みます",
                inputSchema: MCPInputSchema(
                    properties: [
                        "path": MCPPropertySchema(type: "string", description: "書き込むファイルのパス"),
                        "content": MCPPropertySchema(type: "string", description: "書き込む内容")
                    ],
                    required: ["path", "content"]
                )
            ),
            MCPTool(
                name: "list_directory",
                description: "ディレクトリ内のファイル一覧を取得します",
                inputSchema: MCPInputSchema(
                    properties: [
                        "path": MCPPropertySchema(type: "string", description: "ディレクトリのパス（省略時はルート）")
                    ]
                )
            ),
            MCPTool(
                name: "create_directory",
                description: "新しいディレクトリを作成します",
                inputSchema: MCPInputSchema(
                    properties: [
                        "path": MCPPropertySchema(type: "string", description: "作成するディレクトリのパス")
                    ],
                    required: ["path"]
                )
            ),
            MCPTool(
                name: "delete_file",
                description: "ファイルまたはディレクトリを削除します",
                inputSchema: MCPInputSchema(
                    properties: [
                        "path": MCPPropertySchema(type: "string", description: "削除するパス")
                    ],
                    required: ["path"]
                )
            ),
            MCPTool(
                name: "file_info",
                description: "ファイルの情報（サイズ、作成日時など）を取得します",
                inputSchema: MCPInputSchema(
                    properties: [
                        "path": MCPPropertySchema(type: "string", description: "ファイルのパス")
                    ],
                    required: ["path"]
                )
            )
        ]
    }

    func callTool(name: String, arguments: [String: JSONValue]) async throws -> MCPResult {
        switch name {
        case "read_file":
            return try await readFile(arguments: arguments)
        case "write_file":
            return try await writeFile(arguments: arguments)
        case "list_directory":
            return try await listDirectory(arguments: arguments)
        case "create_directory":
            return try await createDirectory(arguments: arguments)
        case "delete_file":
            return try await deleteFile(arguments: arguments)
        case "file_info":
            return try await fileInfo(arguments: arguments)
        default:
            throw MCPClientError.toolNotFound(name)
        }
    }

    private func resolveSecurePath(_ path: String) -> URL {
        if path.isEmpty || path == "/" {
            return documentsDirectory
        }

        let cleanPath = path
            .replacingOccurrences(of: "..", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        return documentsDirectory.appendingPathComponent(cleanPath)
    }

    private func readFile(arguments: [String: JSONValue]) async throws -> MCPResult {
        guard let pathValue = arguments["path"], let path = pathValue.stringValue else {
            throw MCPClientError.invalidArguments("path is required")
        }

        let fileURL = resolveSecurePath(path)

        guard fileManager.fileExists(atPath: fileURL.path) else {
            throw MCPClientError.executionFailed("ファイルが見つかりません: \(path)")
        }

        let content = try String(contentsOf: fileURL, encoding: .utf8)
        return MCPResult(content: [.text(content)])
    }

    private func writeFile(arguments: [String: JSONValue]) async throws -> MCPResult {
        guard let pathValue = arguments["path"], let path = pathValue.stringValue,
              let contentValue = arguments["content"], let content = contentValue.stringValue else {
            throw MCPClientError.invalidArguments("path and content are required")
        }

        let fileURL = resolveSecurePath(path)
        let parentDir = fileURL.deletingLastPathComponent()

        if !fileManager.fileExists(atPath: parentDir.path) {
            try fileManager.createDirectory(at: parentDir, withIntermediateDirectories: true)
        }

        try content.write(to: fileURL, atomically: true, encoding: .utf8)
        return MCPResult(content: [.text("ファイルを書き込みました: \(path)")])
    }

    private func listDirectory(arguments: [String: JSONValue]) async throws -> MCPResult {
        let path = arguments["path"]?.stringValue ?? ""
        let dirURL = resolveSecurePath(path)

        let contents = try fileManager.contentsOfDirectory(
            at: dirURL,
            includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey],
            options: .skipsHiddenFiles
        )

        var result = "📁 \(path.isEmpty ? "Documents" : path)\n\n"

        for item in contents.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let isDir = (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            let icon = isDir ? "📁" : "📄"
            let size = (try? item.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            let sizeStr = isDir ? "" : " (\(formatFileSize(size)))"
            result += "\(icon) \(item.lastPathComponent)\(sizeStr)\n"
        }

        if contents.isEmpty {
            result += "(空のディレクトリ)"
        }

        return MCPResult(content: [.text(result)])
    }

    private func createDirectory(arguments: [String: JSONValue]) async throws -> MCPResult {
        guard let pathValue = arguments["path"], let path = pathValue.stringValue else {
            throw MCPClientError.invalidArguments("path is required")
        }

        let dirURL = resolveSecurePath(path)
        try fileManager.createDirectory(at: dirURL, withIntermediateDirectories: true)

        return MCPResult(content: [.text("ディレクトリを作成しました: \(path)")])
    }

    private func deleteFile(arguments: [String: JSONValue]) async throws -> MCPResult {
        guard let pathValue = arguments["path"], let path = pathValue.stringValue else {
            throw MCPClientError.invalidArguments("path is required")
        }

        let fileURL = resolveSecurePath(path)
        try fileManager.removeItem(at: fileURL)

        return MCPResult(content: [.text("削除しました: \(path)")])
    }

    private func fileInfo(arguments: [String: JSONValue]) async throws -> MCPResult {
        guard let pathValue = arguments["path"], let path = pathValue.stringValue else {
            throw MCPClientError.invalidArguments("path is required")
        }

        let fileURL = resolveSecurePath(path)
        let attrs = try fileManager.attributesOfItem(atPath: fileURL.path)

        var info = "📄 ファイル情報: \(path)\n\n"
        info += "サイズ: \(formatFileSize((attrs[.size] as? Int) ?? 0))\n"
        info += "作成日: \(formatDate(attrs[.creationDate] as? Date))\n"
        info += "更新日: \(formatDate(attrs[.modificationDate] as? Date))\n"
        info += "種類: \(attrs[.type] as? String ?? "不明")\n"

        return MCPResult(content: [.text(info)])
    }

    private func formatFileSize(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }

    private func formatDate(_ date: Date?) -> String {
        guard let date = date else { return "不明" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.locale = Locale(identifier: "ja_JP")
        return formatter.string(from: date)
    }
}
