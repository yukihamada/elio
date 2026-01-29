import Foundation
import AVFoundation

@MainActor
final class ReazonSpeechManager: ObservableObject {
    static let shared = ReazonSpeechManager()

    @Published var isModelDownloaded = false
    @Published var isDownloading = false
    @Published var downloadProgress: Double = 0
    @Published var isRecording = false
    @Published var isTranscribing = false
    @Published var transcribedText = ""
    @Published var errorMessage: String?
    @Published var audioLevel: Float = 0  // Current audio level (0.0 - 1.0)

    private var recognizer: SherpaOnnxOfflineRecognizer?
    private var audioEngine: AVAudioEngine?
    private var audioSamples: [Float] = []
    private let sampleRate: Int = 16000

    // ReazonSpeech model files on Hugging Face (hosted by yukihamada)
    private let modelName = "sherpa-onnx-reazonspeech-ja"
    private let hfBaseURL = "https://huggingface.co/yukihamada/sherpa-onnx-reazonspeech-ja/resolve/main"

    private let modelFiles = [
        "encoder-epoch-99-avg-1.int8.onnx",
        "decoder-epoch-99-avg-1.int8.onnx",
        "joiner-epoch-99-avg-1.int8.onnx",
        "tokens.txt"
    ]

    private var modelsDirectory: URL {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documentsPath.appendingPathComponent("ReazonSpeechModels")
    }

    private var modelPath: URL {
        modelsDirectory.appendingPathComponent(modelName)
    }

    private init() {
        checkModelStatus()
    }

    private func checkModelStatus() {
        let allFilesExist = modelFiles.allSatisfy { fileName in
            let filePath = modelPath.appendingPathComponent(fileName)
            return FileManager.default.fileExists(atPath: filePath.path)
        }

        if allFilesExist {
            isModelDownloaded = true
            UserDefaults.standard.set(true, forKey: "reazonspeech_model_downloaded")
        } else {
            isModelDownloaded = UserDefaults.standard.bool(forKey: "reazonspeech_model_downloaded")
            // If UserDefaults says downloaded but files don't exist, reset
            if isModelDownloaded && !allFilesExist {
                isModelDownloaded = false
                UserDefaults.standard.set(false, forKey: "reazonspeech_model_downloaded")
            }
        }
    }

    // MARK: - Model Management

    func downloadModelIfNeeded() async throws {
        print("[ReazonSpeech] downloadModelIfNeeded called")
        checkModelStatus()

        guard !isModelDownloaded else {
            print("[ReazonSpeech] Model already downloaded, loading...")
            try await loadModel()
            return
        }

        print("[ReazonSpeech] Starting download, isDownloading = true")
        isDownloading = true
        downloadProgress = 0
        errorMessage = nil

        do {
            // Create model directory
            print("[ReazonSpeech] Creating directory: \(modelPath.path)")
            try FileManager.default.createDirectory(at: modelPath, withIntermediateDirectories: true)

            // Download each file
            let totalFiles = modelFiles.count
            for (index, fileName) in modelFiles.enumerated() {
                let fileURL = URL(string: "\(hfBaseURL)/\(fileName)")!
                let destinationURL = modelPath.appendingPathComponent(fileName)

                print("[ReazonSpeech] Downloading file \(index + 1)/\(totalFiles): \(fileName)")
                print("[ReazonSpeech] URL: \(fileURL)")

                // Skip if already downloaded
                if FileManager.default.fileExists(atPath: destinationURL.path) {
                    print("[ReazonSpeech] File already exists, skipping")
                    downloadProgress = Double(index + 1) / Double(totalFiles)
                    continue
                }

                let baseProgress = Double(index) / Double(totalFiles)
                let fileWeight = 1.0 / Double(totalFiles)

                try await downloadFile(from: fileURL, to: destinationURL) { [weak self] progress in
                    Task { @MainActor [weak self] in
                        self?.downloadProgress = baseProgress + progress * fileWeight
                    }
                }
                print("[ReazonSpeech] File downloaded: \(fileName)")
            }

            isModelDownloaded = true
            downloadProgress = 1.0
            UserDefaults.standard.set(true, forKey: "reazonspeech_model_downloaded")
            print("[ReazonSpeech] All files downloaded, loading model...")

            try await loadModel()

            isDownloading = false
            print("[ReazonSpeech] Download complete, isDownloading = false")
        } catch {
            isDownloading = false
            errorMessage = "モデルのダウンロードに失敗しました: \(error.localizedDescription)"
            print("[ReazonSpeech] Download error: \(error)")
            throw error
        }
    }

    private func downloadFile(from url: URL, to destination: URL, progressHandler: @escaping (Double) -> Void) async throws {
        print("[ReazonSpeech] downloadFile starting: \(url)")

        // Use URLSession.download for efficient large file downloads
        let (tempURL, response) = try await URLSession.shared.download(from: url)
        print("[ReazonSpeech] Got response")

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            print("[ReazonSpeech] Bad HTTP response: \((response as? HTTPURLResponse)?.statusCode ?? -1)")
            throw ReazonSpeechError.downloadFailed
        }

        print("[ReazonSpeech] HTTP status: \(httpResponse.statusCode)")
        print("[ReazonSpeech] Download complete")

        // Final progress update
        progressHandler(1.0)

        // Move to destination
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: tempURL, to: destination)
        print("[ReazonSpeech] File moved to: \(destination.path)")
    }

    private func loadModel() async throws {
        guard recognizer == nil else { return }

        let tokensPath = modelPath.appendingPathComponent("tokens.txt")
        let encoderPath = modelPath.appendingPathComponent("encoder-epoch-99-avg-1.int8.onnx")
        let decoderPath = modelPath.appendingPathComponent("decoder-epoch-99-avg-1.int8.onnx")
        let joinerPath = modelPath.appendingPathComponent("joiner-epoch-99-avg-1.int8.onnx")

        guard FileManager.default.fileExists(atPath: tokensPath.path),
              FileManager.default.fileExists(atPath: encoderPath.path),
              FileManager.default.fileExists(atPath: decoderPath.path),
              FileManager.default.fileExists(atPath: joinerPath.path) else {
            isModelDownloaded = false
            UserDefaults.standard.set(false, forKey: "reazonspeech_model_downloaded")
            throw ReazonSpeechError.modelNotFound
        }

        // Create transducer config for Zipformer
        let transducerConfig = sherpaOnnxOfflineTransducerModelConfig(
            encoder: encoderPath.path,
            decoder: decoderPath.path,
            joiner: joinerPath.path
        )

        let modelConfig = sherpaOnnxOfflineModelConfig(
            tokens: tokensPath.path,
            transducer: transducerConfig,
            numThreads: 2,
            debug: 0,
            modelType: "zipformer2"
        )

        let featConfig = sherpaOnnxFeatureConfig(
            sampleRate: sampleRate,
            featureDim: 80
        )

        var config = sherpaOnnxOfflineRecognizerConfig(
            featConfig: featConfig,
            modelConfig: modelConfig
        )

        recognizer = SherpaOnnxOfflineRecognizer(config: &config)

        isModelDownloaded = true
        UserDefaults.standard.set(true, forKey: "reazonspeech_model_downloaded")
    }

    // MARK: - Recording

    func startRecording() async throws {
        guard !isRecording else { return }

        if recognizer == nil {
            try await loadModel()
        }

        let permission = await AVAudioApplication.requestRecordPermission()
        guard permission else {
            errorMessage = "マイクへのアクセスが拒否されました"
            throw ReazonSpeechError.permissionDenied
        }

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
        try session.setActive(true)

        audioSamples = []
        audioEngine = AVAudioEngine()

        guard let audioEngine = audioEngine else {
            throw ReazonSpeechError.audioEngineError
        }

        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        // Output format: 16kHz mono float32
        let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Double(sampleRate),
            channels: 1,
            interleaved: false
        )!

        let converter = AVAudioConverter(from: inputFormat, to: outputFormat)!

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
            guard let self = self else { return }

            var newBufferAvailable = true
            let inputCallback: AVAudioConverterInputBlock = { _, outStatus in
                if newBufferAvailable {
                    outStatus.pointee = .haveData
                    newBufferAvailable = false
                    return buffer
                } else {
                    outStatus.pointee = .noDataNow
                    return nil
                }
            }

            let convertedBuffer = AVAudioPCMBuffer(
                pcmFormat: outputFormat,
                frameCapacity: AVAudioFrameCount(Double(outputFormat.sampleRate) * Double(buffer.frameLength) / inputFormat.sampleRate)
            )!

            var error: NSError?
            _ = converter.convert(to: convertedBuffer, error: &error, withInputFrom: inputCallback)

            if let floatData = convertedBuffer.floatChannelData?[0] {
                let samples = Array(UnsafeBufferPointer(start: floatData, count: Int(convertedBuffer.frameLength)))

                // Calculate RMS audio level
                let sumSquares = samples.reduce(0) { $0 + $1 * $1 }
                let rms = sqrt(sumSquares / Float(samples.count))
                // Normalize to 0-1 range (typical voice RMS is 0.01-0.3)
                let normalizedLevel = min(1.0, rms * 5.0)

                Task { @MainActor [weak self] in
                    self?.audioSamples.append(contentsOf: samples)
                    self?.audioLevel = normalizedLevel
                }
            }
        }

        try audioEngine.start()
        isRecording = true
        transcribedText = ""
    }

    func stopRecording() async throws -> String {
        guard isRecording else {
            throw ReazonSpeechError.notRecording
        }

        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine = nil
        isRecording = false

        return try await transcribe()
    }

    func cancelRecording() {
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine = nil
        isRecording = false
        audioSamples = []
        audioLevel = 0
    }

    // MARK: - Transcription

    private func transcribe() async throws -> String {
        guard !audioSamples.isEmpty else {
            throw ReazonSpeechError.noRecording
        }

        guard let recognizer = recognizer else {
            throw ReazonSpeechError.modelNotLoaded
        }

        isTranscribing = true
        defer {
            isTranscribing = false
            audioSamples = []
        }

        // Decode audio samples
        let result = recognizer.decode(samples: audioSamples, sampleRate: sampleRate)
        let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)

        transcribedText = text
        return text
    }

    // MARK: - Cleanup

    func cleanup() {
        cancelRecording()
        recognizer = nil
    }
}

enum ReazonSpeechError: Error, LocalizedError {
    case permissionDenied
    case notRecording
    case noRecording
    case modelNotLoaded
    case modelNotFound
    case downloadFailed
    case audioEngineError
    case transcriptionFailed(String)

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "マイクへのアクセスが拒否されました"
        case .notRecording:
            return "録音中ではありません"
        case .noRecording:
            return "録音データがありません"
        case .modelNotLoaded:
            return "モデルが読み込まれていません"
        case .modelNotFound:
            return "モデルファイルが見つかりません"
        case .downloadFailed:
            return "ダウンロードに失敗しました"
        case .audioEngineError:
            return "オーディオエンジンのエラー"
        case .transcriptionFailed(let msg):
            return "文字起こしエラー: \(msg)"
        }
    }
}
