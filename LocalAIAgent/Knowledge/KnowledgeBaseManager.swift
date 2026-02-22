import Foundation
import Compression

/// Manages emergency knowledge base downloads, storage, and indexing
/// Pattern: Similar to ModelLoader for consistency
@MainActor
final class KnowledgeBaseManager: ObservableObject {
    static let shared = KnowledgeBaseManager()

    @Published var downloadProgress: [String: Double] = [:]
    @Published var isDownloading = false
    @Published var availableLanguages: [KBLanguage] = []

    private let fileManager = FileManager.default
    private let searchEngine = KnowledgeBaseSearchEngine.shared

    /// Knowledge base directory (Documents/KnowledgeBase/)
    private var kbDirectory: URL {
        let dir = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("KnowledgeBase", isDirectory: true)

        if !fileManager.fileExists(atPath: dir.path) {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }

        return dir
    }

    /// GitHub release base URL
    private let githubReleaseBase = "https://github.com/yukihamada/elio/releases/download"
    private let currentVersion = "v1.0.0"  // Update this when KB content is updated

    init() {
        loadAvailableLanguages()
    }

    // MARK: - Available Languages

    private func loadAvailableLanguages() {
        availableLanguages = [
            KBLanguage(code: "ja", displayName: "日本語", displayNameEn: "Japanese", sizeBytes: 200_000),
            KBLanguage(code: "en", displayName: "English", displayNameEn: "English", sizeBytes: 200_000),
            KBLanguage(code: "es", displayName: "Español", displayNameEn: "Spanish", sizeBytes: 180_000),
            KBLanguage(code: "pt", displayName: "Português", displayNameEn: "Portuguese", sizeBytes: 180_000),
            KBLanguage(code: "de", displayName: "Deutsch", displayNameEn: "German", sizeBytes: 180_000),
            KBLanguage(code: "fr", displayName: "Français", displayNameEn: "French", sizeBytes: 180_000),
            KBLanguage(code: "zh_hans", displayName: "简体中文", displayNameEn: "Simplified Chinese", sizeBytes: 220_000),
            KBLanguage(code: "zh_hant", displayName: "繁體中文", displayNameEn: "Traditional Chinese", sizeBytes: 220_000),
            KBLanguage(code: "ar", displayName: "العربية", displayNameEn: "Arabic", sizeBytes: 180_000),
            KBLanguage(code: "ko", displayName: "한국어", displayNameEn: "Korean", sizeBytes: 200_000),
            KBLanguage(code: "hi", displayName: "हिन्दी", displayNameEn: "Hindi", sizeBytes: 180_000),
            KBLanguage(code: "it", displayName: "Italiano", displayNameEn: "Italian", sizeBytes: 180_000)
        ]
    }

    // MARK: - Language Selection

    /// Determine which languages to download during onboarding
    /// Always: ja + en
    /// Conditional: system language if different
    func determineLanguagesToDownload() -> [String] {
        var languages: [String] = ["ja", "en"]

        // Add system language if not already included
        let systemLang = Locale.current.language.languageCode?.identifier ?? "en"
        let normalizedLang = normalizeLanguageCode(systemLang)

        if !languages.contains(normalizedLang) {
            languages.append(normalizedLang)
        }

        return languages
    }

    /// Normalize language code (handle variants like zh-Hans → zh_hans)
    private func normalizeLanguageCode(_ code: String) -> String {
        switch code.lowercased() {
        case "zh-hans", "zh-cn", "zh-sg":
            return "zh_hans"
        case "zh-hant", "zh-tw", "zh-hk", "zh-mo":
            return "zh_hant"
        default:
            return String(code.prefix(2))  // Take first 2 characters (e.g., "en-US" → "en")
        }
    }

    // MARK: - Download

    /// Download knowledge bases for multiple languages
    /// - Parameter languages: Array of language codes to download
    func downloadKnowledgeBases(languages: [String]) async throws {
        isDownloading = true
        defer { isDownloading = false }

        for language in languages {
            print("[KBManager] Downloading KB for language: \(language)")

            do {
                try await downloadKnowledgeBase(language: language)
                print("[KBManager] Successfully downloaded KB for: \(language)")

                // Index after download
                try await indexKnowledgeBase(language)
                print("[KBManager] Successfully indexed KB for: \(language)")
            } catch {
                print("[KBManager] Error downloading/indexing KB for \(language): \(error)")
                // Continue with other languages even if one fails
                throw error
            }
        }
    }

    /// Download knowledge base for a single language
    /// - Parameter language: Language code (e.g., "ja", "en")
    private func downloadKnowledgeBase(language: String) async throws {
        // Construct download URL
        let filename = "emergency_kb_\(language).json.gz"
        let downloadURL = "\(githubReleaseBase)/\(currentVersion)/\(filename)"

        guard let url = URL(string: downloadURL) else {
            throw KBManagerError.invalidURL
        }

        print("[KBManager] Downloading from: \(downloadURL)")

        // Initialize progress
        var newProgress = downloadProgress
        newProgress[language] = 0
        downloadProgress = newProgress

        // Download with progress tracking
        let (tempURL, _) = try await downloadWithProgress(from: url, language: language)

        // Set to 100% before decompression
        var completeProgress = downloadProgress
        completeProgress[language] = 1.0
        downloadProgress = completeProgress

        // Decompress gzip
        let decompressedURL = try await decompressGzip(from: tempURL, language: language)

        // Move to final destination
        let destinationPath = kbDirectory.appendingPathComponent("emergency_kb_\(language).json")
        if fileManager.fileExists(atPath: destinationPath.path) {
            try fileManager.removeItem(at: destinationPath)
        }
        try fileManager.moveItem(at: decompressedURL, to: destinationPath)

        // Clean up temp file
        try? fileManager.removeItem(at: tempURL)

        // Remove from progress
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s delay
            var newProgress = self.downloadProgress
            newProgress.removeValue(forKey: language)
            self.downloadProgress = newProgress
        }
    }

    private func downloadWithProgress(from url: URL, language: String) async throws -> (URL, URLResponse) {
        try await withCheckedThrowingContinuation { continuation in
            let delegate = KBDownloadDelegate(
                language: language,
                progressHandler: { [weak self] progress in
                    Task { @MainActor in
                        guard let self = self else { return }
                        var newProgress = self.downloadProgress
                        newProgress[language] = progress
                        self.downloadProgress = newProgress
                    }
                },
                completionHandler: { result in
                    switch result {
                    case .success(let tempURL):
                        let response = URLResponse(url: url, mimeType: nil, expectedContentLength: 0, textEncodingName: nil)
                        continuation.resume(returning: (tempURL, response))
                    case .failure(let error):
                        continuation.resume(throwing: error)
                    }
                }
            )

            let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
            let task = session.downloadTask(with: url)
            task.resume()
        }
    }

    /// Decompress gzip file
    private func decompressGzip(from sourceURL: URL, language: String) async throws -> URL {
        return try await Task.detached(priority: .userInitiated) {
            let sourceData = try Data(contentsOf: sourceURL)
            let decompressed = try self.decompressData(sourceData)

            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("kb_\(language)_\(UUID().uuidString).json")
            try decompressed.write(to: tempURL)

            return tempURL
        }.value
    }

    /// Decompress gzip data
    nonisolated private func decompressData(_ compressedData: Data) throws -> Data {
        let bufferSize = 64 * 1024  // 64KB buffer
        var decompressedData = Data()

        try compressedData.withUnsafeBytes { (compressedPtr: UnsafeRawBufferPointer) in
            var stream = compression_stream(
                dst_ptr: nil,
                dst_size: 0,
                src_ptr: nil,
                src_size: 0,
                state: nil
            )
            var status = compression_stream_init(&stream, COMPRESSION_STREAM_DECODE, COMPRESSION_ZLIB)
            guard status == COMPRESSION_STATUS_OK else {
                throw KBManagerError.decompressionFailed
            }
            defer {
                compression_stream_destroy(&stream)
            }

            stream.src_ptr = compressedPtr.baseAddress!.assumingMemoryBound(to: UInt8.self)
            stream.src_size = compressedData.count

            var outputBuffer = [UInt8](repeating: 0, count: bufferSize)

            repeat {
                stream.dst_ptr = &outputBuffer
                stream.dst_size = bufferSize

                status = compression_stream_process(&stream, 0)

                switch status {
                case COMPRESSION_STATUS_OK, COMPRESSION_STATUS_END:
                    let bytesWritten = bufferSize - stream.dst_size
                    decompressedData.append(&outputBuffer, count: bytesWritten)
                case COMPRESSION_STATUS_ERROR:
                    throw KBManagerError.decompressionFailed
                default:
                    break
                }
            } while status == COMPRESSION_STATUS_OK

            guard status == COMPRESSION_STATUS_END else {
                throw KBManagerError.decompressionFailed
            }
        }

        return decompressedData
    }

    // MARK: - Indexing

    /// Index knowledge base into FTS5 for search
    /// - Parameter language: Language code
    func indexKnowledgeBase(_ language: String) async throws {
        let kbPath = kbDirectory.appendingPathComponent("emergency_kb_\(language).json")

        guard fileManager.fileExists(atPath: kbPath.path) else {
            throw KBManagerError.fileNotFound
        }

        let data = try Data(contentsOf: kbPath)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw KBManagerError.invalidJSON
        }

        // Index in search engine
        try searchEngine.indexKnowledgeBase(json, language: language)

        // Save version info
        saveVersionInfo(for: language)
    }

    // MARK: - Version Management

    private func saveVersionInfo(for language: String) {
        let versionPath = kbDirectory.appendingPathComponent(".version_\(language)")
        try? currentVersion.write(to: versionPath, atomically: true, encoding: .utf8)
    }

    private func getInstalledVersion(for language: String) -> String? {
        let versionPath = kbDirectory.appendingPathComponent(".version_\(language)")
        return try? String(contentsOf: versionPath, encoding: .utf8)
    }

    // MARK: - Status Checks

    /// Check if language is downloaded and indexed
    func isLanguageReady(_ code: String) -> Bool {
        let kbPath = kbDirectory.appendingPathComponent("emergency_kb_\(code).json")
        let versionPath = kbDirectory.appendingPathComponent(".version_\(code)")

        // File must exist and be indexed
        guard fileManager.fileExists(atPath: kbPath.path),
              fileManager.fileExists(atPath: versionPath.path) else {
            return false
        }

        // Check if indexed in search engine
        let indexedCount = searchEngine.getIndexedCount(for: code)
        return indexedCount > 0
    }

    /// Check for updates (compare installed version with current version)
    func checkForUpdates() async throws -> [String] {
        var updatesAvailable: [String] = []

        for language in availableLanguages {
            if let installedVersion = getInstalledVersion(for: language.code) {
                if installedVersion != currentVersion {
                    updatesAvailable.append(language.code)
                }
            }
        }

        return updatesAvailable
    }

    /// Download and index a single language
    func downloadAndIndex(_ language: String) async throws {
        try await downloadKnowledgeBase(language: language)
        try await indexKnowledgeBase(language)
    }

    /// Get total size of all KBs for specified languages
    func getTotalSize(for languages: [String]) -> Int64 {
        var total: Int64 = 0
        for lang in languages {
            if let kbLang = availableLanguages.first(where: { $0.code == lang }) {
                total += kbLang.sizeBytes
            }
        }
        return total
    }

    /// Delete KB for a language
    func deleteKnowledgeBase(_ language: String) throws {
        let kbPath = kbDirectory.appendingPathComponent("emergency_kb_\(language).json")
        let versionPath = kbDirectory.appendingPathComponent(".version_\(language)")

        if fileManager.fileExists(atPath: kbPath.path) {
            try fileManager.removeItem(at: kbPath)
        }

        if fileManager.fileExists(atPath: versionPath.path) {
            try fileManager.removeItem(at: versionPath)
        }

        // Clear from search index
        searchEngine.rebuildIndex()  // Simplified: rebuild entire index
    }
}

// MARK: - Language Model

struct KBLanguage: Identifiable {
    let id = UUID()
    let code: String           // "ja", "en", etc.
    let displayName: String    // "日本語", "English"
    let displayNameEn: String  // English name for UI
    let sizeBytes: Int64       // Approximate size in bytes
}

// MARK: - Download Delegate

private final class KBDownloadDelegate: NSObject, URLSessionDownloadDelegate {
    private let language: String
    private let progressHandler: (Double) -> Void
    private let completionHandler: (Result<URL, Error>) -> Void

    init(language: String,
         progressHandler: @escaping (Double) -> Void,
         completionHandler: @escaping (Result<URL, Error>) -> Void) {
        self.language = language
        self.progressHandler = progressHandler
        self.completionHandler = completionHandler
        super.init()
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }

        let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        progressHandler(min(progress, 1.0))
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // Move to persistent temp location
        let persistentTemp = FileManager.default.temporaryDirectory.appendingPathComponent("kb_\(language)_\(UUID().uuidString).gz")
        do {
            try FileManager.default.moveItem(at: location, to: persistentTemp)
            completionHandler(.success(persistentTemp))
        } catch {
            completionHandler(.failure(error))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            completionHandler(.failure(error))
        }
    }
}

// MARK: - Errors

enum KBManagerError: Error, LocalizedError {
    case invalidURL
    case downloadFailed
    case decompressionFailed
    case fileNotFound
    case invalidJSON
    case indexingFailed

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "無効なURL"
        case .downloadFailed:
            return "ダウンロードに失敗しました"
        case .decompressionFailed:
            return "解凍に失敗しました"
        case .fileNotFound:
            return "ファイルが見つかりません"
        case .invalidJSON:
            return "無効なJSON形式"
        case .indexingFailed:
            return "インデックス作成に失敗しました"
        }
    }
}
