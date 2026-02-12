import SwiftUI

// MARK: - Voice Analysis Models

struct VoiceScores: Codable {
    let clarity: Int
    let stability: Int
    let warmth: Int
    let expressiveness: Int
    let listenability: Int
    let overall: Int
}

struct VoiceAnalysisResponse: Codable {
    let scores: VoiceScores
    let analysis: [String: AnyCodable]?
    let voiceType: String?
    let languageDetected: String?
    let compliment: String?
    let marketplaceEligible: Bool?

    enum CodingKeys: String, CodingKey {
        case scores, analysis, compliment
        case voiceType = "voice_type"
        case languageDetected = "language_detected"
        case marketplaceEligible = "marketplace_eligible"
    }
}

/// Simple AnyCodable wrapper for JSON values
struct AnyCodable: Codable {
    let value: Any

    init(_ value: Any) { self.value = value }
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let v = try? container.decode(Double.self) { value = v }
        else if let v = try? container.decode(String.self) { value = v }
        else if let v = try? container.decode(Bool.self) { value = v }
        else if let v = try? container.decode([String: AnyCodable].self) { value = v }
        else if let v = try? container.decode([AnyCodable].self) { value = v }
        else { value = NSNull() }
    }
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if let v = value as? Double { try container.encode(v) }
        else if let v = value as? String { try container.encode(v) }
        else if let v = value as? Bool { try container.encode(v) }
        else { try container.encodeNil() }
    }
}

// MARK: - Marketplace Voice Model

struct MarketplaceVoice: Identifiable, Codable {
    var id: String { voiceId }
    let voiceId: String
    let displayName: String
    let description: String?
    let creatorName: String?
    let scores: VoiceScores?
    let usageCount: Int?
    let publishedAt: String?
    let voiceType: String?
    let language: String?
    let previewUrl: String?

    enum CodingKeys: String, CodingKey {
        case displayName = "display_name"
        case description
        case creatorName = "creator_name"
        case scores
        case usageCount = "usage_count"
        case publishedAt = "published_at"
        case voiceType = "voice_type"
        case language
        case previewUrl = "preview_url"
        case voiceId = "voice_id"
    }
}

struct MarketplaceListResponse: Codable {
    let voices: [MarketplaceVoice]
    let total: Int?
}

// MARK: - Voice Analysis Manager

@MainActor
class VoiceAnalysisManager: ObservableObject {
    static let shared = VoiceAnalysisManager()

    @Published var analysisResult: VoiceAnalysisResponse?
    @Published var isAnalyzing = false
    @Published var analysisError: String?

    func analyzeVoice(audioData: Data) async {
        guard let token = SyncManager.shared.authToken else {
            analysisError = "chatweb.aiにログインしてください"
            return
        }

        isAnalyzing = true
        analysisError = nil

        let baseURL = SyncManager.shared.baseURL
        guard let url = URL(string: "\(baseURL)/api/v1/voice/analyze") else {
            analysisError = "URL error"
            isAnalyzing = false
            return
        }

        let audioB64 = audioData.base64EncodedString()
        let lang = Locale.current.language.languageCode?.identifier ?? "ja"

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "audio_base64": audioB64,
            "language": lang,
        ])
        request.timeoutInterval = 30

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let result = try JSONDecoder().decode(VoiceAnalysisResponse.self, from: data)
            analysisResult = result
        } catch {
            analysisError = "分析に失敗しました: \(error.localizedDescription)"
            print("[VoiceAnalysis] Error: \(error)")
        }

        isAnalyzing = false
    }
}

// MARK: - Voice Marketplace Manager

@MainActor
class VoiceMarketplaceManager: ObservableObject {
    static let shared = VoiceMarketplaceManager()

    @Published var voices: [MarketplaceVoice] = []
    @Published var isLoading = false
    @Published var isPublishing = false
    @Published var publishError: String?

    enum SortOption: String, CaseIterable {
        case popular = "popular"
        case newest = "newest"
        case highestRated = "highest_rated"

        var label: String {
            switch self {
            case .popular: return "人気順"
            case .newest: return "新着順"
            case .highestRated: return "高評価順"
            }
        }
    }

    func fetchVoices(sort: SortOption = .popular) async {
        let baseURL = SyncManager.shared.baseURL
        guard let url = URL(string: "\(baseURL)/api/v1/marketplace/voices?sort=\(sort.rawValue)&limit=30") else { return }

        isLoading = true
        defer { isLoading = false }

        var request = URLRequest(url: url)
        if let token = SyncManager.shared.authToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let response = try JSONDecoder().decode(MarketplaceListResponse.self, from: data)
            voices = response.voices
        } catch {
            print("[Marketplace] Fetch error: \(error)")
        }
    }

    func publishVoice(voiceId: String, displayName: String, description: String, voiceType: String, language: String) async -> Bool {
        guard let token = SyncManager.shared.authToken else {
            publishError = "ログインが必要です"
            return false
        }

        isPublishing = true
        publishError = nil

        let baseURL = SyncManager.shared.baseURL
        guard let url = URL(string: "\(baseURL)/api/v1/marketplace/publish") else {
            publishError = "URL error"
            isPublishing = false
            return false
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "voice_id": voiceId,
            "display_name": displayName,
            "description": description,
            "voice_type": voiceType,
            "language": language,
        ])

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let ok = json["ok"] as? Bool, ok {
                isPublishing = false
                return true
            } else {
                let errorMsg = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String
                publishError = errorMsg ?? "公開に失敗しました"
            }
        } catch {
            publishError = "エラー: \(error.localizedDescription)"
        }

        isPublishing = false
        return false
    }

    func useVoice(voiceId: String) async -> Bool {
        guard let token = SyncManager.shared.authToken else { return false }

        let baseURL = SyncManager.shared.baseURL
        guard let url = URL(string: "\(baseURL)/api/v1/marketplace/\(voiceId)/use") else { return false }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let ok = json["ok"] as? Bool, ok {
                return true
            }
        } catch {
            print("[Marketplace] Use voice error: \(error)")
        }
        return false
    }
}

// MARK: - Voice Analysis Result View

struct VoiceAnalysisResultView: View {
    let result: VoiceAnalysisResponse
    var onPublish: (() -> Void)?
    var onDismiss: (() -> Void)?

    private let scoreDefinitions: [(key: String, label: String, color: Color)] = [
        ("clarity", "クリアリティ", .blue),
        ("stability", "安定性", .green),
        ("warmth", "温かみ", .orange),
        ("expressiveness", "表現力", .purple),
        ("listenability", "聴きやすさ", .pink),
        ("overall", "総合", .red),
    ]

    var body: some View {
        VStack(spacing: 16) {
            // Header
            Text("声の分析結果")
                .font(.system(size: 18, weight: .bold))

            // Score grid
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible()),
            ], spacing: 12) {
                ForEach(scoreDefinitions, id: \.key) { def in
                    scoreCard(label: def.label, value: scoreValue(for: def.key), color: def.color)
                }
            }

            // Compliment text
            if let compliment = result.compliment, !compliment.isEmpty {
                Text(compliment)
                    .font(.system(size: 14))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .lineSpacing(4)
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.cardBackground)
                    )
            }

            // Voice type badge
            if let voiceType = result.voiceType, voiceType != "unknown" {
                HStack(spacing: 6) {
                    Image(systemName: "waveform")
                        .font(.system(size: 12))
                    Text(voiceType)
                        .font(.system(size: 13, weight: .medium))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(Color.teal.opacity(0.15))
                )
                .foregroundStyle(.teal)
            }

            // Marketplace CTA
            if result.marketplaceEligible == true {
                Button(action: { onPublish?() }) {
                    HStack(spacing: 8) {
                        Image(systemName: "building.2")
                        Text("マーケットプレイスに公開する")
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        LinearGradient(colors: [.purple, .indigo], startPoint: .leading, endPoint: .trailing)
                    )
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .shadow(color: .purple.opacity(0.3), radius: 8, y: 4)
                }
            }
        }
        .padding(20)
    }

    private func scoreValue(for key: String) -> Int {
        switch key {
        case "clarity": return result.scores.clarity
        case "stability": return result.scores.stability
        case "warmth": return result.scores.warmth
        case "expressiveness": return result.scores.expressiveness
        case "listenability": return result.scores.listenability
        case "overall": return result.scores.overall
        default: return 0
        }
    }

    private func scoreCard(label: String, value: Int, color: Color) -> some View {
        VStack(spacing: 6) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            Text("\(value)")
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(color)

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.secondary.opacity(0.15))
                        .frame(height: 4)

                    RoundedRectangle(cornerRadius: 2)
                        .fill(color)
                        .frame(width: geometry.size.width * CGFloat(value) / 100.0, height: 4)
                }
            }
            .frame(height: 4)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.cardBackground)
        )
    }
}

// MARK: - Voice Marketplace View

struct VoiceMarketplaceView: View {
    @StateObject private var manager = VoiceMarketplaceManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var selectedSort: VoiceMarketplaceManager.SortOption = .popular
    @State private var showingUseConfirmation = false
    @State private var selectedVoice: MarketplaceVoice?
    @State private var usedVoiceId: String?

    var body: some View {
        NavigationStack {
            ZStack {
                Color.chatBackgroundDynamic
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 16) {
                        // Sort picker
                        Picker("Sort", selection: $selectedSort) {
                            ForEach(VoiceMarketplaceManager.SortOption.allCases, id: \.self) { option in
                                Text(option.label).tag(option)
                            }
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal, 20)
                        .onChange(of: selectedSort) { _, _ in
                            Task { await manager.fetchVoices(sort: selectedSort) }
                        }

                        if manager.isLoading {
                            ProgressView()
                                .padding(.top, 40)
                        } else if manager.voices.isEmpty {
                            VStack(spacing: 12) {
                                Image(systemName: "mic.slash")
                                    .font(.system(size: 40))
                                    .foregroundStyle(.secondary)
                                Text("まだ声が公開されていません")
                                    .font(.system(size: 15))
                                    .foregroundStyle(.secondary)
                                Text("最初に公開してみませんか？")
                                    .font(.system(size: 13))
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.top, 60)
                        } else {
                            LazyVStack(spacing: 10) {
                                ForEach(manager.voices) { voice in
                                    marketplaceVoiceCard(voice)
                                }
                            }
                            .padding(.horizontal, 20)
                        }
                    }
                    .padding(.vertical, 12)
                }
            }
            .navigationTitle("ボイスマーケット")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完了") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
            .task {
                await manager.fetchVoices(sort: selectedSort)
            }
            .alert("声をライブラリに追加しますか？", isPresented: $showingUseConfirmation) {
                Button("追加する", role: .none) {
                    if let voice = selectedVoice {
                        Task {
                            let success = await manager.useVoice(voiceId: voice.voiceId)
                            if success {
                                usedVoiceId = voice.voiceId
                            }
                        }
                    }
                }
                Button("キャンセル", role: .cancel) {}
            } message: {
                if let voice = selectedVoice {
                    Text("\(voice.displayName) を自分のボイスライブラリに追加します。")
                }
            }
        }
    }

    private func marketplaceVoiceCard(_ voice: MarketplaceVoice) -> some View {
        let overall = voice.scores?.overall ?? 0
        let scoreColor: Color = overall >= 85 ? .green : overall >= 75 ? .blue : .orange

        return HStack(spacing: 14) {
            // Score circle
            ZStack {
                Circle()
                    .fill(scoreColor.opacity(0.15))
                    .frame(width: 50, height: 50)

                Text("\(overall)")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(scoreColor)
            }

            // Info
            VStack(alignment: .leading, spacing: 4) {
                Text(voice.displayName)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)

                HStack(spacing: 8) {
                    if let creator = voice.creatorName, !creator.isEmpty {
                        Label(creator, systemImage: "person")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    if let vtype = voice.voiceType, !vtype.isEmpty {
                        Text(vtype)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    Text("\(voice.usageCount ?? 0) uses")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }

                if let desc = voice.description, !desc.isEmpty {
                    Text(desc)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer()

            // Actions
            VStack(spacing: 8) {
                Button(action: {
                    selectedVoice = voice
                    showingUseConfirmation = true
                }) {
                    Text("使う")
                        .font(.system(size: 13, weight: .semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(Color.accentColor)
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                }

                if usedVoiceId == voice.voiceId {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.system(size: 14))
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.subtleSeparator, lineWidth: 0.5)
        )
    }
}

// MARK: - Marketplace Publish Sheet

struct MarketplacePublishView: View {
    @StateObject private var manager = VoiceMarketplaceManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var displayName = ""
    @State private var description = ""

    let voiceId: String
    let voiceType: String
    let language: String

    var body: some View {
        NavigationStack {
            ZStack {
                Color.chatBackgroundDynamic
                    .ignoresSafeArea()

                VStack(spacing: 20) {
                    // Icon
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(colors: [.purple, .indigo], startPoint: .topLeading, endPoint: .bottomTrailing)
                            )
                            .frame(width: 80, height: 80)
                            .shadow(color: .purple.opacity(0.3), radius: 12, y: 4)

                        Image(systemName: "building.2")
                            .font(.system(size: 32))
                            .foregroundStyle(.white)
                    }
                    .padding(.top, 20)

                    Text("声をマーケットプレイスに公開")
                        .font(.system(size: 18, weight: .bold))

                    Text("他のユーザーがあなたの声でAIと会話できるようになります。")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)

                    VStack(alignment: .leading, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("表示名")
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                            TextField("例: さくらボイス", text: $displayName)
                                .textFieldStyle(.roundedBorder)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("説明")
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                            TextField("あなたの声の特徴を教えてください", text: $description, axis: .vertical)
                                .textFieldStyle(.roundedBorder)
                                .lineLimit(3...5)
                        }
                    }
                    .padding(.horizontal, 20)

                    if let error = manager.publishError {
                        Text(error)
                            .font(.system(size: 13))
                            .foregroundStyle(.red)
                    }

                    Button(action: {
                        Task {
                            let success = await manager.publishVoice(
                                voiceId: voiceId,
                                displayName: displayName,
                                description: description,
                                voiceType: voiceType,
                                language: language
                            )
                            if success {
                                dismiss()
                            }
                        }
                    }) {
                        if manager.isPublishing {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Text("公開する")
                                .font(.system(size: 16, weight: .semibold))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        LinearGradient(colors: [.purple, .indigo], startPoint: .leading, endPoint: .trailing)
                    )
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .padding(.horizontal, 20)
                    .disabled(displayName.isEmpty || manager.isPublishing)
                    .opacity(displayName.isEmpty ? 0.6 : 1)

                    Spacer()
                }
            }
            .navigationTitle("マーケットプレイスに公開")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
            }
        }
    }
}

#Preview {
    VoiceMarketplaceView()
}
