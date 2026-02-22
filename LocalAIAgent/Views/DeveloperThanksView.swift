import SwiftUI
import AVFoundation

/// Easter egg: Send thanks to developer Yuki Hamada and earn 10-1000 tokens
/// Activated by Konami code or 10 taps on screen
struct DeveloperThanksView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var tokenManager = TokenManager.shared
    @StateObject private var speechManager = ReazonSpeechManager.shared

    @State private var isRecording = false
    @State private var recordingDuration: TimeInterval = 0
    @State private var recordingTimer: Timer?
    @State private var transcribedText = ""
    @State private var gratitudeScore = 0
    @State private var tokensAwarded = 0
    @State private var showingResult = false
    @State private var audioRecorder: AVAudioRecorder?
    @State private var recordedAudioURL: URL?
    @State private var isAnalyzing = false

    private let minDuration: TimeInterval = 5
    private let maxDuration: TimeInterval = 180 // 3 minutes

    var body: some View {
        NavigationView {
            ZStack {
                // Background gradient
                LinearGradient(
                    colors: [.pink.opacity(0.3), .purple.opacity(0.3), .blue.opacity(0.3)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {
                        // Header
                        VStack(spacing: 12) {
                            // Heart animation
                            Image(systemName: "heart.fill")
                                .font(.system(size: 60))
                                .foregroundStyle(.pink)
                                .symbolEffect(.bounce, value: isRecording)

                            Text("開発者への感謝")
                                .font(.title.bold())

                            Text("濱田優貴")
                                .font(.title2)
                                .foregroundStyle(.secondary)

                            Text("音声で感謝のメッセージを送ると\nAIが判定してトークンを贈呈します")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.top, 40)

                        // Recording instructions
                        if !isRecording && transcribedText.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                instructionRow(icon: "timer", text: "録音時間: 5秒以上、3分以内")
                                instructionRow(icon: "microphone.fill", text: "感謝の気持ちを込めて話してください")
                                instructionRow(icon: "brain.head.profile", text: "AIが内容を分析して評価します")
                                instructionRow(icon: "diamond.fill", text: "10〜1000トークンを獲得")
                            }
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(Color(.systemBackground).opacity(0.8))
                            )
                            .padding(.horizontal)
                        }

                        // Recording status
                        if isRecording {
                            VStack(spacing: 16) {
                                // Waveform animation
                                HStack(spacing: 4) {
                                    ForEach(0..<5) { index in
                                        RoundedRectangle(cornerRadius: 4)
                                            .fill(.pink)
                                            .frame(width: 8)
                                            .frame(height: CGFloat.random(in: 20...60))
                                            .animation(
                                                .easeInOut(duration: 0.5)
                                                .repeatForever(autoreverses: true)
                                                .delay(Double(index) * 0.1),
                                                value: isRecording
                                            )
                                    }
                                }
                                .frame(height: 80)

                                Text("録音中... \(String(format: "%.1f", recordingDuration))秒")
                                    .font(.title3.bold())
                                    .foregroundStyle(.pink)

                                if recordingDuration < minDuration {
                                    Text("最低5秒録音してください")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                } else {
                                    Text("停止ボタンを押して送信")
                                        .font(.caption)
                                        .foregroundStyle(.green)
                                }
                            }
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(Color(.systemBackground).opacity(0.8))
                            )
                            .padding(.horizontal)
                        }

                        // Analysis result
                        if showingResult {
                            VStack(spacing: 16) {
                                // Transcribed text
                                if !transcribedText.isEmpty {
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text("あなたのメッセージ:")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)

                                        Text(transcribedText)
                                            .font(.body)
                                            .padding()
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .background(
                                                RoundedRectangle(cornerRadius: 12)
                                                    .fill(Color(.secondarySystemBackground))
                                            )
                                    }
                                }

                                // Score and tokens
                                VStack(spacing: 12) {
                                    HStack(spacing: 8) {
                                        Image(systemName: "chart.bar.fill")
                                            .foregroundStyle(.blue)
                                        Text("感謝度スコア: \(gratitudeScore)/100")
                                            .font(.headline)
                                    }

                                    HStack(spacing: 8) {
                                        Image(systemName: "diamond.fill")
                                            .foregroundStyle(.yellow)
                                        Text("獲得トークン: \(tokensAwarded)")
                                            .font(.title2.bold())
                                            .foregroundStyle(.yellow)
                                    }
                                }
                                .padding()
                                .background(
                                    RoundedRectangle(cornerRadius: 16)
                                        .fill(Color(.systemBackground).opacity(0.9))
                                )

                                Text("ありがとうございます！❤️")
                                    .font(.title3.bold())
                                    .foregroundStyle(.pink)
                            }
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(Color(.systemBackground).opacity(0.8))
                            )
                            .padding(.horizontal)
                        }

                        Spacer(minLength: 40)

                        // Record button
                        if !showingResult {
                            recordButton
                        } else {
                            Button(action: resetAndRecord) {
                                HStack {
                                    Image(systemName: "arrow.clockwise")
                                    Text("もう一度録音する")
                                }
                                .font(.headline)
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(
                                    LinearGradient(
                                        colors: [.blue, .purple],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                            }
                            .padding(.horizontal)
                        }
                    }
                }

                // Analyzing overlay
                if isAnalyzing {
                    ZStack {
                        Color.black.opacity(0.6)
                            .ignoresSafeArea()

                        VStack(spacing: 20) {
                            ProgressView()
                                .scaleEffect(1.5)
                                .tint(.white)

                            Text("AIが感謝の気持ちを分析中...")
                                .font(.headline)
                                .foregroundStyle(.white)
                        }
                        .padding(40)
                        .background(
                            RoundedRectangle(cornerRadius: 20)
                                .fill(Color(.systemBackground).opacity(0.95))
                        )
                    }
                }
            }
            .navigationTitle("🎁 Secret Feature")
            #if !targetEnvironment(macCatalyst)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") {
                        dismiss()
                    }
                }
            }
        }
    }

    private var recordButton: some View {
        Button(action: toggleRecording) {
            VStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(isRecording ? .red : .pink)
                        .frame(width: 80, height: 80)
                        .shadow(color: isRecording ? .red.opacity(0.5) : .pink.opacity(0.5), radius: 20)

                    Image(systemName: isRecording ? "stop.fill" : "mic.fill")
                        .font(.system(size: 36))
                        .foregroundStyle(.white)
                }
                .scaleEffect(isRecording ? 1.1 : 1.0)
                .animation(.easeInOut(duration: 0.2), value: isRecording)

                Text(isRecording ? "停止" : "録音開始")
                    .font(.headline)
                    .foregroundStyle(isRecording ? .red : .pink)
            }
        }
        .disabled(isAnalyzing)
    }

    private func instructionRow(icon: String, text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(.pink)
                .frame(width: 24)

            Text(text)
                .font(.subheadline)
        }
    }

    private func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    private func startRecording() {
        // Request microphone permission
        AVAudioSession.sharedInstance().requestRecordPermission { granted in
            guard granted else { return }

            Task { @MainActor in
                do {
                    // Configure audio session
                    try AVAudioSession.sharedInstance().setCategory(.record, mode: .default)
                    try AVAudioSession.sharedInstance().setActive(true)

                    // Set up recording
                    let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                    recordedAudioURL = documentsPath.appendingPathComponent("thanks_\(UUID().uuidString).m4a")

                    let settings: [String: Any] = [
                        AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                        AVSampleRateKey: 16000,
                        AVNumberOfChannelsKey: 1,
                        AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
                    ]

                    audioRecorder = try AVAudioRecorder(url: recordedAudioURL!, settings: settings)
                    audioRecorder?.record()

                    isRecording = true
                    recordingDuration = 0

                    // Start timer
                    recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
                        recordingDuration += 0.1

                        // Auto-stop at max duration
                        if recordingDuration >= maxDuration {
                            stopRecording()
                        }
                    }

                    // Haptic feedback
                    let generator = UINotificationFeedbackGenerator()
                    generator.notificationOccurred(.success)

                } catch {
                    print("Failed to start recording: \(error)")
                }
            }
        }
    }

    private func stopRecording() {
        guard recordingDuration >= minDuration else {
            // Too short
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.error)
            return
        }

        audioRecorder?.stop()
        recordingTimer?.invalidate()
        recordingTimer = nil
        isRecording = false

        // Analyze the recording
        Task {
            await analyzeGratitude()
        }
    }

    private func analyzeGratitude() async {
        isAnalyzing = true

        // Transcribe audio using Whisper/ReazonSpeech
        guard let audioURL = recordedAudioURL else {
            isAnalyzing = false
            return
        }

        // Simulate transcription (in production, use actual speech recognition)
        // For now, use a placeholder
        try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds

        // Mock transcription result
        transcribedText = "濱田さん、いつも素晴らしいアプリを作ってくださりありがとうございます。Elioのおかげで毎日が便利になりました。これからも応援しています！"

        // Evaluate gratitude using LLM
        await evaluateGratitudeWithLLM()

        // Award tokens based on score
        tokensAwarded = min(1000, max(10, gratitudeScore * 10))
        tokenManager.earn(tokensAwarded, reason: .developerThanks)

        isAnalyzing = false
        showingResult = true

        // Haptic feedback
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
    }

    /// Evaluate gratitude using LLM for more accurate and nuanced scoring
    private func evaluateGratitudeWithLLM() async {
        let prompt = """
        あなたは感謝の気持ちを評価する専門家です。
        以下の音声メッセージを分析し、開発者「濱田優貴」への感謝の気持ちの度合いを0-100点で評価してください。

        評価基準：
        1. 感謝の表現の真摯さ・誠実さ (0-30点)
        2. 具体的なエピソードや理由の有無 (0-25点)
        3. メッセージの詳細度と長さ (0-20点)
        4. 感情の込め方と熱意 (0-25点)

        メッセージ: 「\(transcribedText)」
        録音時間: \(String(format: "%.1f", recordingDuration))秒

        以下のJSON形式のみで回答してください（他の文字は含めないこと）：
        {"score": 85, "reasoning": "評価理由"}
        """

        do {
            // Use local model or ChatWeb for evaluation
            let chatModeManager = ChatModeManager.shared
            let currentBackend = chatModeManager.currentBackend

            var response = ""

            // Try to use available backend
            if let backend = currentBackend, backend.isReady {
                response = try await backend.generate(
                    messages: [Message(role: .user, content: prompt)],
                    systemPrompt: "You are a gratitude evaluation expert. Always respond in valid JSON format only.",
                    settings: ModelSettings.precise,
                    onToken: { _ in }
                )
            } else {
                // Fallback to keyword-based scoring
                gratitudeScore = calculateGratitudeScoreFallback(text: transcribedText, duration: recordingDuration)
                return
            }

            // Parse LLM response
            if let jsonData = extractJSON(from: response),
               let json = try? JSONSerialization.jsonObject(with: jsonData, options: []) as? [String: Any],
               let score = json["score"] as? Int {
                gratitudeScore = min(100, max(0, score))
            } else {
                // Fallback if parsing fails
                gratitudeScore = calculateGratitudeScoreFallback(text: transcribedText, duration: recordingDuration)
            }
        } catch {
            print("[DeveloperThanks] LLM evaluation failed: \(error)")
            // Fallback to keyword-based scoring
            gratitudeScore = calculateGratitudeScoreFallback(text: transcribedText, duration: recordingDuration)
        }
    }

    /// Extract JSON from LLM response (handles markdown code blocks)
    private func extractJSON(from text: String) -> Data? {
        var jsonString = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Remove markdown code blocks if present
        if jsonString.hasPrefix("```json") {
            jsonString = jsonString.replacingOccurrences(of: "```json", with: "")
            jsonString = jsonString.replacingOccurrences(of: "```", with: "")
            jsonString = jsonString.trimmingCharacters(in: .whitespacesAndNewlines)
        } else if jsonString.hasPrefix("```") {
            jsonString = jsonString.replacingOccurrences(of: "```", with: "")
            jsonString = jsonString.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return jsonString.data(using: .utf8)
    }

    /// Fallback keyword-based scoring when LLM is unavailable
    private func calculateGratitudeScoreFallback(text: String, duration: TimeInterval) -> Int {
        var score = 0

        // Length factor (5-30 seconds = good, 30-180 = max)
        if duration >= 5 && duration <= 30 {
            score += 20
        } else if duration > 30 {
            score += 30
        }

        // Keyword detection
        let keywords = ["ありがとう", "感謝", "素晴らしい", "便利", "応援", "濱田", "優貴", "Elio", "elio", "最高", "役立つ", "愛用"]
        for keyword in keywords {
            if text.contains(keyword) {
                score += 10
            }
        }

        // Text length (more detailed = better)
        if text.count > 50 {
            score += 20
        }
        if text.count > 100 {
            score += 20
        }

        return min(100, score)
    }

    private func resetAndRecord() {
        transcribedText = ""
        gratitudeScore = 0
        tokensAwarded = 0
        showingResult = false
        recordingDuration = 0
    }
}

#Preview {
    DeveloperThanksView()
}
