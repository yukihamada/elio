import Foundation
import AVFoundation
import WhisperKit

@MainActor
final class WhisperManager: ObservableObject {
    static let shared = WhisperManager()

    @Published var isModelDownloaded = false
    @Published var isDownloading = false
    @Published var downloadProgress: Double = 0
    @Published var isRecording = false
    @Published var isTranscribing = false
    @Published var transcribedText = ""
    @Published var errorMessage: String?

    private var whisperKit: WhisperKit?
    private var audioRecorder: AVAudioRecorder?
    private var recordingURL: URL?

    // Use small model for balance between speed and accuracy
    private let modelName = "openai_whisper-small"

    private var modelsDirectory: URL {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documentsPath.appendingPathComponent("WhisperModels")
    }

    private init() {
        checkModelStatus()
    }

    private func checkModelStatus() {
        // WhisperKit stores models in subdirectory with .mlmodelc files
        let modelPath = modelsDirectory.appendingPathComponent(modelName)

        // Check if directory exists and contains model files
        if FileManager.default.fileExists(atPath: modelPath.path) {
            do {
                let contents = try FileManager.default.contentsOfDirectory(atPath: modelPath.path)
                // Check for essential WhisperKit model files (.mlmodelc directories)
                let hasModelFiles = contents.contains { $0.hasSuffix(".mlmodelc") || $0.hasSuffix(".mlpackage") }
                isModelDownloaded = hasModelFiles

                // Also save to UserDefaults as backup check
                if hasModelFiles {
                    UserDefaults.standard.set(true, forKey: "whisper_model_downloaded")
                }
            } catch {
                isModelDownloaded = false
            }
        } else {
            // Fallback: check UserDefaults (in case file check fails but model was downloaded)
            isModelDownloaded = UserDefaults.standard.bool(forKey: "whisper_model_downloaded")
        }
    }

    // MARK: - Model Management

    func downloadModelIfNeeded() async throws {
        // Re-check model status before downloading
        checkModelStatus()

        guard !isModelDownloaded else {
            try await loadModel()
            return
        }

        isDownloading = true
        downloadProgress = 0
        errorMessage = nil

        do {
            // Create models directory if needed
            try FileManager.default.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)

            // Download and initialize WhisperKit
            whisperKit = try await WhisperKit(
                model: modelName,
                downloadBase: modelsDirectory,
                verbose: false,
                prewarm: true
            )

            isModelDownloaded = true
            isDownloading = false
            downloadProgress = 1.0

            // Save download status to UserDefaults
            UserDefaults.standard.set(true, forKey: "whisper_model_downloaded")
        } catch {
            isDownloading = false
            errorMessage = String(localized: "whisper.download.error") + ": \(error.localizedDescription)"
            throw error
        }
    }

    private func loadModel() async throws {
        guard whisperKit == nil else { return }

        do {
            // Load from local storage - WhisperKit will find the existing model
            whisperKit = try await WhisperKit(
                model: modelName,
                downloadBase: modelsDirectory,
                verbose: false,
                prewarm: true
            )

            // Ensure status is correct after successful load
            isModelDownloaded = true
            UserDefaults.standard.set(true, forKey: "whisper_model_downloaded")
        } catch {
            // If loading fails, model might be corrupted - reset status
            isModelDownloaded = false
            UserDefaults.standard.set(false, forKey: "whisper_model_downloaded")
            errorMessage = String(localized: "whisper.load.error") + ": \(error.localizedDescription)"
            throw error
        }
    }

    // MARK: - Recording

    func startRecording() async throws {
        guard !isRecording else { return }

        // Ensure model is loaded
        if whisperKit == nil {
            try await loadModel()
        }

        // Request microphone permission
        let permission = await AVAudioApplication.requestRecordPermission()
        guard permission else {
            errorMessage = String(localized: "whisper.permission.denied")
            throw WhisperError.permissionDenied
        }

        // Setup audio session
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
        try session.setActive(true)

        // Create recording URL
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        recordingURL = documentsPath.appendingPathComponent("whisper_recording.wav")

        // Audio settings for Whisper (16kHz mono)
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 16000,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false
        ]

        audioRecorder = try AVAudioRecorder(url: recordingURL!, settings: settings)
        audioRecorder?.record()
        isRecording = true
        transcribedText = ""
    }

    func stopRecording() async throws -> String {
        guard isRecording, let recorder = audioRecorder else {
            throw WhisperError.notRecording
        }

        recorder.stop()
        isRecording = false

        // Transcribe the recording
        return try await transcribe()
    }

    func cancelRecording() {
        audioRecorder?.stop()
        audioRecorder = nil
        isRecording = false

        // Delete recording file
        if let url = recordingURL {
            try? FileManager.default.removeItem(at: url)
        }
        recordingURL = nil
    }

    // MARK: - Transcription

    private func transcribe() async throws -> String {
        guard let url = recordingURL else {
            throw WhisperError.noRecording
        }

        guard let whisper = whisperKit else {
            throw WhisperError.modelNotLoaded
        }

        isTranscribing = true
        defer { isTranscribing = false }

        do {
            // Japanese transcription settings - optimized for accuracy
            let results = try await whisper.transcribe(audioPath: url.path, decodeOptions: DecodingOptions(
                task: .transcribe,
                language: "ja",
                temperature: 0.0,
                temperatureFallbackCount: 3,
                sampleLength: 224,
                usePrefillPrompt: true,
                usePrefillCache: true,
                skipSpecialTokens: true,
                withoutTimestamps: true,
                suppressBlank: true
            ))

            let text = results.map { $0.text }.joined(separator: " ").trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            transcribedText = text

            // Clean up recording file
            try? FileManager.default.removeItem(at: url)
            recordingURL = nil

            return text
        } catch {
            errorMessage = String(localized: "whisper.transcribe.error") + ": \(error.localizedDescription)"
            throw error
        }
    }

    // MARK: - Cleanup

    func cleanup() {
        cancelRecording()
        whisperKit = nil
    }
}

enum WhisperError: Error, LocalizedError {
    case permissionDenied
    case notRecording
    case noRecording
    case modelNotLoaded
    case transcriptionFailed(String)

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return String(localized: "whisper.error.permission")
        case .notRecording:
            return String(localized: "whisper.error.not.recording")
        case .noRecording:
            return String(localized: "whisper.error.no.recording")
        case .modelNotLoaded:
            return String(localized: "whisper.error.model.not.loaded")
        case .transcriptionFailed(let msg):
            return String(localized: "whisper.error.transcription") + ": \(msg)"
        }
    }
}
