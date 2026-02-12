import SwiftUI
import AVFoundation

// MARK: - Voice Model

struct VoiceInfo: Identifiable, Codable {
    let id: String
    let name: String
    let nameJa: String?
    let description: String?
    let descriptionJa: String?
    let gender: String?
    let language: String?
    let style: String?
    let type: String  // "preset" or "cloned"
    let engine: String?
    let modalVoiceRef: String?
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, name, description, gender, language, style, type, engine
        case nameJa = "name_ja"
        case descriptionJa = "description_ja"
        case modalVoiceRef = "modal_voice_ref"
        case createdAt = "created_at"
    }

    var displayName: String {
        let isJa = Locale.current.language.languageCode?.identifier == "ja"
        return (isJa ? nameJa : nil) ?? name
    }

    var displayDescription: String {
        let isJa = Locale.current.language.languageCode?.identifier == "ja"
        return (isJa ? descriptionJa : nil) ?? description ?? ""
    }

    var genderIcon: String {
        switch gender?.lowercased() {
        case "female": return "person.fill"
        case "male": return "person.fill"
        default: return "person.fill"
        }
    }

    var languageLabel: String {
        switch language?.lowercased() {
        case "ja": return "JP"
        case "en": return "EN"
        default: return language?.uppercased() ?? ""
        }
    }
}

struct VoicesResponse: Codable {
    let voices: [VoiceInfo]
}

// MARK: - Voice Manager

@MainActor
class VoiceSelectionManager: ObservableObject {
    static let shared = VoiceSelectionManager()

    @Published var voices: [VoiceInfo] = []
    @Published var selectedVoiceId: String
    @Published var isLoading = false
    @Published var isRecording = false
    @Published var recordingSeconds = 0
    @Published var cloneStatus: String = ""
    @Published var isCloning = false
    @Published var recordedAudioData: Data?

    private var audioRecorder: AVAudioRecorder?
    private var recordingTimer: Timer?
    private var recordingURL: URL?

    init() {
        selectedVoiceId = UserDefaults.standard.string(forKey: "ttsVoiceId") ?? "nova"
        loadDefaultVoices()
    }

    private func loadDefaultVoices() {
        voices = [
            VoiceInfo(id: "nova", name: "Nova", nameJa: "ノヴァ", description: "Warm, conversational", descriptionJa: "温かく会話的", gender: "female", language: "en", style: "warm", type: "preset", engine: "openai", modalVoiceRef: nil, createdAt: nil),
            VoiceInfo(id: "shimmer", name: "Shimmer", nameJa: "シマー", description: "Bright, energetic", descriptionJa: "明るく元気", gender: "female", language: "en", style: "bright", type: "preset", engine: "openai", modalVoiceRef: nil, createdAt: nil),
            VoiceInfo(id: "echo", name: "Echo", nameJa: "エコー", description: "Clear, balanced", descriptionJa: "クリアでバランス良い", gender: "male", language: "en", style: "calm", type: "preset", engine: "openai", modalVoiceRef: nil, createdAt: nil),
            VoiceInfo(id: "onyx", name: "Onyx", nameJa: "オニキス", description: "Deep, authoritative", descriptionJa: "深みのある声", gender: "male", language: "en", style: "deep", type: "preset", engine: "openai", modalVoiceRef: nil, createdAt: nil),
            VoiceInfo(id: "alloy", name: "Alloy", nameJa: "アロイ", description: "Neutral, versatile", descriptionJa: "ニュートラル", gender: "female", language: "en", style: "neutral", type: "preset", engine: "openai", modalVoiceRef: nil, createdAt: nil),
        ]
    }

    func selectVoice(_ voiceId: String) {
        selectedVoiceId = voiceId
        UserDefaults.standard.set(voiceId, forKey: "ttsVoiceId")
        // Also save to ChatWeb settings if logged in
        saveToChatWeb(voiceId: voiceId)
    }

    private func saveToChatWeb(voiceId: String) {
        guard let token = SyncManager.shared.authToken else { return }
        let baseURL = SyncManager.shared.baseURL
        guard let url = URL(string: "\(baseURL)/api/v1/settings/me") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "tts_voice": voiceId,
            "tts_voice_id": voiceId,
        ])

        URLSession.shared.dataTask(with: request) { _, _, _ in }.resume()
    }

    func fetchVoices() async {
        guard let token = SyncManager.shared.authToken else { return }
        let baseURL = SyncManager.shared.baseURL

        isLoading = true
        defer { isLoading = false }

        guard let url = URL(string: "\(baseURL)/api/v1/voices") else { return }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let response = try JSONDecoder().decode(VoicesResponse.self, from: data)
            voices = response.voices
        } catch {
            print("[VoiceSelection] Failed to fetch voices: \(error)")
        }
    }

    // MARK: - Voice Recording

    func startRecording() {
        #if os(iOS)
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try audioSession.setActive(true)
        } catch {
            cloneStatus = "マイクへのアクセスに失敗しました"
            return
        }
        #endif

        let tempDir = FileManager.default.temporaryDirectory
        recordingURL = tempDir.appendingPathComponent("voice_clone_\(UUID().uuidString).m4a")

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100.0,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]

        do {
            audioRecorder = try AVAudioRecorder(url: recordingURL!, settings: settings)
            audioRecorder?.record()
            isRecording = true
            recordingSeconds = 0
            cloneStatus = "録音中..."

            recordingTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.recordingSeconds += 1
                    if self.recordingSeconds >= 30 {
                        self.stopRecording()
                    }
                }
            }
        } catch {
            cloneStatus = "録音の開始に失敗しました"
        }
    }

    func stopRecording() {
        recordingTimer?.invalidate()
        recordingTimer = nil
        audioRecorder?.stop()
        isRecording = false

        guard recordingSeconds >= 3 else {
            cloneStatus = "3秒以上録音してください"
            return
        }

        // Read the recorded audio data
        guard let url = recordingURL,
              let data = try? Data(contentsOf: url) else {
            cloneStatus = "録音データの読み込みに失敗しました"
            return
        }

        recordedAudioData = data
        cloneStatus = "録音完了。名前を付けて保存してください。"
    }

    func saveClonedVoice(name: String) async {
        guard let audioData = recordedAudioData else {
            cloneStatus = "まず録音してください"
            return
        }
        guard let token = SyncManager.shared.authToken else {
            cloneStatus = "chatweb.aiにログインしてください"
            return
        }

        isCloning = true
        cloneStatus = "保存中..."

        let baseURL = SyncManager.shared.baseURL
        guard let url = URL(string: "\(baseURL)/api/v1/voices/clone") else {
            cloneStatus = "URL error"
            isCloning = false
            return
        }

        let audioB64 = audioData.base64EncodedString()

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "audio_base64": audioB64,
            "name": name,
        ])
        request.timeoutInterval = 60

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let voiceId = json["voice_id"] as? String {
                cloneStatus = "保存しました！"
                selectVoice(voiceId)
                recordedAudioData = nil
                await fetchVoices()
            } else {
                cloneStatus = "保存に失敗しました"
            }
        } catch {
            cloneStatus = "保存エラー: \(error.localizedDescription)"
        }

        isCloning = false
    }

    func deleteVoice(_ voiceId: String) async {
        guard let token = SyncManager.shared.authToken else { return }
        let baseURL = SyncManager.shared.baseURL
        guard let url = URL(string: "\(baseURL)/api/v1/voices/\(voiceId)") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        do {
            _ = try await URLSession.shared.data(for: request)
            if selectedVoiceId == voiceId {
                selectVoice("nova")
            }
            await fetchVoices()
        } catch {
            print("[VoiceSelection] Delete failed: \(error)")
        }
    }
}

// MARK: - Voice Selection View

struct VoiceSelectionView: View {
    @StateObject private var manager = VoiceSelectionManager.shared
    @EnvironmentObject var syncManager: SyncManager
    @Environment(\.dismiss) private var dismiss
    @State private var showingCloneSheet = false
    @State private var showingMarketplace = false
    @State private var cloneName = ""

    var presetVoices: [VoiceInfo] {
        manager.voices.filter { $0.type == "preset" }
    }

    var clonedVoices: [VoiceInfo] {
        manager.voices.filter { $0.type == "cloned" }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.chatBackgroundDynamic
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        // Preset voices
                        VStack(alignment: .leading, spacing: 12) {
                            ModernSectionHeader(
                                title: String(localized: "voice.preset.title", defaultValue: "プリセット音声"),
                                icon: "speaker.wave.2",
                                gradient: [.teal, .cyan]
                            )

                            LazyVGrid(columns: [
                                GridItem(.flexible(), spacing: 10),
                                GridItem(.flexible(), spacing: 10),
                            ], spacing: 10) {
                                ForEach(presetVoices) { voice in
                                    voiceCard(voice)
                                }
                            }
                        }

                        // Cloned voices
                        if !clonedVoices.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                ModernSectionHeader(
                                    title: String(localized: "voice.cloned.title", defaultValue: "クローン音声"),
                                    icon: "mic.fill",
                                    gradient: [.purple, .indigo]
                                )

                                ForEach(clonedVoices) { voice in
                                    clonedVoiceRow(voice)
                                }
                            }
                        }

                        // Clone button
                        if syncManager.isLoggedIn {
                            Button(action: { showingCloneSheet = true }) {
                                HStack(spacing: 10) {
                                    Image(systemName: "mic.badge.plus")
                                        .font(.system(size: 18))
                                    Text(String(localized: "voice.clone.button", defaultValue: "録音して声をクローン"))
                                        .font(.system(size: 15, weight: .semibold))
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(
                                    LinearGradient(
                                        colors: [.purple, .indigo],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .foregroundStyle(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                                .shadow(color: .purple.opacity(0.3), radius: 8, y: 4)
                            }
                        } else {
                            Text(String(localized: "voice.clone.login.required", defaultValue: "声のクローンにはchatweb.aiへのログインが必要です"))
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity)
                                .padding()
                        }

                        // Voice Marketplace button
                        if syncManager.isLoggedIn {
                            Button(action: { showingMarketplace = true }) {
                                HStack(spacing: 10) {
                                    Image(systemName: "building.2")
                                        .font(.system(size: 18))
                                    Text(String(localized: "voice.marketplace.button", defaultValue: "ボイスマーケット"))
                                        .font(.system(size: 15, weight: .semibold))
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(
                                    LinearGradient(
                                        colors: [.orange, .yellow],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .foregroundStyle(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                                .shadow(color: .orange.opacity(0.3), radius: 8, y: 4)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                }
            }
            .navigationTitle(String(localized: "voice.selection.title", defaultValue: "ボイス選択"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(String(localized: "common.done")) { dismiss() }
                        .fontWeight(.semibold)
                }
            }
            .task {
                await manager.fetchVoices()
            }
            .sheet(isPresented: $showingCloneSheet) {
                VoiceCloneRecordingView(manager: manager)
            }
            .sheet(isPresented: $showingMarketplace) {
                VoiceMarketplaceView()
            }
        }
    }

    private func voiceCard(_ voice: VoiceInfo) -> some View {
        let isSelected = manager.selectedVoiceId == voice.id

        return Button(action: {
            withAnimation(.easeInOut(duration: 0.2)) {
                manager.selectVoice(voice.id)
            }
        }) {
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(
                            voice.gender == "female"
                            ? Color.pink.opacity(0.15)
                            : Color.blue.opacity(0.15)
                        )
                        .frame(width: 44, height: 44)

                    Image(systemName: voice.genderIcon)
                        .font(.system(size: 20))
                        .foregroundStyle(
                            voice.gender == "female" ? .pink : .blue
                        )
                }

                VStack(spacing: 2) {
                    Text(voice.displayName)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)

                    HStack(spacing: 4) {
                        Text(voice.languageLabel)
                            .font(.system(size: 10, weight: .medium))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.secondary.opacity(0.15))
                            .clipShape(Capsule())

                        Text(voice.style ?? "")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.green)
                } else {
                    Image(systemName: "circle")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary.opacity(0.3))
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.cardBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(
                        isSelected ? Color.accentColor : Color.subtleSeparator,
                        lineWidth: isSelected ? 2 : 0.5
                    )
            )
            .shadow(color: isSelected ? Color.accentColor.opacity(0.2) : .clear, radius: 6)
        }
        .buttonStyle(.plain)
    }

    private func clonedVoiceRow(_ voice: VoiceInfo) -> some View {
        let isSelected = manager.selectedVoiceId == voice.id

        return HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.purple.opacity(0.15))
                    .frame(width: 40, height: 40)

                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(.purple)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(voice.name)
                    .font(.system(size: 15, weight: .medium))

                if let created = voice.createdAt {
                    Text(created.prefix(10))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }

            // Delete button
            Button(action: {
                Task { await manager.deleteVoice(voice.id) }
            }) {
                Image(systemName: "trash")
                    .font(.system(size: 14))
                    .foregroundStyle(.red.opacity(0.7))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(
                    isSelected ? Color.accentColor : Color.subtleSeparator,
                    lineWidth: isSelected ? 2 : 0.5
                )
        )
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.2)) {
                manager.selectVoice(voice.id)
            }
        }
    }
}

// MARK: - Voice Clone Recording View

struct VoiceCloneRecordingView: View {
    @ObservedObject var manager: VoiceSelectionManager
    @StateObject private var analysisManager = VoiceAnalysisManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var cloneName = ""
    @State private var showingPublishSheet = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.chatBackgroundDynamic
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {
                        Spacer(minLength: 20)

                        // Recording visualization
                        ZStack {
                            Circle()
                                .fill(
                                    manager.isRecording
                                    ? Color.red.opacity(0.15)
                                    : Color.purple.opacity(0.1)
                                )
                                .frame(width: 160, height: 160)
                                .scaleEffect(manager.isRecording ? 1.1 : 1.0)
                                .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: manager.isRecording)

                            Circle()
                                .fill(
                                    manager.isRecording
                                    ? LinearGradient(colors: [.red, .orange], startPoint: .top, endPoint: .bottom)
                                    : LinearGradient(colors: [.purple, .indigo], startPoint: .top, endPoint: .bottom)
                                )
                                .frame(width: 100, height: 100)
                                .shadow(color: (manager.isRecording ? Color.red : Color.purple).opacity(0.4), radius: 16, y: 4)

                            if manager.isRecording {
                                Image(systemName: "stop.fill")
                                    .font(.system(size: 32))
                                    .foregroundStyle(.white)
                            } else {
                                Image(systemName: "mic.fill")
                                    .font(.system(size: 32))
                                    .foregroundStyle(.white)
                            }
                        }
                        .onTapGesture {
                            if manager.isRecording {
                                manager.stopRecording()
                            } else {
                                manager.startRecording()
                            }
                        }

                        // Timer
                        if manager.isRecording || manager.recordingSeconds > 0 {
                            Text(formatTime(manager.recordingSeconds))
                                .font(.system(size: 32, weight: .bold, design: .rounded))
                                .monospacedDigit()
                        }

                        // Status
                        Text(manager.cloneStatus.isEmpty ? "タップして録音開始 (5-30秒)" : manager.cloneStatus)
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)

                        // Voice analysis results (shown after recording)
                        if let result = analysisManager.analysisResult, manager.recordedAudioData != nil {
                            VoiceAnalysisResultView(result: result, onPublish: {
                                showingPublishSheet = true
                            })
                        }

                        // Analysis loading
                        if analysisManager.isAnalyzing {
                            VStack(spacing: 8) {
                                ProgressView()
                                    .scaleEffect(0.9)
                                Text("声を分析中...")
                                    .font(.system(size: 13))
                                    .foregroundStyle(.secondary)
                            }
                        }

                        // Save section (shown after recording)
                        if manager.recordedAudioData != nil && !manager.isRecording {
                            VStack(spacing: 12) {
                                TextField("声の名前 (例: My Voice)", text: $cloneName)
                                    .textFieldStyle(.roundedBorder)
                                    .padding(.horizontal, 40)

                                HStack(spacing: 12) {
                                    // Re-record
                                    Button(action: {
                                        manager.recordedAudioData = nil
                                        manager.recordingSeconds = 0
                                        manager.cloneStatus = ""
                                        analysisManager.analysisResult = nil
                                    }) {
                                        Label("やり直し", systemImage: "arrow.counterclockwise")
                                            .font(.system(size: 14, weight: .medium))
                                            .padding(.horizontal, 16)
                                            .padding(.vertical, 10)
                                            #if os(iOS)
                                            .background(Color(.tertiarySystemBackground))
                                            #else
                                            .background(Color.secondary.opacity(0.1))
                                            #endif
                                            .clipShape(Capsule())
                                    }

                                    // Save
                                    Button(action: {
                                        let name = cloneName.isEmpty ? "My Voice" : cloneName
                                        Task {
                                            await manager.saveClonedVoice(name: name)
                                            if !manager.isCloning && manager.cloneStatus.contains("保存しました") {
                                                try? await Task.sleep(nanoseconds: 1_000_000_000)
                                                dismiss()
                                            }
                                        }
                                    }) {
                                        Label("保存", systemImage: "checkmark.circle.fill")
                                            .font(.system(size: 14, weight: .semibold))
                                            .padding(.horizontal, 20)
                                            .padding(.vertical, 10)
                                            .background(
                                                LinearGradient(colors: [.green, .teal], startPoint: .leading, endPoint: .trailing)
                                            )
                                            .foregroundStyle(.white)
                                            .clipShape(Capsule())
                                    }
                                    .disabled(manager.isCloning)
                                }
                            }
                        }

                        if manager.isCloning {
                            ProgressView()
                                .scaleEffect(0.8)
                        }

                        Text("5〜30秒の音声サンプルから声をコピーします。\n静かな場所で、はっきりと話してください。")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                            .padding(.bottom, 20)
                    }
                }
            }
            .navigationTitle("声をクローン")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
            }
            .onChange(of: manager.recordedAudioData) { _, newData in
                // Automatically analyze voice when recording is complete
                if let audioData = newData {
                    Task {
                        await analysisManager.analyzeVoice(audioData: audioData)
                    }
                }
            }
            .sheet(isPresented: $showingPublishSheet) {
                if let voices = Optional(manager.voices.filter({ $0.type == "cloned" })),
                   let latestClone = voices.last {
                    MarketplacePublishView(
                        voiceId: latestClone.id,
                        voiceType: analysisManager.analysisResult?.voiceType ?? "unknown",
                        language: analysisManager.analysisResult?.languageDetected ?? "ja"
                    )
                }
            }
        }
    }

    private func formatTime(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%d:%02d", m, s)
    }
}

#Preview {
    VoiceSelectionView()
        .environmentObject(SyncManager())
}
