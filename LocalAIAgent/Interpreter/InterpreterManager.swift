import Foundation
import AVFoundation
import Combine

/// Real-time interpreter: Speech → Transcription → Translation → Speech/Text output
@MainActor
final class InterpreterManager: NSObject, ObservableObject {
    static let shared = InterpreterManager()

    // MARK: - Published State

    @Published var isInterpreting = false
    @Published var isListening = false
    @Published var isTranslating = false
    @Published var isSpeaking = false

    @Published var recognizedText = ""
    @Published var translatedText = ""
    @Published var errorMessage: String?

    // MARK: - Configuration

    @Published var sourceLanguage: Language = .japanese
    @Published var targetLanguage: Language = .english
    @Published var autoSpeak = true  // Automatically speak translation

    // MARK: - Dependencies

    private var audioRecorder: AVAudioRecorder?
    private var audioPlayer: AVAudioPlayer?
    private let speechSynthesizer = AVSpeechSynthesizer()

    private var recordingURL: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("interpreter_recording.m4a")
    }

    // WhisperKit or ReazonSpeech for transcription
    private var whisperKit: Any?  // WhisperKitManager reference
    private var reazonSpeech: Any?  // ReazonSpeechManager reference

    // MARK: - Interpreter Control

    func startInterpreting() async {
        guard !isInterpreting else { return }

        // Request microphone permission
        let permission = await AVAudioApplication.requestRecordPermission()
        guard permission else {
            errorMessage = "Microphone permission required"
            return
        }

        isInterpreting = true
        errorMessage = nil

        // Start listening loop
        await listeningLoop()
    }

    func stopInterpreting() {
        isInterpreting = false
        stopRecording()
        speechSynthesizer.stopSpeaking(at: .immediate)
        isListening = false
        isTranslating = false
        isSpeaking = false
    }

    // MARK: - Listening Loop

    private func listeningLoop() async {
        while isInterpreting {
            // Listen for speech
            await listenForSpeech()

            // If we got text, translate it
            if !recognizedText.isEmpty {
                await translateSpeech()

                // Clear for next round
                try? await Task.sleep(nanoseconds: 500_000_000)  // 0.5s pause
                recognizedText = ""
            }

            // Small delay before next listening
            try? await Task.sleep(nanoseconds: 100_000_000)  // 0.1s
        }
    }

    // MARK: - Speech Recognition

    private func listenForSpeech() async {
        isListening = true
        defer { isListening = false }

        do {
            // Start recording
            try startRecording()

            // Record for a fixed duration (e.g., 5 seconds)
            try await Task.sleep(nanoseconds: 5_000_000_000)  // 5 seconds

            // Stop recording
            stopRecording()

            // Transcribe the audio
            recognizedText = try await transcribeAudio()

        } catch {
            errorMessage = "Recording error: \(error.localizedDescription)"
        }
    }

    private func startRecording() throws {
        #if !targetEnvironment(macCatalyst)
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.record, mode: .measurement)
        try audioSession.setActive(true)
        #endif

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 16000,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        audioRecorder = try AVAudioRecorder(url: recordingURL, settings: settings)
        audioRecorder?.record()
    }

    private func stopRecording() {
        audioRecorder?.stop()
        audioRecorder = nil

        #if !targetEnvironment(macCatalyst)
        let audioSession = AVAudioSession.sharedInstance()
        try? audioSession.setActive(false)
        #endif
    }

    private func transcribeAudio() async throws -> String {
        // Check if we have audio data
        guard FileManager.default.fileExists(atPath: recordingURL.path) else {
            throw InterpreterError.noAudioData
        }

        let audioData = try Data(contentsOf: recordingURL)
        guard !audioData.isEmpty else {
            throw InterpreterError.noAudioData
        }

        // Use WhisperKit if available (multilingual)
        if let whisperKit = AppState.shared.whisperKitManager {
            let result = try await whisperKit.transcribe(audioData: audioData)
            return result.text
        }

        // Fallback: Use ReazonSpeech for Japanese
        if sourceLanguage == .japanese, let reazon = AppState.shared.reazonSpeechManager {
            let result = try await reazon.transcribe(audioData: audioData)
            return result
        }

        throw InterpreterError.noTranscriptionEngine
    }

    // MARK: - Translation

    private func translateSpeech() async {
        guard !recognizedText.isEmpty else { return }

        isTranslating = true
        defer { isTranslating = false }

        do {
            // Build translation prompt
            let prompt = buildTranslationPrompt()

            // Use current backend for translation
            guard let backend = ChatModeManager.shared.currentBackend else {
                throw InterpreterError.noBackendAvailable
            }

            let message = Message(role: .user, content: prompt)
            let systemPrompt = "You are a professional interpreter. Translate accurately and naturally."

            var translation = ""
            _ = try await backend.generate(
                messages: [message],
                systemPrompt: systemPrompt,
                settings: ModelSettings.default
            ) { token in
                translation += token
            }

            translatedText = translation.trimmingCharacters(in: .whitespacesAndNewlines)

            // Speak translation if enabled
            if autoSpeak && !translatedText.isEmpty {
                await speakTranslation()
            }

        } catch {
            errorMessage = "Translation error: \(error.localizedDescription)"
        }
    }

    private func buildTranslationPrompt() -> String {
        """
        Translate the following text from \(sourceLanguage.displayName) to \(targetLanguage.displayName).
        Provide ONLY the translation, no explanations.

        Text:
        \(recognizedText)
        """
    }

    // MARK: - Text-to-Speech

    private func speakTranslation() async {
        guard !translatedText.isEmpty else { return }

        isSpeaking = true
        defer { isSpeaking = false }

        return await withCheckedContinuation { continuation in
            let utterance = AVSpeechUtterance(string: translatedText)
            utterance.voice = AVSpeechSynthesisVoice(language: targetLanguage.ttsCode)
            utterance.rate = 0.5
            utterance.pitchMultiplier = 1.0

            // Set completion handler
            let delegate = SpeechDelegate { [weak self] in
                self?.isSpeaking = false
                continuation.resume()
            }
            speechSynthesizer.delegate = delegate

            speechSynthesizer.speak(utterance)
        }
    }

    // MARK: - Manual Controls

    func manualTranslate(text: String) async {
        recognizedText = text
        await translateSpeech()
    }

    func speakText(_ text: String, language: Language) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: language.ttsCode)
        utterance.rate = 0.5
        speechSynthesizer.speak(utterance)
    }

    func swapLanguages() {
        let temp = sourceLanguage
        sourceLanguage = targetLanguage
        targetLanguage = temp
    }
}

// MARK: - Supporting Types

enum Language: String, CaseIterable, Identifiable {
    case japanese = "ja"
    case english = "en"
    case chinese = "zh"
    case korean = "ko"
    case spanish = "es"
    case french = "fr"
    case german = "de"
    case italian = "it"
    case portuguese = "pt"
    case russian = "ru"
    case arabic = "ar"
    case hindi = "hi"
    case thai = "th"
    case vietnamese = "vi"
    case indonesian = "id"
    case turkish = "tr"
    case polish = "pl"
    case dutch = "nl"
    case swedish = "sv"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .japanese: return "日本語"
        case .english: return "English"
        case .chinese: return "中文"
        case .korean: return "한국어"
        case .spanish: return "Español"
        case .french: return "Français"
        case .german: return "Deutsch"
        case .italian: return "Italiano"
        case .portuguese: return "Português"
        case .russian: return "Русский"
        case .arabic: return "العربية"
        case .hindi: return "हिन्दी"
        case .thai: return "ไทย"
        case .vietnamese: return "Tiếng Việt"
        case .indonesian: return "Bahasa Indonesia"
        case .turkish: return "Türkçe"
        case .polish: return "Polski"
        case .dutch: return "Nederlands"
        case .swedish: return "Svenska"
        }
    }

    var ttsCode: String {
        switch self {
        case .japanese: return "ja-JP"
        case .english: return "en-US"
        case .chinese: return "zh-CN"
        case .korean: return "ko-KR"
        case .spanish: return "es-ES"
        case .french: return "fr-FR"
        case .german: return "de-DE"
        case .italian: return "it-IT"
        case .portuguese: return "pt-PT"
        case .russian: return "ru-RU"
        case .arabic: return "ar-SA"
        case .hindi: return "hi-IN"
        case .thai: return "th-TH"
        case .vietnamese: return "vi-VN"
        case .indonesian: return "id-ID"
        case .turkish: return "tr-TR"
        case .polish: return "pl-PL"
        case .dutch: return "nl-NL"
        case .swedish: return "sv-SE"
        }
    }

    var flag: String {
        switch self {
        case .japanese: return "🇯🇵"
        case .english: return "🇺🇸"
        case .chinese: return "🇨🇳"
        case .korean: return "🇰🇷"
        case .spanish: return "🇪🇸"
        case .french: return "🇫🇷"
        case .german: return "🇩🇪"
        case .italian: return "🇮🇹"
        case .portuguese: return "🇵🇹"
        case .russian: return "🇷🇺"
        case .arabic: return "🇸🇦"
        case .hindi: return "🇮🇳"
        case .thai: return "🇹🇭"
        case .vietnamese: return "🇻🇳"
        case .indonesian: return "🇮🇩"
        case .turkish: return "🇹🇷"
        case .polish: return "🇵🇱"
        case .dutch: return "🇳🇱"
        case .swedish: return "🇸🇪"
        }
    }
}

enum InterpreterError: LocalizedError {
    case noAudioData
    case noTranscriptionEngine
    case noBackendAvailable

    var errorDescription: String? {
        switch self {
        case .noAudioData: return "No audio recorded"
        case .noTranscriptionEngine: return "Speech recognition not available"
        case .noBackendAvailable: return "Translation backend not ready"
        }
    }
}

// MARK: - Speech Delegate

private class SpeechDelegate: NSObject, AVSpeechSynthesizerDelegate {
    let onFinish: () -> Void

    init(onFinish: @escaping () -> Void) {
        self.onFinish = onFinish
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        onFinish()
    }
}
