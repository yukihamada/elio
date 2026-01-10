import Foundation
import CoreML
import Compression
import UIKit

// Device tier for model recommendations
enum DeviceTier: Int, Comparable {
    case low = 1      // iPhone 12 and below, 4GB RAM
    case medium = 2   // iPhone 13/14, 6GB RAM
    case high = 3     // iPhone 15 Pro/16, 8GB RAM
    case ultra = 4    // iPhone 15 Pro Max/16 Pro Max, Mac, 8GB+ RAM

    static func < (lhs: DeviceTier, rhs: DeviceTier) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    static var current: DeviceTier {
        #if targetEnvironment(macCatalyst)
        // Mac Catalyst - use memory-based detection
        let memory = ProcessInfo.processInfo.physicalMemory
        if memory >= 16 * 1024 * 1024 * 1024 {
            return .ultra
        } else if memory >= 8 * 1024 * 1024 * 1024 {
            return .high
        }
        return .medium
        #else
        var systemInfo = utsname()
        uname(&systemInfo)
        let machineMirror = Mirror(reflecting: systemInfo.machine)
        let identifier = machineMirror.children.reduce("") { identifier, element in
            guard let value = element.value as? Int8, value != 0 else { return identifier }
            return identifier + String(UnicodeScalar(UInt8(value)))
        }

        // iPad identifiers
        switch identifier {
        // iPad Pro M4 / M2 / M1
        case let id where id.hasPrefix("iPad16"), let id where id.hasPrefix("iPad14"), let id where id.hasPrefix("iPad13"):
            return .ultra
        // iPad Air M2 / M1
        case let id where id.hasPrefix("iPad15"):
            return .high
        // iPad mini 6, iPad 10th gen
        case let id where id.hasPrefix("iPad11"), let id where id.hasPrefix("iPad12"):
            return .medium
        // Older iPads
        case let id where id.hasPrefix("iPad"):
            return .medium
        // iPhone identifiers
        case let id where id.hasPrefix("iPhone18"):
            return .ultra
        case "iPhone17,2":
            return .ultra
        case "iPhone17,1":
            return .high
        case "iPhone17,4", "iPhone17,3":
            return .medium
        case "iPhone16,2":
            return .ultra
        case "iPhone16,1":
            return .high
        case "iPhone16,4", "iPhone16,3":
            return .medium
        case "iPhone15,3", "iPhone15,2":
            return .high
        case "iPhone15,4", "iPhone15,5":
            return .medium
        case "iPhone14,3", "iPhone14,2", "iPhone14,5", "iPhone14,4":
            return .medium
        // Simulator or Mac
        case "x86_64", "arm64":
            let memory = ProcessInfo.processInfo.physicalMemory
            if memory >= 16 * 1024 * 1024 * 1024 {
                return .ultra
            } else if memory >= 8 * 1024 * 1024 * 1024 {
                return .high
            } else if memory >= 6 * 1024 * 1024 * 1024 {
                return .medium
            }
            return .low
        default:
            return .low
        }
        #endif
    }

    var displayName: String {
        #if targetEnvironment(macCatalyst)
        switch self {
        case .low: return "Mac (ベーシック)"
        case .medium: return "Mac (スタンダード)"
        case .high: return "Mac (Pro)"
        case .ultra: return "Mac (高性能)"
        }
        #else
        if UIDevice.current.userInterfaceIdiom == .pad {
            switch self {
            case .low: return "iPad (ベーシック)"
            case .medium: return "iPad"
            case .high: return "iPad Air"
            case .ultra: return "iPad Pro"
            }
        }
        switch self {
        case .low: return "エントリー"
        case .medium: return "スタンダード"
        case .high: return "Pro"
        case .ultra: return "Pro Max"
        }
        #endif
    }

    var recommendedModelSize: String {
        switch self {
        case .low: return "0.6B〜1B"
        case .medium: return "1B〜3B"
        case .high: return "3B〜4B"
        case .ultra: return "4B〜8B"
        }
    }
}

// Model tier for matching with device
enum ModelTier: Int, Codable, Comparable {
    case tiny = 1     // 0.6B
    case small = 2    // 1B-1.7B
    case medium = 3   // 2B-3B
    case large = 4    // 4B
    case xlarge = 5   // 7B-8B

    static func < (lhs: ModelTier, rhs: ModelTier) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

@MainActor
final class ModelLoader: ObservableObject {
    @Published var availableModels: [ModelInfo] = []
    @Published var downloadProgress: [String: Double] = [:]
    @Published var isDownloading = false

    private let fileManager = FileManager.default
    let deviceTier = DeviceTier.current

    struct ModelInfo: Identifiable, Codable {
        let id: String
        let name: String
        let description: String
        let descriptionEn: String
        let size: String
        let downloadURL: String
        let config: ModelConfigData
        let tier: ModelTier
        let supportsVision: Bool

        struct ModelConfigData: Codable {
            let maxContextLength: Int
            let vocabularySize: Int
            let eosTokenId: Int
            let bosTokenId: Int
        }

        init(
            id: String,
            name: String,
            description: String,
            descriptionEn: String? = nil,
            size: String,
            downloadURL: String,
            config: ModelConfigData,
            tier: ModelTier,
            supportsVision: Bool = false
        ) {
            self.id = id
            self.name = name
            self.description = description
            self.descriptionEn = descriptionEn ?? description
            self.size = size
            self.downloadURL = downloadURL
            self.config = config
            self.tier = tier
            self.supportsVision = supportsVision
        }

        // Check if this model is recommended for the given device tier
        func isRecommended(for deviceTier: DeviceTier) -> Bool {
            switch deviceTier {
            case .ultra:
                return tier == .large || tier == .xlarge
            case .high:
                return tier == .medium || tier == .large
            case .medium:
                return tier == .small || tier == .medium
            case .low:
                return tier == .tiny || tier == .small
            }
        }

        // Check if model might be too heavy for device
        func isTooHeavy(for deviceTier: DeviceTier) -> Bool {
            switch deviceTier {
            case .ultra:
                return false
            case .high:
                return tier == .xlarge
            case .medium:
                return tier >= .large
            case .low:
                return tier >= .medium
            }
        }
    }

    private var modelsDirectory: URL {
        let dir = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Models", isDirectory: true)

        if !fileManager.fileExists(atPath: dir.path) {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }

        return dir
    }

    init() {
        loadAvailableModels()
    }

    private func loadAvailableModels() {
        availableModels = [
            // Vision Models (画像対応) - Qwen3-VL Series
            ModelInfo(
                id: "qwen3-vl-2b",
                name: "Qwen3-VL 2B",
                description: "📷 最新Qwen3ベースの画像認識。軽量で全デバイス対応。",
                descriptionEn: "📷 Latest Qwen3-based vision. Light, works on all devices.",
                size: "約1.5GB",
                downloadURL: "https://huggingface.co/Qwen/Qwen3-VL-2B-Instruct-GGUF/resolve/main/qwen3-vl-2b-instruct-q4_k_m.gguf",
                config: ModelInfo.ModelConfigData(
                    maxContextLength: 32768,
                    vocabularySize: 151936,
                    eosTokenId: 151645,
                    bosTokenId: 151643
                ),
                tier: .medium,
                supportsVision: true
            ),
            ModelInfo(
                id: "qwen3-vl-4b",
                name: "Qwen3-VL 4B",
                description: "📷 バランス良好な画像認識。Pro以上推奨。",
                descriptionEn: "📷 Well-balanced vision model. Pro or higher recommended.",
                size: "約2.5GB",
                downloadURL: "https://huggingface.co/Qwen/Qwen3-VL-4B-Instruct-GGUF/resolve/main/qwen3-vl-4b-instruct-q4_k_m.gguf",
                config: ModelInfo.ModelConfigData(
                    maxContextLength: 32768,
                    vocabularySize: 151936,
                    eosTokenId: 151645,
                    bosTokenId: 151643
                ),
                tier: .large,
                supportsVision: true
            ),
            ModelInfo(
                id: "qwen3-vl-8b",
                name: "Qwen3-VL 8B",
                description: "📷 最高性能の画像認識。詳細分析・動画理解対応。Pro Max推奨。",
                descriptionEn: "📷 Best vision performance. Detailed analysis & video. Pro Max recommended.",
                size: "約5GB",
                downloadURL: "https://huggingface.co/Qwen/Qwen3-VL-8B-Instruct-GGUF/resolve/main/qwen3-vl-8b-instruct-q4_k_m.gguf",
                config: ModelInfo.ModelConfigData(
                    maxContextLength: 32768,
                    vocabularySize: 151936,
                    eosTokenId: 151645,
                    bosTokenId: 151643
                ),
                tier: .xlarge,
                supportsVision: true
            ),
            // Legacy Vision Models
            ModelInfo(
                id: "smolvlm-instruct",
                name: "SmolVLM 2B",
                description: "📷 軽量画像認識モデル。全デバイス対応。",
                descriptionEn: "📷 Lightweight vision model. Works on all devices.",
                size: "約1.5GB",
                downloadURL: "https://huggingface.co/mradermacher/SmolVLM-Instruct-GGUF/resolve/main/SmolVLM-Instruct.Q4_K_M.gguf",
                config: ModelInfo.ModelConfigData(
                    maxContextLength: 8192,
                    vocabularySize: 49152,
                    eosTokenId: 2,
                    bosTokenId: 1
                ),
                tier: .medium,
                supportsVision: true
            ),
            // Text Models (テキストのみ)
            ModelInfo(
                id: "qwen3-0.6b",
                name: "Qwen3 0.6B",
                description: "超軽量・高速。全デバイス対応。",
                descriptionEn: "Ultra-light and fast. Works on all devices.",
                size: "約500MB",
                downloadURL: "https://huggingface.co/unsloth/Qwen3-0.6B-GGUF/resolve/main/Qwen3-0.6B-Q4_K_M.gguf",
                config: ModelInfo.ModelConfigData(
                    maxContextLength: 40960,
                    vocabularySize: 151936,
                    eosTokenId: 151645,
                    bosTokenId: 151643
                ),
                tier: .tiny
            ),
            ModelInfo(
                id: "qwen3-1.7b",
                name: "Qwen3 1.7B",
                description: "軽量でバランスの良い性能。",
                descriptionEn: "Lightweight with balanced performance.",
                size: "約1.2GB",
                downloadURL: "https://huggingface.co/unsloth/Qwen3-1.7B-GGUF/resolve/main/Qwen3-1.7B-Q4_K_M.gguf",
                config: ModelInfo.ModelConfigData(
                    maxContextLength: 40960,
                    vocabularySize: 151936,
                    eosTokenId: 151645,
                    bosTokenId: 151643
                ),
                tier: .small
            ),
            ModelInfo(
                id: "qwen3-4b",
                name: "Qwen3 4B",
                description: "高性能モデル。Pro以上推奨。",
                descriptionEn: "High performance. Pro or higher recommended.",
                size: "約2.7GB",
                downloadURL: "https://huggingface.co/unsloth/Qwen3-4B-GGUF/resolve/main/Qwen3-4B-Q4_K_M.gguf",
                config: ModelInfo.ModelConfigData(
                    maxContextLength: 40960,
                    vocabularySize: 151936,
                    eosTokenId: 151645,
                    bosTokenId: 151643
                ),
                tier: .large
            ),
            ModelInfo(
                id: "qwen3-8b",
                name: "Qwen3 8B",
                description: "最高性能。Pro Max推奨。",
                descriptionEn: "Best performance. Pro Max recommended.",
                size: "約5GB",
                downloadURL: "https://huggingface.co/unsloth/Qwen3-8B-GGUF/resolve/main/Qwen3-8B-Q4_K_M.gguf",
                config: ModelInfo.ModelConfigData(
                    maxContextLength: 40960,
                    vocabularySize: 151936,
                    eosTokenId: 151645,
                    bosTokenId: 151643
                ),
                tier: .xlarge
            ),
            ModelInfo(
                id: "llama-3.2-1b",
                name: "Llama 3.2 1B",
                description: "Meta製。軽量で高速。",
                descriptionEn: "By Meta. Light and fast.",
                size: "約700MB",
                downloadURL: "https://huggingface.co/bartowski/Llama-3.2-1B-Instruct-GGUF/resolve/main/Llama-3.2-1B-Instruct-Q4_K_M.gguf",
                config: ModelInfo.ModelConfigData(
                    maxContextLength: 131072,
                    vocabularySize: 128256,
                    eosTokenId: 128001,
                    bosTokenId: 128000
                ),
                tier: .small
            ),
            ModelInfo(
                id: "llama-3.2-3b",
                name: "Llama 3.2 3B",
                description: "Meta製。バランス良好。",
                descriptionEn: "By Meta. Well balanced.",
                size: "約2GB",
                downloadURL: "https://huggingface.co/bartowski/Llama-3.2-3B-Instruct-GGUF/resolve/main/Llama-3.2-3B-Instruct-Q4_K_M.gguf",
                config: ModelInfo.ModelConfigData(
                    maxContextLength: 131072,
                    vocabularySize: 128256,
                    eosTokenId: 128001,
                    bosTokenId: 128000
                ),
                tier: .medium
            ),
            ModelInfo(
                id: "phi-3.5-mini",
                name: "Phi-3.5 Mini",
                description: "Microsoft製。コンパクト高性能。",
                descriptionEn: "By Microsoft. Compact and powerful.",
                size: "約2.2GB",
                downloadURL: "https://huggingface.co/bartowski/Phi-3.5-mini-instruct-GGUF/resolve/main/Phi-3.5-mini-instruct-Q4_K_M.gguf",
                config: ModelInfo.ModelConfigData(
                    maxContextLength: 131072,
                    vocabularySize: 32064,
                    eosTokenId: 32000,
                    bosTokenId: 1
                ),
                tier: .medium
            ),
            ModelInfo(
                id: "gemma-2-2b",
                name: "Gemma 2 2B",
                description: "Google製。軽量高性能。",
                descriptionEn: "By Google. Light and powerful.",
                size: "約1.6GB",
                downloadURL: "https://huggingface.co/bartowski/gemma-2-2b-it-GGUF/resolve/main/gemma-2-2b-it-Q4_K_M.gguf",
                config: ModelInfo.ModelConfigData(
                    maxContextLength: 8192,
                    vocabularySize: 256000,
                    eosTokenId: 1,
                    bosTokenId: 2
                ),
                tier: .medium
            ),
            // DeepSeek-R1 Distill Models
            ModelInfo(
                id: "deepseek-r1-distill-qwen-1.5b",
                name: "DeepSeek-R1 1.5B",
                description: "高度な推論能力。軽量版。",
                descriptionEn: "Advanced reasoning. Lightweight.",
                size: "約1.1GB",
                downloadURL: "https://huggingface.co/unsloth/DeepSeek-R1-Distill-Qwen-1.5B-GGUF/resolve/main/DeepSeek-R1-Distill-Qwen-1.5B-Q4_K_M.gguf",
                config: ModelInfo.ModelConfigData(
                    maxContextLength: 32768,
                    vocabularySize: 151936,
                    eosTokenId: 151645,
                    bosTokenId: 151643
                ),
                tier: .small
            ),
            ModelInfo(
                id: "deepseek-r1-distill-qwen-7b",
                name: "DeepSeek-R1 7B",
                description: "高い推論性能。Pro推奨。",
                descriptionEn: "High reasoning performance. Pro recommended.",
                size: "約4.7GB",
                downloadURL: "https://huggingface.co/unsloth/DeepSeek-R1-Distill-Qwen-7B-GGUF/resolve/main/DeepSeek-R1-Distill-Qwen-7B-Q4_K_M.gguf",
                config: ModelInfo.ModelConfigData(
                    maxContextLength: 32768,
                    vocabularySize: 151936,
                    eosTokenId: 151645,
                    bosTokenId: 151643
                ),
                tier: .xlarge
            ),
            ModelInfo(
                id: "deepseek-r1-distill-llama-8b",
                name: "DeepSeek-R1 8B",
                description: "最高の推論性能。Pro Max推奨。",
                descriptionEn: "Best reasoning performance. Pro Max recommended.",
                size: "約5GB",
                downloadURL: "https://huggingface.co/unsloth/DeepSeek-R1-Distill-Llama-8B-GGUF/resolve/main/DeepSeek-R1-Distill-Llama-8B-Q4_K_M.gguf",
                config: ModelInfo.ModelConfigData(
                    maxContextLength: 131072,
                    vocabularySize: 128256,
                    eosTokenId: 128001,
                    bosTokenId: 128000
                ),
                tier: .xlarge
            )
        ]
    }

    func getDownloadedModels() -> [String] {
        guard let contents = try? fileManager.contentsOfDirectory(
            at: modelsDirectory,
            includingPropertiesForKeys: nil
        ) else {
            return []
        }

        return contents
            .filter { $0.pathExtension == "gguf" || $0.pathExtension == "mlpackage" || $0.pathExtension == "mlmodelc" }
            .map { $0.deletingPathExtension().lastPathComponent }
    }

    func getModelInfo(_ modelId: String) -> ModelInfo? {
        availableModels.first { $0.id == modelId }
    }

    func modelSupportsVision(_ modelId: String) -> Bool {
        getModelInfo(modelId)?.supportsVision ?? false
    }

    func isModelDownloaded(_ modelId: String) -> Bool {
        let ggufPath = modelsDirectory.appendingPathComponent("\(modelId).gguf")
        let modelPath = modelsDirectory.appendingPathComponent("\(modelId).mlpackage")
        let compiledPath = modelsDirectory.appendingPathComponent("\(modelId).mlmodelc")
        return fileManager.fileExists(atPath: ggufPath.path) ||
               fileManager.fileExists(atPath: modelPath.path) ||
               fileManager.fileExists(atPath: compiledPath.path)
    }

    func getModelPath(_ modelId: String) -> URL? {
        let ggufPath = modelsDirectory.appendingPathComponent("\(modelId).gguf")
        if fileManager.fileExists(atPath: ggufPath.path) {
            return ggufPath
        }
        let modelPath = modelsDirectory.appendingPathComponent("\(modelId).mlpackage")
        if fileManager.fileExists(atPath: modelPath.path) {
            return modelPath
        }
        let compiledPath = modelsDirectory.appendingPathComponent("\(modelId).mlmodelc")
        if fileManager.fileExists(atPath: compiledPath.path) {
            return compiledPath
        }
        return nil
    }

    func downloadModel(_ model: ModelInfo) async throws {
        guard let url = URL(string: model.downloadURL) else {
            throw ModelLoaderError.invalidURL
        }

        isDownloading = true
        downloadProgress[model.id] = 0

        defer {
            isDownloading = false
            downloadProgress.removeValue(forKey: model.id)
        }

        // Create models directory if needed
        if !fileManager.fileExists(atPath: modelsDirectory.path) {
            try fileManager.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)
        }

        // Use URLSessionDownloadTask with delegate for progress
        let (tempURL, _) = try await downloadWithProgress(from: url, modelId: model.id)

        // Determine file extension from URL or response
        let fileExtension = url.pathExtension.lowercased()

        if fileExtension == "gguf" {
            // Direct GGUF file - just move it
            let destinationPath = modelsDirectory.appendingPathComponent("\(model.id).gguf")
            if fileManager.fileExists(atPath: destinationPath.path) {
                try fileManager.removeItem(at: destinationPath)
            }
            try fileManager.moveItem(at: tempURL, to: destinationPath)
        } else if fileExtension == "zip" {
            // ZIP file - extract it
            let destinationDir = modelsDirectory.appendingPathComponent(model.id)
            try fileManager.createDirectory(at: destinationDir, withIntermediateDirectories: true)
            try await unzipModel(from: tempURL, to: destinationDir)
            try fileManager.removeItem(at: tempURL)
        } else {
            // Unknown format - try to move as-is
            let destinationPath = modelsDirectory.appendingPathComponent("\(model.id).\(fileExtension)")
            if fileManager.fileExists(atPath: destinationPath.path) {
                try fileManager.removeItem(at: destinationPath)
            }
            try fileManager.moveItem(at: tempURL, to: destinationPath)
        }
    }

    private func downloadWithProgress(from url: URL, modelId: String) async throws -> (URL, URLResponse) {
        try await withCheckedThrowingContinuation { continuation in
            let delegate = DownloadDelegate { [weak self] progress in
                Task { @MainActor in
                    self?.downloadProgress[modelId] = progress
                }
            }

            let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
            let task = session.downloadTask(with: url) { tempURL, response, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let tempURL = tempURL, let response = response else {
                    continuation.resume(throwing: ModelLoaderError.downloadFailed)
                    return
                }

                // Move to a persistent temp location before returning
                let persistentTemp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
                do {
                    try FileManager.default.moveItem(at: tempURL, to: persistentTemp)
                    continuation.resume(returning: (persistentTemp, response))
                } catch {
                    continuation.resume(throwing: error)
                }
            }

            task.resume()
        }
    }

    private func unzipModel(from source: URL, to destination: URL) async throws {
        try await Task.detached(priority: .userInitiated) {
            try self.extractZIP(from: source, to: destination)
        }.value
    }

    nonisolated private func extractZIP(from source: URL, to destination: URL) throws {
        guard let archive = ZIPArchive(url: source) else {
            throw ModelLoaderError.extractionFailed
        }

        try archive.extractAll(to: destination)
    }
}

// MARK: - Simple ZIP Extraction for iOS

private final class ZIPArchive {
    private let fileHandle: FileHandle
    private let fileSize: UInt64

    init?(url: URL) {
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            return nil
        }
        self.fileHandle = handle

        do {
            let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
            self.fileSize = attrs[.size] as? UInt64 ?? 0
        } catch {
            return nil
        }
    }

    deinit {
        try? fileHandle.close()
    }

    func extractAll(to destination: URL) throws {
        let fileManager = FileManager.default

        try fileHandle.seek(toOffset: 0)
        let data = fileHandle.readDataToEndOfFile()

        var offset = 0

        while offset < data.count - 4 {
            let signature = data.subdata(in: offset..<offset+4).withUnsafeBytes { $0.load(as: UInt32.self) }

            guard signature == 0x04034b50 else {
                break
            }

            let header = data.subdata(in: offset..<min(offset+30, data.count))
            guard header.count >= 30 else { break }

            let compressionMethod = header.subdata(in: 8..<10).withUnsafeBytes { $0.load(as: UInt16.self) }
            let compressedSize = header.subdata(in: 18..<22).withUnsafeBytes { $0.load(as: UInt32.self) }
            let uncompressedSize = header.subdata(in: 22..<26).withUnsafeBytes { $0.load(as: UInt32.self) }
            let fileNameLength = header.subdata(in: 26..<28).withUnsafeBytes { $0.load(as: UInt16.self) }
            let extraFieldLength = header.subdata(in: 28..<30).withUnsafeBytes { $0.load(as: UInt16.self) }

            let fileNameStart = offset + 30
            let fileNameEnd = fileNameStart + Int(fileNameLength)
            guard fileNameEnd <= data.count else { break }

            let fileNameData = data.subdata(in: fileNameStart..<fileNameEnd)
            guard let fileName = String(data: fileNameData, encoding: .utf8) else {
                offset = fileNameEnd + Int(extraFieldLength) + Int(compressedSize)
                continue
            }

            let fileDataStart = fileNameEnd + Int(extraFieldLength)
            let fileDataEnd = fileDataStart + Int(compressedSize)
            guard fileDataEnd <= data.count else { break }

            let compressedData = data.subdata(in: fileDataStart..<fileDataEnd)
            let filePath = destination.appendingPathComponent(fileName)

            if fileName.hasSuffix("/") {
                try fileManager.createDirectory(at: filePath, withIntermediateDirectories: true)
            } else {
                let parentDir = filePath.deletingLastPathComponent()
                if !fileManager.fileExists(atPath: parentDir.path) {
                    try fileManager.createDirectory(at: parentDir, withIntermediateDirectories: true)
                }

                let fileData: Data
                if compressionMethod == 0 {
                    fileData = compressedData
                } else if compressionMethod == 8 {
                    fileData = try decompressDeflate(compressedData, uncompressedSize: Int(uncompressedSize))
                } else {
                    offset = fileDataEnd
                    continue
                }

                try fileData.write(to: filePath)
            }

            offset = fileDataEnd
        }
    }

    private func decompressDeflate(_ data: Data, uncompressedSize: Int) throws -> Data {
        var decompressedData = Data(count: uncompressedSize)

        let result = decompressedData.withUnsafeMutableBytes { destBuffer in
            data.withUnsafeBytes { srcBuffer in
                compression_decode_buffer(
                    destBuffer.bindMemory(to: UInt8.self).baseAddress!,
                    uncompressedSize,
                    srcBuffer.bindMemory(to: UInt8.self).baseAddress!,
                    data.count,
                    nil,
                    COMPRESSION_ZLIB
                )
            }
        }

        guard result > 0 else {
            throw ModelLoaderError.extractionFailed
        }

        return decompressedData.prefix(result)
    }
}

// MARK: - Download Delegate

private final class DownloadDelegate: NSObject, URLSessionDownloadDelegate {
    private let progressHandler: (Double) -> Void

    init(progressHandler: @escaping (Double) -> Void) {
        self.progressHandler = progressHandler
        super.init()
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        if totalBytesExpectedToWrite > 0 {
            let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
            progressHandler(progress)
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // Handled in completion handler
    }
}

// MARK: - ModelLoader Extensions

extension ModelLoader {
    func loadModel(named modelId: String) async throws -> CoreMLInference {
        guard let modelInfo = availableModels.first(where: { $0.id == modelId }) else {
            throw ModelLoaderError.modelNotFound
        }

        // Check for GGUF file first
        let ggufPath = modelsDirectory.appendingPathComponent("\(modelId).gguf")
        if fileManager.fileExists(atPath: ggufPath.path) {
            // GGUF model - needs llama.cpp integration
            // For now, return a placeholder that indicates GGUF support needed
            let config = CoreMLInference.ModelConfig(
                name: modelInfo.name,
                maxContextLength: modelInfo.config.maxContextLength,
                vocabularySize: modelInfo.config.vocabularySize,
                eosTokenId: modelInfo.config.eosTokenId,
                bosTokenId: modelInfo.config.bosTokenId
            )

            let inference = CoreMLInference(config: config)
            try await inference.loadGGUFModel(from: ggufPath)
            return inference
        }

        // Check for mlpackage
        let modelPath = modelsDirectory.appendingPathComponent(modelId).appendingPathComponent("model.mlpackage")
        if fileManager.fileExists(atPath: modelPath.path) {
            let config = CoreMLInference.ModelConfig(
                name: modelInfo.name,
                maxContextLength: modelInfo.config.maxContextLength,
                vocabularySize: modelInfo.config.vocabularySize,
                eosTokenId: modelInfo.config.eosTokenId,
                bosTokenId: modelInfo.config.bosTokenId
            )

            let inference = CoreMLInference(config: config)
            try await inference.loadModel(from: modelPath)
            return inference
        }

        throw ModelLoaderError.modelNotFound
    }

    func deleteModel(_ modelId: String) throws {
        let ggufPath = modelsDirectory.appendingPathComponent("\(modelId).gguf")
        let modelDir = modelsDirectory.appendingPathComponent(modelId)
        let compiledDir = modelsDirectory.appendingPathComponent("\(modelId).mlmodelc")

        if fileManager.fileExists(atPath: ggufPath.path) {
            try fileManager.removeItem(at: ggufPath)
        }

        if fileManager.fileExists(atPath: modelDir.path) {
            try fileManager.removeItem(at: modelDir)
        }

        if fileManager.fileExists(atPath: compiledDir.path) {
            try fileManager.removeItem(at: compiledDir)
        }
    }

    func getModelSize(_ modelId: String) -> String? {
        // Check GGUF first
        let ggufPath = modelsDirectory.appendingPathComponent("\(modelId).gguf")
        if let attrs = try? fileManager.attributesOfItem(atPath: ggufPath.path),
           let size = attrs[.size] as? Int64 {
            return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
        }

        // Check directory
        let modelDir = modelsDirectory.appendingPathComponent(modelId)
        if let size = try? fileManager.allocatedSizeOfDirectory(at: modelDir) {
            return ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
        }

        return nil
    }
}

extension FileManager {
    func allocatedSizeOfDirectory(at url: URL) throws -> Int {
        var size = 0
        let contents = try contentsOfDirectory(at: url, includingPropertiesForKeys: [.fileSizeKey])

        for itemURL in contents {
            let resourceValues = try itemURL.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey])

            if resourceValues.isDirectory == true {
                size += try allocatedSizeOfDirectory(at: itemURL)
            } else {
                size += resourceValues.fileSize ?? 0
            }
        }

        return size
    }
}

enum ModelLoaderError: Error, LocalizedError {
    case invalidURL
    case downloadFailed
    case extractionFailed
    case modelNotFound
    case configNotFound

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "無効なURL"
        case .downloadFailed: return "ダウンロードに失敗しました"
        case .extractionFailed: return "展開に失敗しました"
        case .modelNotFound: return "モデルが見つかりません"
        case .configNotFound: return "設定ファイルが見つかりません"
        }
    }
}
