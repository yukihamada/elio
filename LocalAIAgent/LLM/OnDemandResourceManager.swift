@preconcurrency import Foundation
import Combine

/// Manages On-Demand Resources (ODR) for model files
/// ODR allows downloading large resources from App Store CDN when needed
@MainActor
final class OnDemandResourceManager: ObservableObject {

    // MARK: - Singleton
    static let shared = OnDemandResourceManager()

    // MARK: - Published Properties
    @Published private(set) var downloadProgress: [String: Double] = [:]
    @Published private(set) var downloadStatus: [String: ODRStatus] = [:]
    @Published private(set) var isDownloading: Bool = false

    // MARK: - Private Properties
    private var activeRequests: [String: NSBundleResourceRequest] = [:]
    private var progressObservations: [String: NSKeyValueObservation] = [:]

    // MARK: - ODR Configuration
    struct ODRModelConfig {
        let tag: String
        let modelId: String
        let filename: String
        let sizeBytes: Int64
        let priority: Double

        static let eliochat = ODRModelConfig(
            tag: "model-eliochat-jp-v2",
            modelId: "eliochat-1.7b-jp-v2",
            filename: "ElioChat-1.7B-JP-v2-merged-Q4_K_M.gguf",
            sizeBytes: 1_000_000_000,
            priority: 0.8
        )

        static let allConfigs: [ODRModelConfig] = [
            .eliochat
        ]

        static func config(for modelId: String) -> ODRModelConfig? {
            allConfigs.first { $0.modelId == modelId }
        }
    }

    // MARK: - Status
    enum ODRStatus: Equatable {
        case notAvailable       // ODR not available for this resource
        case available          // Ready to download
        case downloading        // Currently downloading
        case downloaded         // Downloaded and accessible
        case error(String)      // Error occurred
    }

    // MARK: - Errors
    enum ODRError: Error, LocalizedError {
        case resourceUnavailable
        case downloadFailed(Error)
        case resourceNotFound
        case copyFailed(Error)
        case cancelled

        var errorDescription: String? {
            switch self {
            case .resourceUnavailable:
                return "このリソースはApp Storeから利用できません"
            case .downloadFailed(let error):
                return "ダウンロード失敗: \(error.localizedDescription)"
            case .resourceNotFound:
                return "リソースが見つかりません"
            case .copyFailed(let error):
                return "ファイルコピー失敗: \(error.localizedDescription)"
            case .cancelled:
                return "ダウンロードがキャンセルされました"
            }
        }
    }

    // MARK: - Initialization
    private init() {}

    // MARK: - Public Methods

    /// Check if ODR is available for a model
    func isODRAvailable(for modelId: String) -> Bool {
        guard ODRModelConfig.config(for: modelId) != nil else {
            return false
        }

        // For development/testing, we might not have actual ODR tags
        // In production, this would check NSBundleResourceRequest availability
        #if DEBUG
        // In debug, check if we have the resource configured
        return ODRModelConfig.allConfigs.contains { $0.modelId == modelId }
        #else
        // In release, check actual ODR availability
        return true // Will be validated when actually requesting
        #endif
    }

    /// Request and download an ODR resource
    func requestResource(for modelId: String, progressHandler: (@Sendable (Double) -> Void)? = nil) async throws -> URL {
        guard let config = ODRModelConfig.config(for: modelId) else {
            throw ODRError.resourceUnavailable
        }

        let tag = config.tag

        // Update status
        downloadStatus[tag] = .downloading
        downloadProgress[tag] = 0
        isDownloading = true

        defer {
            isDownloading = activeRequests.values.contains { _ in true }
        }

        // Create bundle resource request
        // Using nonisolated(unsafe) to suppress Swift 6 Sendable warning
        // This is safe because the request is created and used only on MainActor
        nonisolated(unsafe) let request = NSBundleResourceRequest(tags: [tag])
        request.loadingPriority = config.priority

        // Store request for potential cancellation
        activeRequests[tag] = request

        // Observe progress
        let observation = request.progress.observe(\.fractionCompleted, options: [.new]) { [weak self] progress, _ in
            let fraction = progress.fractionCompleted
            Task { @MainActor in
                self?.downloadProgress[tag] = fraction
                progressHandler?(fraction)
            }
        }
        progressObservations[tag] = observation

        do {
            // Begin accessing resources (this downloads if needed)
            try await request.beginAccessingResources()

            // Resource is now available
            downloadStatus[tag] = .downloaded
            downloadProgress[tag] = 1.0

            // Find the resource in the bundle
            guard let resourceURL = Bundle.main.url(forResource: config.filename, withExtension: nil) else {
                // Try alternative: look in the models subdirectory
                if let altURL = Bundle.main.url(forResource: config.filename, withExtension: nil, subdirectory: "models") {
                    return altURL
                }
                throw ODRError.resourceNotFound
            }

            return resourceURL

        } catch {
            // Clean up on error
            activeRequests.removeValue(forKey: tag)
            progressObservations.removeValue(forKey: tag)
            downloadStatus[tag] = .error(error.localizedDescription)

            if (error as NSError).code == NSUserCancelledError {
                throw ODRError.cancelled
            }
            throw ODRError.downloadFailed(error)
        }
    }

    /// Copy ODR resource to Documents/Models directory for persistent access
    func copyResourceToModels(from sourceURL: URL, modelId: String) async throws -> URL {
        let fileManager = FileManager.default
        guard let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            throw NSError(domain: "OnDemandResourceManager", code: -1,
                         userInfo: [NSLocalizedDescriptionKey: "Documents directory not found"])
        }
        let modelsDirectory = documentsURL.appendingPathComponent("Models", isDirectory: true)

        // Create Models directory if needed
        if !fileManager.fileExists(atPath: modelsDirectory.path) {
            try fileManager.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)
        }

        let destinationURL = modelsDirectory.appendingPathComponent(sourceURL.lastPathComponent)

        // Remove existing file if present
        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }

        do {
            try fileManager.copyItem(at: sourceURL, to: destinationURL)
            return destinationURL
        } catch {
            throw ODRError.copyFailed(error)
        }
    }

    /// Cancel an ongoing download
    func cancelDownload(for modelId: String) {
        guard let config = ODRModelConfig.config(for: modelId) else { return }
        let tag = config.tag

        if let request = activeRequests.removeValue(forKey: tag) {
            request.progress.cancel()
            request.endAccessingResources()
        }

        progressObservations.removeValue(forKey: tag)
        downloadStatus[tag] = .available
        downloadProgress[tag] = 0
    }

    /// Release resources (call when done using the resource)
    func endAccessingResources(for modelId: String) {
        guard let config = ODRModelConfig.config(for: modelId) else { return }
        let tag = config.tag

        if let request = activeRequests.removeValue(forKey: tag) {
            request.endAccessingResources()
        }
        progressObservations.removeValue(forKey: tag)
    }

    /// Get current status for a model
    func status(for modelId: String) -> ODRStatus {
        guard let config = ODRModelConfig.config(for: modelId) else {
            return .notAvailable
        }
        return downloadStatus[config.tag] ?? .available
    }

    /// Get current progress for a model (0.0 - 1.0)
    func progress(for modelId: String) -> Double {
        guard let config = ODRModelConfig.config(for: modelId) else {
            return 0
        }
        return downloadProgress[config.tag] ?? 0
    }
}

// MARK: - ODR Availability Extension
extension OnDemandResourceManager {

    /// Check if device supports ODR and if the model is configured for ODR
    static func isODRSupported(for modelId: String) -> Bool {
        // ODR requires iOS 9.0+, which we support
        // Check if model has ODR configuration
        return ODRModelConfig.config(for: modelId) != nil
    }

    /// Get recommended download method for a model
    static func recommendedDownloadMethod(for modelId: String) -> DownloadMethod {
        if isODRSupported(for: modelId) {
            return .onDemandResource
        }
        return .urlSession
    }

    enum DownloadMethod {
        case onDemandResource  // Use App Store CDN
        case urlSession        // Use direct HTTP download
        case bundled           // Already in app bundle
    }
}
