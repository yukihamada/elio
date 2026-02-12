#if !targetEnvironment(macCatalyst)
import Foundation
import AVFoundation

/// Kokoro TTS Manager using Sherpa-ONNX for high-quality neural text-to-speech
@MainActor
final class KokoroTTSManager: NSObject, ObservableObject {
    static let shared = KokoroTTSManager()

    // MARK: - Published Properties

    @Published var isModelDownloaded = false
    @Published var isDownloading = false
    @Published var downloadProgress: Double = 0
    @Published var isSpeaking = false
    @Published var currentMessageId: UUID?
    @Published var errorMessage: String?

    // MARK: - Private Properties

    private var tts: SherpaOnnxOfflineTtsWrapper?
    private var audioPlayer: AVAudioPlayer?

    // Kokoro TTS model hosted on Hugging Face (sherpa-onnx models)
    // Using kokoro multi-language INT8 model with Japanese, English, Chinese support
    private let modelName = "kokoro-int8-multi-lang"
    private let hfBaseURL = "https://huggingface.co/csukuangfj/kokoro-int8-multi-lang-v1_0/resolve/main"

    // Model files needed for Kokoro TTS (INT8 quantized model - smaller and faster)
    private let modelFiles: [(filename: String, url: String)] = [
        ("model.onnx", "model.int8.onnx"),  // INT8 quantized model (109MB)
        ("voices.bin", "voices.bin"),        // Voice embeddings (26.4MB)
        ("tokens.txt", "tokens.txt")         // Token vocabulary
    ]

    // espeak-ng data files for phonemization (essential for Japanese)
    private let espeakDataFiles = [
        "espeak-ng-data/ja_dict",
        "espeak-ng-data/ja_rules",
        "espeak-ng-data/phontab",
        "espeak-ng-data/phonindex",
        "espeak-ng-data/phondata",
        "espeak-ng-data/intonations"
    ]

    private var modelsDirectory: URL {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documentsPath.appendingPathComponent("KokoroTTSModels")
    }

    private var modelPath: URL {
        modelsDirectory.appendingPathComponent(modelName)
    }

    private var espeakDataPath: URL {
        modelPath.appendingPathComponent("espeak-ng-data")
    }

    // MARK: - Language Detection

    /// Detect app language and return appropriate TTS language code
    private static func detectTTSLanguage() -> String {
        // Check app's preferred localization
        let preferredLang = Bundle.main.preferredLocalizations.first ?? "en"

        switch preferredLang {
        case "ja":
            return "ja"      // Japanese
        case "zh-Hans", "zh-Hant", "zh":
            return "cmn"     // Chinese (Mandarin)
        case "fr":
            return "fr-fr"   // French
        case "de":
            return "de"      // German
        case "es":
            return "es"      // Spanish
        case "it":
            return "it"      // Italian
        case "pt":
            return "pt"      // Portuguese
        case "ko":
            return "ko"      // Korean
        default:
            return "en-us"   // Default to American English
        }
    }

    /// Get default speaker ID based on app language
    /// Speaker IDs: 0-10=American, 11-19=American Male, 20-23=British Female, 24-27=British Male,
    ///              37-40=Japanese Female, 41=Japanese Male, 45-52=Chinese
    static var defaultSpeakerId: Int {
        let preferredLang = Bundle.main.preferredLocalizations.first ?? "en"

        switch preferredLang {
        case "ja":
            return 37    // jf_alpha - Japanese female
        case "zh-Hans", "zh-Hant", "zh":
            return 45    // zf_xiaobei - Chinese female
        default:
            return 0     // af_alloy - American English female
        }
    }

    // MARK: - Initialization

    private override init() {
        super.init()
        checkModelStatus()
        setupAudioSession()
    }

    private func setupAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("[KokoroTTS] Audio session setup error: \(error)")
        }
    }

    private func checkModelStatus() {
        let mainFilesExist = modelFiles.allSatisfy { file in
            let filePath = modelPath.appendingPathComponent(file.filename)
            return FileManager.default.fileExists(atPath: filePath.path)
        }

        // Check essential espeak-ng-data files (not just directory existence)
        let essentialEspeakFiles = [
            "phontab",
            "phonindex",
            "phondata",
            "voices/ja",
            "voices/en-us"
        ]
        let espeakFilesExist = essentialEspeakFiles.allSatisfy { file in
            let filePath = espeakDataPath.appendingPathComponent(file)
            return FileManager.default.fileExists(atPath: filePath.path)
        }

        if mainFilesExist && espeakFilesExist {
            isModelDownloaded = true
            UserDefaults.standard.set(true, forKey: "kokoro_tts_model_downloaded")
            print("[KokoroTTS] Model status: All files present")
        } else {
            isModelDownloaded = false
            UserDefaults.standard.set(false, forKey: "kokoro_tts_model_downloaded")
            if !mainFilesExist {
                print("[KokoroTTS] Model status: Main model files missing")
            }
            if !espeakFilesExist {
                print("[KokoroTTS] Model status: eSpeak-ng data files incomplete")
            }
        }
    }

    // MARK: - Model Management

    func downloadModelIfNeeded() async throws {
        print("[KokoroTTS] downloadModelIfNeeded called")
        checkModelStatus()

        guard !isModelDownloaded else {
            print("[KokoroTTS] Model already downloaded, loading...")
            try await loadModel()
            return
        }

        print("[KokoroTTS] Starting download")
        isDownloading = true
        downloadProgress = 0
        errorMessage = nil

        do {
            try FileManager.default.createDirectory(at: modelPath, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: espeakDataPath, withIntermediateDirectories: true)

            // Download main model files
            let totalFiles = modelFiles.count + 1 // +1 for espeak-ng-data archive
            for (index, file) in modelFiles.enumerated() {
                let fileURL = URL(string: "\(hfBaseURL)/\(file.url)")!
                let destinationURL = modelPath.appendingPathComponent(file.filename)

                print("[KokoroTTS] Downloading file \(index + 1)/\(totalFiles): \(file.filename)")

                if FileManager.default.fileExists(atPath: destinationURL.path) {
                    print("[KokoroTTS] File already exists, skipping")
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
                print("[KokoroTTS] File downloaded: \(file.filename)")
            }

            // Download espeak-ng-data (bundled or from separate source)
            print("[KokoroTTS] Downloading espeak-ng data...")
            try await downloadEspeakData()

            isModelDownloaded = true
            downloadProgress = 1.0
            UserDefaults.standard.set(true, forKey: "kokoro_tts_model_downloaded")
            print("[KokoroTTS] All files downloaded, loading model...")

            try await loadModel()

            isDownloading = false
            print("[KokoroTTS] Download complete")
        } catch {
            isDownloading = false
            errorMessage = "TTSモデルのダウンロードに失敗しました: \(error.localizedDescription)"
            print("[KokoroTTS] Download error: \(error)")
            throw error
        }
    }

    private func downloadEspeakData() async throws {
        // Check if essential files already downloaded (including voice files)
        let phontabExists = FileManager.default.fileExists(atPath: espeakDataPath.appendingPathComponent("phontab").path)
        let jaVoiceExists = FileManager.default.fileExists(atPath: espeakDataPath.appendingPathComponent("voices/ja").path)
        let enVoiceExists = FileManager.default.fileExists(atPath: espeakDataPath.appendingPathComponent("voices/en-us").path)

        if phontabExists && jaVoiceExists && enVoiceExists {
            print("[KokoroTTS] espeak-ng data already exists (with voice files)")
            return
        }

        print("[KokoroTTS] espeak-ng data incomplete, downloading...")
        // On iOS, download individual files (can't use tar on iOS)
        try await downloadEspeakDataFiles()
    }

    private func downloadEspeakDataFiles() async throws {
        // Download essential espeak-ng data files from the kokoro model repository
        let espeakBaseURL = "https://huggingface.co/csukuangfj/kokoro-int8-multi-lang-v1_0/resolve/main/espeak-ng-data"

        // Essential phoneme data files
        let essentialFiles = [
            "phontab",
            "phonindex",
            "phondata",
            "phondata-manifest",
            "intonations"
        ]

        // Language dictionaries
        let dictFiles = [
            "ja_dict",    // Japanese dictionary
            "en_dict",    // English dictionary
            "cmn_dict",   // Chinese (Mandarin) dictionary
            "fr_dict",    // French dictionary
            "de_dict"     // German dictionary
        ]

        // Voice files (required for proper TTS)
        let voiceFiles = [
            "voices/!v/Alex",
            "voices/!v/Andy",
            "voices/!v/Annie",
            "voices/!v/Boris",
            "voices/!v/Denis",
            "voices/!v/Diogo",
            "voices/!v/Ed",
            "voices/!v/Gene",
            "voices/!v/Gene2",
            "voices/!v/Henrique",
            "voices/!v/Hugo",
            "voices/!v/Iven",
            "voices/!v/Iven2",
            "voices/!v/Iven3",
            "voices/!v/Iven4",
            "voices/!v/John",
            "voices/!v/Linda",
            "voices/!v/Marco",
            "voices/!v/Mario",
            "voices/!v/Michael",
            "voices/!v/Mike",
            "voices/!v/Miguel",
            "voices/!v/Mr_serious",
            "voices/!v/Nguyen",
            "voices/!v/Pablo",
            "voices/!v/Paul",
            "voices/!v/Pedro",
            "voices/!v/Reed",
            "voices/!v/Rich",
            "voices/!v/RicishayMax",
            "voices/!v/RicishayMax2",
            "voices/!v/RicishayMax3",
            "voices/!v/Rob",
            "voices/!v/Robert",
            "voices/!v/Robosoft",
            "voices/!v/Robosoft2",
            "voices/!v/Robosoft3",
            "voices/!v/Robosoft4",
            "voices/!v/Robosoft5",
            "voices/!v/Robosoft6",
            "voices/!v/Robosoft7",
            "voices/!v/Robosoft8",
            "voices/!v/Steph",
            "voices/!v/Steph2",
            "voices/!v/Steph3",
            "voices/!v/Storm",
            "voices/!v/Travis",
            "voices/!v/Victor",
            "voices/!v/Zac"
        ]

        // Language voice files
        let langVoiceFiles = [
            "voices/en",
            "voices/en-gb",
            "voices/en-gb-scotland",
            "voices/en-gb-x-rp",
            "voices/en-us",
            "voices/ja",
            "voices/cmn",
            "voices/fr",
            "voices/de"
        ]

        // Create voices directory (voicesVDir includes parent voices/ directory)
        let voicesVDir = espeakDataPath.appendingPathComponent("voices/!v")
        try FileManager.default.createDirectory(at: voicesVDir, withIntermediateDirectories: true)

        // Download essential phoneme files (these are required for TTS to work)
        for file in essentialFiles {
            let fileURL = URL(string: "\(espeakBaseURL)/\(file)")!
            let destination = espeakDataPath.appendingPathComponent(file)
            if !FileManager.default.fileExists(atPath: destination.path) {
                do {
                    try await downloadFile(from: fileURL, to: destination) { _ in }
                    print("[KokoroTTS] Downloaded: \(file)")
                } catch {
                    // Essential files are required - fail if we can't download them
                    print("[KokoroTTS] ERROR: Failed to download essential file \(file): \(error)")
                    throw KokoroTTSError.downloadFailed
                }
            }
        }

        // Download dictionary files
        for file in dictFiles {
            let fileURL = URL(string: "\(espeakBaseURL)/\(file)")!
            let destination = espeakDataPath.appendingPathComponent(file)
            if !FileManager.default.fileExists(atPath: destination.path) {
                do {
                    try await downloadFile(from: fileURL, to: destination) { _ in }
                    print("[KokoroTTS] Downloaded: \(file)")
                } catch {
                    print("[KokoroTTS] Warning: Could not download \(file): \(error)")
                }
            }
        }

        // Download language voice files (ESSENTIAL for TTS - required for voice synthesis)
        // These are critical - without them Kokoro TTS will fail and fall back to system TTS
        let essentialVoiceFiles = ["voices/ja", "voices/en-us", "voices/en"]
        for file in essentialVoiceFiles {
            let fileURL = URL(string: "\(espeakBaseURL)/\(file)")!
            let destination = espeakDataPath.appendingPathComponent(file)

            // Create parent directory if needed
            let parentDir = destination.deletingLastPathComponent()
            if !FileManager.default.fileExists(atPath: parentDir.path) {
                try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)
            }

            if !FileManager.default.fileExists(atPath: destination.path) {
                do {
                    try await downloadFile(from: fileURL, to: destination) { _ in }
                    print("[KokoroTTS] Downloaded essential voice: \(file)")
                } catch {
                    // Essential voice files are required - fail if we can't download them
                    print("[KokoroTTS] ERROR: Failed to download essential voice file \(file): \(error)")
                    throw KokoroTTSError.downloadFailed
                }
            }
        }

        // Download other language voice files (optional - only log warning if fail)
        let optionalVoiceFiles = langVoiceFiles.filter { !essentialVoiceFiles.contains($0) }
        for file in optionalVoiceFiles {
            let fileURL = URL(string: "\(espeakBaseURL)/\(file)")!
            let destination = espeakDataPath.appendingPathComponent(file)

            // Create parent directory if needed
            let parentDir = destination.deletingLastPathComponent()
            if !FileManager.default.fileExists(atPath: parentDir.path) {
                try? FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)
            }

            if !FileManager.default.fileExists(atPath: destination.path) {
                do {
                    try await downloadFile(from: fileURL, to: destination) { _ in }
                    print("[KokoroTTS] Downloaded: \(file)")
                } catch {
                    print("[KokoroTTS] Warning: Could not download \(file): \(error)")
                }
            }
        }

        // Download a subset of voice variant files
        for file in voiceFiles.prefix(10) {  // Download first 10 voice variants
            let fileURL = URL(string: "\(espeakBaseURL)/\(file)")!
            let destination = espeakDataPath.appendingPathComponent(file)
            if !FileManager.default.fileExists(atPath: destination.path) {
                do {
                    try await downloadFile(from: fileURL, to: destination) { _ in }
                    print("[KokoroTTS] Downloaded: \(file)")
                } catch {
                    print("[KokoroTTS] Warning: Could not download \(file): \(error)")
                }
            }
        }

        print("[KokoroTTS] espeak-ng data download complete")
    }

    private func downloadFile(from url: URL, to destination: URL, progressHandler: @escaping (Double) -> Void) async throws {
        print("[KokoroTTS] Downloading: \(url)")

        // Use URLSession with delegate for progress tracking
        var request = URLRequest(url: url)
        request.timeoutInterval = 600 // 10 minutes timeout for large files

        let (asyncBytes, response) = try await URLSession.shared.bytes(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            print("[KokoroTTS] Bad HTTP response: \((response as? HTTPURLResponse)?.statusCode ?? -1)")
            throw KokoroTTSError.downloadFailed
        }

        let expectedLength = httpResponse.expectedContentLength
        print("[KokoroTTS] Expected file size: \(expectedLength) bytes (\(String(format: "%.1f", Double(expectedLength) / 1_000_000)) MB)")

        // Create temporary file
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        FileManager.default.createFile(atPath: tempURL.path, contents: nil)
        let fileHandle = try FileHandle(forWritingTo: tempURL)

        var downloadedBytes: Int64 = 0
        var lastProgressUpdate = Date()
        let progressUpdateInterval: TimeInterval = 0.3 // Update every 0.3 seconds
        let bufferSize = 65536 // 64KB buffer for better performance
        var buffer = Data()
        buffer.reserveCapacity(bufferSize)

        do {
            for try await byte in asyncBytes {
                buffer.append(byte)
                downloadedBytes += 1

                // Write buffer when full
                if buffer.count >= bufferSize {
                    try fileHandle.write(contentsOf: buffer)
                    buffer.removeAll(keepingCapacity: true)
                }

                // Update progress periodically
                let now = Date()
                if now.timeIntervalSince(lastProgressUpdate) >= progressUpdateInterval {
                    lastProgressUpdate = now
                    if expectedLength > 0 {
                        let progress = Double(downloadedBytes) / Double(expectedLength)
                        let mbDownloaded = Double(downloadedBytes) / 1_000_000
                        let mbTotal = Double(expectedLength) / 1_000_000
                        print("[KokoroTTS] Download progress: \(Int(progress * 100))% (\(String(format: "%.1f", mbDownloaded))MB / \(String(format: "%.1f", mbTotal))MB)")
                        await MainActor.run {
                            progressHandler(progress)
                        }
                    }
                }
            }

            // Write remaining buffer
            if !buffer.isEmpty {
                try fileHandle.write(contentsOf: buffer)
            }
            try fileHandle.close()
        } catch {
            try? fileHandle.close()
            try? FileManager.default.removeItem(at: tempURL)
            throw error
        }

        await MainActor.run {
            progressHandler(1.0)
        }
        print("[KokoroTTS] Download complete: \(downloadedBytes) bytes")

        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: tempURL, to: destination)
        print("[KokoroTTS] File saved to: \(destination.path)")
    }

    private func loadModel() async throws {
        guard tts == nil else { return }

        let modelFilePath = modelPath.appendingPathComponent("model.onnx")
        let voicesPath = modelPath.appendingPathComponent("voices.bin")
        let tokensPath = modelPath.appendingPathComponent("tokens.txt")

        // Check main model files
        var missingFiles: [String] = []
        if !FileManager.default.fileExists(atPath: modelFilePath.path) {
            missingFiles.append("model.onnx")
        }
        if !FileManager.default.fileExists(atPath: voicesPath.path) {
            missingFiles.append("voices.bin")
        }
        if !FileManager.default.fileExists(atPath: tokensPath.path) {
            missingFiles.append("tokens.txt")
        }

        // Check essential espeak-ng-data files
        let essentialEspeakFiles = ["phontab", "phonindex", "phondata"]
        for file in essentialEspeakFiles {
            let filePath = espeakDataPath.appendingPathComponent(file)
            if !FileManager.default.fileExists(atPath: filePath.path) {
                missingFiles.append("espeak-ng-data/\(file)")
            }
        }

        if !missingFiles.isEmpty {
            print("[KokoroTTS] ERROR: Missing required files: \(missingFiles.joined(separator: ", "))")
            isModelDownloaded = false
            UserDefaults.standard.set(false, forKey: "kokoro_tts_model_downloaded")
            throw KokoroTTSError.modelNotFound
        }

        print("[KokoroTTS] Loading model...")
        print("[KokoroTTS] Model: \(modelFilePath.path)")
        print("[KokoroTTS] Voices: \(voicesPath.path)")
        print("[KokoroTTS] Tokens: \(tokensPath.path)")
        print("[KokoroTTS] Data dir: \(espeakDataPath.path)")

        // Verify espeak-ng-data files exist (CRITICAL - missing files cause C++ crash)
        let espeakFiles = ["phontab", "phonindex", "phondata", "intonations"]
        var missingEspeakFiles: [String] = []
        for file in espeakFiles {
            let filePath = espeakDataPath.appendingPathComponent(file)
            let exists = FileManager.default.fileExists(atPath: filePath.path)
            print("[KokoroTTS] espeak-ng-data/\(file): \(exists ? "OK" : "MISSING")")
            if !exists {
                missingEspeakFiles.append(file)
            }
        }

        // Check voice files (CRITICAL - missing voice files cause crash)
        let jaVoicePath = espeakDataPath.appendingPathComponent("voices/ja")
        let enVoicePath = espeakDataPath.appendingPathComponent("voices/en-us")
        let jaExists = FileManager.default.fileExists(atPath: jaVoicePath.path)
        let enExists = FileManager.default.fileExists(atPath: enVoicePath.path)
        print("[KokoroTTS] voices/ja: \(jaExists ? "OK" : "MISSING")")
        print("[KokoroTTS] voices/en-us: \(enExists ? "OK" : "MISSING")")

        // Fail early if essential espeak-ng files are missing (prevents C++ crash)
        if !missingEspeakFiles.isEmpty || !jaExists || !enExists {
            print("[KokoroTTS] ERROR: Essential espeak-ng files missing - cannot initialize TTS")
            print("[KokoroTTS] Missing espeak files: \(missingEspeakFiles)")
            print("[KokoroTTS] Please reset TTS model from Settings to re-download")
            isModelDownloaded = false
            UserDefaults.standard.set(false, forKey: "kokoro_tts_model_downloaded")
            throw KokoroTTSError.modelNotFound
        }

        // Configure Kokoro TTS
        // For Kokoro v1.0+ multi-lingual model, lang parameter is required
        // Detect app language and set appropriate TTS language
        let ttsLang = Self.detectTTSLanguage()
        print("[KokoroTTS] Using language: \(ttsLang)")

        let kokoroConfig = sherpaOnnxOfflineTtsKokoroModelConfig(
            model: modelFilePath.path,
            voices: voicesPath.path,
            tokens: tokensPath.path,
            dataDir: espeakDataPath.path,
            lengthScale: 1.0,
            dictDir: "",
            lexicon: "",
            lang: ttsLang
        )

        let modelConfig = sherpaOnnxOfflineTtsModelConfig(
            kokoro: kokoroConfig,
            numThreads: 2,
            debug: 1,
            provider: "cpu"
        )

        var config = sherpaOnnxOfflineTtsConfig(
            model: modelConfig,
            maxNumSentences: 1
        )

        let wrapper = SherpaOnnxOfflineTtsWrapper(config: &config)

        // Check if TTS was initialized successfully
        guard wrapper.isValid else {
            print("[KokoroTTS] ERROR: Failed to initialize TTS wrapper - SherpaOnnxCreateOfflineTts returned nil")
            print("[KokoroTTS] This usually means:")
            print("[KokoroTTS]   1. Model file is corrupted or incomplete")
            print("[KokoroTTS]   2. espeak-ng-data files are missing")
            print("[KokoroTTS]   3. Model file format is incompatible")

            // Reset download state so user can re-download
            isModelDownloaded = false
            UserDefaults.standard.set(false, forKey: "kokoro_tts_model_downloaded")
            throw KokoroTTSError.synthesisError
        }

        tts = wrapper
        print("[KokoroTTS] Model loaded successfully")
    }

    // MARK: - Speech Synthesis

    /// Speak text using Kokoro TTS
    /// - Parameters:
    ///   - text: Text to speak
    ///   - messageId: Optional message ID for tracking
    ///   - speakerId: Speaker ID (nil = auto-detect based on language)
    ///   - speed: Speech speed (1.0 = normal)
    func speak(_ text: String, messageId: UUID? = nil, speakerId: Int? = nil, speed: Float = 1.0) async {
        // Skip TTS in test mode (no model available)
        if ProcessInfo.processInfo.arguments.contains("-SkipDownload") {
            print("[KokoroTTS] Skipping TTS in test mode")
            return
        }

        // Use language-appropriate default speaker if not specified
        let effectiveSpeakerId = speakerId ?? Self.defaultSpeakerId
        // Stop any current speech first, then continue with new speech
        if isSpeaking {
            stop()
            // Small delay to ensure audio session is properly reset
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        }

        isSpeaking = true
        currentMessageId = messageId

        // Clean text for TTS
        var cleanedText = cleanTextForTTS(text)

        // Convert Japanese kanji to hiragana to avoid Kokoro's Chinese detection bug
        if containsKanji(cleanedText) {
            print("[KokoroTTS] Converting kanji to hiragana...")
            cleanedText = convertKanjiToHiragana(cleanedText)
            print("[KokoroTTS] Converted: \(cleanedText.prefix(50))...")
        }

        // Ensure model is loaded
        guard let tts = tts else {
            print("[KokoroTTS] Model not loaded, attempting to load...")
            do {
                try await downloadModelIfNeeded()
            } catch {
                print("[KokoroTTS] Failed to load model: \(error)")
                errorMessage = "TTSモデルの読み込みに失敗しました"
                isSpeaking = false
                currentMessageId = nil
                return
            }

            guard self.tts != nil else {
                errorMessage = "TTSモデルが利用できません"
                isSpeaking = false
                currentMessageId = nil
                return
            }

            // Retry speak after loading
            await speak(text, messageId: messageId, speakerId: effectiveSpeakerId, speed: speed)
            return
        }

        print("[KokoroTTS] Generating speech for: \(cleanedText.prefix(100))... (speaker: \(effectiveSpeakerId), speed: \(speed))")

        // Generate audio with Kokoro
        let audio = tts.generate(text: cleanedText, sid: effectiveSpeakerId, speed: speed)

        guard audio.n > 0 else {
            print("[KokoroTTS] ERROR: No audio generated for text: \(cleanedText.prefix(50))")
            print("[KokoroTTS] This may be caused by:")
            print("[KokoroTTS]   - Empty or invalid text after cleaning")
            print("[KokoroTTS]   - Model not properly loaded")
            print("[KokoroTTS]   - Unsupported characters in text")
            errorMessage = "音声生成に失敗しました"
            isSpeaking = false
            currentMessageId = nil
            return
        }

        print("[KokoroTTS] Generated \(audio.n) samples at \(audio.sampleRate) Hz (duration: \(Float(audio.n) / Float(audio.sampleRate))s)")

        // Convert to WAV and play
        await playAudio(samples: audio.samples, sampleRate: Int(audio.sampleRate))
    }

    /// Check if text contains kanji (CJK characters that cause issues)
    private func containsKanji(_ text: String) -> Bool {
        for scalar in text.unicodeScalars {
            // CJK Unified Ideographs (Kanji): U+4E00 - U+9FFF
            if scalar.value >= 0x4E00 && scalar.value <= 0x9FFF {
                return true
            }
        }
        return false
    }

    /// Convert Japanese text with kanji to hiragana using iOS text analysis
    private func convertKanjiToHiragana(_ text: String) -> String {
        // Use CFStringTokenizer to get readings for Japanese text
        let inputText = text as CFString
        let range = CFRangeMake(0, CFStringGetLength(inputText))

        guard let tokenizer = CFStringTokenizerCreate(
            kCFAllocatorDefault,
            inputText,
            range,
            kCFStringTokenizerUnitWord,
            CFLocaleCopyCurrent()
        ) else {
            return text
        }

        var result = ""
        var currentIndex = 0

        var tokenType = CFStringTokenizerGoToTokenAtIndex(tokenizer, 0)
        while tokenType != [] {
            let tokenRange = CFStringTokenizerGetCurrentTokenRange(tokenizer)

            // Add any text before this token (spaces, punctuation, etc.)
            if tokenRange.location > currentIndex {
                let preRange = CFRange(location: currentIndex, length: tokenRange.location - currentIndex)
                if let preString = CFStringCreateWithSubstring(kCFAllocatorDefault, inputText, preRange) {
                    result += preString as String
                }
            }

            // Get the token text
            let tokenString: String
            if let substring = CFStringCreateWithSubstring(kCFAllocatorDefault, inputText, tokenRange) {
                tokenString = substring as String
            } else {
                tokenString = ""
            }

            // Check if this token contains kanji
            if containsKanji(tokenString) {
                // Try to get Latin transcription (romaji) first, then convert to hiragana
                if let latin = CFStringTokenizerCopyCurrentTokenAttribute(tokenizer, kCFStringTokenizerAttributeLatinTranscription) as? String {
                    // Convert romaji to hiragana
                    let hiragana = romajiToHiragana(latin)
                    result += hiragana
                } else {
                    // No reading available, keep original
                    result += tokenString
                }
            } else {
                // No kanji, keep original
                result += tokenString
            }

            currentIndex = tokenRange.location + tokenRange.length
            tokenType = CFStringTokenizerAdvanceToNextToken(tokenizer)
        }

        // Add any remaining text after the last token
        let textLength = CFStringGetLength(inputText)
        if currentIndex < textLength {
            let remainingRange = CFRange(location: currentIndex, length: textLength - currentIndex)
            if let remainingString = CFStringCreateWithSubstring(kCFAllocatorDefault, inputText, remainingRange) {
                result += remainingString as String
            }
        }

        return result
    }

    /// Convert romaji to hiragana
    private func romajiToHiragana(_ romaji: String) -> String {
        let mapping: [String: String] = [
            // Basic vowels
            "a": "あ", "i": "い", "u": "う", "e": "え", "o": "お",
            // K row
            "ka": "か", "ki": "き", "ku": "く", "ke": "け", "ko": "こ",
            "kya": "きゃ", "kyu": "きゅ", "kyo": "きょ",
            // S row
            "sa": "さ", "si": "し", "shi": "し", "su": "す", "se": "せ", "so": "そ",
            "sha": "しゃ", "shu": "しゅ", "sho": "しょ",
            "sya": "しゃ", "syu": "しゅ", "syo": "しょ",
            // T row
            "ta": "た", "ti": "ち", "chi": "ち", "tu": "つ", "tsu": "つ", "te": "て", "to": "と",
            "cha": "ちゃ", "chu": "ちゅ", "cho": "ちょ",
            "tya": "ちゃ", "tyu": "ちゅ", "tyo": "ちょ",
            // N row
            "na": "な", "ni": "に", "nu": "ぬ", "ne": "ね", "no": "の",
            "nya": "にゃ", "nyu": "にゅ", "nyo": "にょ",
            "n": "ん", "nn": "ん",
            // H row
            "ha": "は", "hi": "ひ", "hu": "ふ", "fu": "ふ", "he": "へ", "ho": "ほ",
            "hya": "ひゃ", "hyu": "ひゅ", "hyo": "ひょ",
            // M row
            "ma": "ま", "mi": "み", "mu": "む", "me": "め", "mo": "も",
            "mya": "みゃ", "myu": "みゅ", "myo": "みょ",
            // Y row
            "ya": "や", "yu": "ゆ", "yo": "よ",
            // R row
            "ra": "ら", "ri": "り", "ru": "る", "re": "れ", "ro": "ろ",
            "rya": "りゃ", "ryu": "りゅ", "ryo": "りょ",
            // W row
            "wa": "わ", "wo": "を",
            // G row (voiced)
            "ga": "が", "gi": "ぎ", "gu": "ぐ", "ge": "げ", "go": "ご",
            "gya": "ぎゃ", "gyu": "ぎゅ", "gyo": "ぎょ",
            // Z row (voiced)
            "za": "ざ", "zi": "じ", "ji": "じ", "zu": "ず", "ze": "ぜ", "zo": "ぞ",
            "ja": "じゃ", "ju": "じゅ", "jo": "じょ",
            "zya": "じゃ", "zyu": "じゅ", "zyo": "じょ",
            // D row (voiced)
            "da": "だ", "di": "ぢ", "du": "づ", "de": "で", "do": "ど",
            // B row (voiced)
            "ba": "ば", "bi": "び", "bu": "ぶ", "be": "べ", "bo": "ぼ",
            "bya": "びゃ", "byu": "びゅ", "byo": "びょ",
            // P row (half-voiced)
            "pa": "ぱ", "pi": "ぴ", "pu": "ぷ", "pe": "ぺ", "po": "ぽ",
            "pya": "ぴゃ", "pyu": "ぴゅ", "pyo": "ぴょ",
            // Special
            "xtu": "っ", "xtsu": "っ", "ltu": "っ", "ltsu": "っ",
            "-": "ー"
        ]

        var result = ""
        var input = romaji.lowercased()

        while !input.isEmpty {
            var found = false

            // Try longer patterns first (3 chars, then 2, then 1)
            for length in stride(from: min(4, input.count), through: 1, by: -1) {
                let prefix = String(input.prefix(length))
                if let hiragana = mapping[prefix] {
                    result += hiragana
                    input.removeFirst(length)
                    found = true
                    break
                }
            }

            if !found {
                // Handle double consonants (っ)
                let first = input.first!
                if "kstcnhfmyrwgzjdbp".contains(first) && input.count > 1 {
                    let second = input[input.index(input.startIndex, offsetBy: 1)]
                    if first == second {
                        result += "っ"
                        input.removeFirst()
                        found = true
                        continue
                    }
                }

                // Keep unknown character as-is
                result += String(input.removeFirst())
            }
        }

        return result
    }

    private func cleanTextForTTS(_ text: String) -> String {
        // Remove markdown, code blocks, and other non-speech elements
        var cleaned = text

        // Remove code blocks
        cleaned = cleaned.replacingOccurrences(of: "```[^`]*```", with: "", options: .regularExpression)

        // Remove inline code
        cleaned = cleaned.replacingOccurrences(of: "`[^`]+`", with: "", options: .regularExpression)

        // Remove markdown links, keep text
        cleaned = cleaned.replacingOccurrences(of: "\\[([^\\]]+)\\]\\([^)]+\\)", with: "$1", options: .regularExpression)

        // Remove markdown formatting
        cleaned = cleaned.replacingOccurrences(of: "\\*\\*([^*]+)\\*\\*", with: "$1", options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(of: "\\*([^*]+)\\*", with: "$1", options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(of: "__([^_]+)__", with: "$1", options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(of: "_([^_]+)_", with: "$1", options: .regularExpression)

        // Remove headers
        cleaned = cleaned.replacingOccurrences(of: "^#{1,6}\\s*", with: "", options: .regularExpression)

        // Remove URLs
        cleaned = cleaned.replacingOccurrences(of: "https?://[^\\s]+", with: "", options: .regularExpression)

        // Clean up whitespace
        cleaned = cleaned.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)

        return cleaned
    }

    private func playAudio(samples: [Float], sampleRate: Int) async {
        // Create WAV data
        guard let wavData = createWAVData(samples: samples, sampleRate: sampleRate) else {
            print("[KokoroTTS] Failed to create WAV data")
            isSpeaking = false
            currentMessageId = nil
            return
        }

        do {
            audioPlayer = try AVAudioPlayer(data: wavData)
            audioPlayer?.delegate = self
            audioPlayer?.prepareToPlay()
            audioPlayer?.play()
            print("[KokoroTTS] Playing audio...")
        } catch {
            print("[KokoroTTS] Audio playback error: \(error)")
            isSpeaking = false
            currentMessageId = nil
        }
    }

    private func createWAVData(samples: [Float], sampleRate: Int) -> Data? {
        let numSamples = samples.count
        let numChannels: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let bytesPerSample = Int(bitsPerSample / 8)
        let dataSize = numSamples * bytesPerSample

        var data = Data()

        // RIFF header
        data.append(contentsOf: "RIFF".utf8)
        var fileSize = UInt32(36 + dataSize)
        data.append(Data(bytes: &fileSize, count: 4))
        data.append(contentsOf: "WAVE".utf8)

        // fmt chunk
        data.append(contentsOf: "fmt ".utf8)
        var fmtSize: UInt32 = 16
        data.append(Data(bytes: &fmtSize, count: 4))
        var audioFormat: UInt16 = 1 // PCM
        data.append(Data(bytes: &audioFormat, count: 2))
        var channels = numChannels
        data.append(Data(bytes: &channels, count: 2))
        var rate = UInt32(sampleRate)
        data.append(Data(bytes: &rate, count: 4))
        var byteRate = UInt32(sampleRate * Int(numChannels) * bytesPerSample)
        data.append(Data(bytes: &byteRate, count: 4))
        var blockAlign = UInt16(numChannels * UInt16(bytesPerSample))
        data.append(Data(bytes: &blockAlign, count: 2))
        var bps = bitsPerSample
        data.append(Data(bytes: &bps, count: 2))

        // data chunk
        data.append(contentsOf: "data".utf8)
        var dataChunkSize = UInt32(dataSize)
        data.append(Data(bytes: &dataChunkSize, count: 4))

        // Audio samples (convert float to int16)
        for sample in samples {
            let clampedSample = max(-1.0, min(1.0, sample))
            var int16Sample = Int16(clampedSample * 32767.0)
            data.append(Data(bytes: &int16Sample, count: 2))
        }

        return data
    }

    /// Stop current speech
    func stop() {
        audioPlayer?.stop()
        audioPlayer = nil
        isSpeaking = false
        currentMessageId = nil
    }

    /// Check if the model is ready for use
    var isReady: Bool {
        return isModelDownloaded && tts != nil
    }

    /// Get the model download size in MB (approximate)
    var modelSizeDescription: String {
        return "約140MB"  // model.int8.onnx (109MB) + voices.bin (26.4MB) + espeak-ng-data (~5MB)
    }

    /// Reset and delete the downloaded model to allow re-download
    func resetModel() {
        stop()
        tts = nil
        isModelDownloaded = false
        UserDefaults.standard.set(false, forKey: "kokoro_tts_model_downloaded")

        // Delete the model directory
        do {
            if FileManager.default.fileExists(atPath: modelPath.path) {
                try FileManager.default.removeItem(at: modelPath)
                print("[KokoroTTS] Model directory deleted")
            }
        } catch {
            print("[KokoroTTS] Failed to delete model directory: \(error)")
        }
    }
}

// MARK: - AVAudioPlayerDelegate

extension KokoroTTSManager: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.isSpeaking = false
            self.currentMessageId = nil
            print("[KokoroTTS] Audio playback finished")
        }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        Task { @MainActor in
            self.isSpeaking = false
            self.currentMessageId = nil
            if let error = error {
                print("[KokoroTTS] Audio decode error: \(error)")
            }
        }
    }
}

// MARK: - Errors

enum KokoroTTSError: LocalizedError {
    case downloadFailed
    case modelNotFound
    case synthesisError

    var errorDescription: String? {
        switch self {
        case .downloadFailed:
            return "TTSモデルのダウンロードに失敗しました"
        case .modelNotFound:
            return "TTSモデルが見つかりません"
        case .synthesisError:
            return "音声合成に失敗しました"
        }
    }
}
#endif  // !targetEnvironment(macCatalyst)
