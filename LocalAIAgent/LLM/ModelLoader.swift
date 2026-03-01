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

// Model category for UI organization
enum ModelCategory: String, Codable, CaseIterable {
    case recommended = "recommended"
    case japanese = "japanese"
    case vision = "vision"
    case efficient = "efficient"
    case others = "others"

    var displayName: String {
        switch self {
        case .recommended: return "おすすめ"
        case .japanese: return "日本語特化"
        case .vision: return "画像認識"
        case .efficient: return "高効率"
        case .others: return "その他"
        }
    }

    var displayNameEn: String {
        switch self {
        case .recommended: return "Recommended"
        case .japanese: return "Japanese Optimized"
        case .vision: return "Vision"
        case .efficient: return "Efficient"
        case .others: return "Others"
        }
    }
}

// ダウンロード進捗情報
struct DownloadProgressInfo: Equatable {
    let progress: Double              // 0.0 - 1.0
    let bytesDownloaded: Int64
    let totalBytes: Int64
    let speed: Double                 // bytes per second
    let estimatedTimeRemaining: TimeInterval?  // seconds

    var speedFormatted: String {
        let mbps = speed / 1_000_000
        return String(format: "%.1f MB/s", mbps)
    }

    var etaFormatted: String? {
        guard let eta = estimatedTimeRemaining, eta > 0 && eta < 86400 else { return nil }
        let mins = Int(eta) / 60
        let secs = Int(eta) % 60
        return String(format: "残り %d:%02d", mins, secs)
    }
}

@MainActor
final class ModelLoader: ObservableObject {
    // Singleton instance for sharing download progress across views
    @MainActor static let shared = ModelLoader()
    @Published var availableModels: [ModelInfo] = []
    @Published var downloadProgress: [String: Double] = [:]
    @Published var downloadProgressInfo: [String: DownloadProgressInfo] = [:]
    @Published var isDownloading = false

    private let fileManager = FileManager.default
    let deviceTier = DeviceTier.current

    struct ModelInfo: Identifiable, Codable {
        let id: String
        let name: String
        let description: String
        let descriptionEn: String
        let size: String
        let sizeBytes: Int64  // Exact size in bytes for total calculation
        let downloadURL: String
        let config: ModelConfigData
        let tier: ModelTier
        let category: ModelCategory
        let supportsVision: Bool
        let defaultSystemPrompt: String  // Default system prompt for this model

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
            sizeBytes: Int64 = 0,
            downloadURL: String,
            config: ModelConfigData,
            tier: ModelTier,
            category: ModelCategory = .others,
            supportsVision: Bool = false,
            defaultSystemPrompt: String = ""
        ) {
            self.id = id
            self.name = name
            self.description = description
            self.descriptionEn = descriptionEn ?? description
            self.size = size
            self.sizeBytes = sizeBytes
            self.downloadURL = downloadURL
            self.config = config
            self.tier = tier
            self.category = category
            self.supportsVision = supportsVision
            self.defaultSystemPrompt = defaultSystemPrompt
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

        // Recommended device tier for this model
        var recommendedDeviceName: String {
            switch tier {
            case .tiny:
                return "全デバイス"
            case .small:
                return "全デバイス"
            case .medium:
                return "スタンダード以上"
            case .large:
                return "Pro以上"
            case .xlarge:
                return "Pro Max"
            }
        }

        /// Recommended max tokens based on model's context length and device constraints
        /// Balances quality output with memory/performance on iPhone
        var recommendedMaxTokens: Int {
            let contextLen = config.maxContextLength
            // Reserve some context for input, calculate reasonable output limit
            // iPhone memory is limited, so cap based on model tier too
            let tierLimit: Int
            switch tier {
            case .tiny:
                tierLimit = 2048   // Small models can generate more
            case .small:
                tierLimit = 2048
            case .medium:
                tierLimit = 4096
            case .large:
                tierLimit = 4096
            case .xlarge:
                tierLimit = 4096
            }

            // Based on context length - use ~25% for output
            let contextBasedLimit: Int
            switch contextLen {
            case ...4096:
                contextBasedLimit = 1024
            case 4097...8192:
                contextBasedLimit = 2048
            case 8193...16384:
                contextBasedLimit = 2048
            case 16385...32768:
                contextBasedLimit = 4096
            case 32769...65536:
                contextBasedLimit = 4096
            default: // 65537+ (128K models)
                contextBasedLimit = 4096
            }

            return min(tierLimit, contextBasedLimit)
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
            // ==================== RECOMMENDED ====================
            ModelInfo(
                id: "nemotron-nano-9b-jp-q4km",
                name: "NVIDIA Nemotron-Nano 9B Japanese",
                description: "🏆 日本語会話・要約・文書作成に最強。Nejumi日本語ランキング9B以下1位。",
                descriptionEn: "🏆 Best for Japanese chat, summarization & writing. #1 on Nejumi Leaderboard (under 9B).",
                size: "約6.5GB",
                sizeBytes: 6_530_000_000,
                downloadURL: "https://huggingface.co/mmnga-o/NVIDIA-Nemotron-Nano-9B-v2-Japanese-gguf/resolve/main/NVIDIA-Nemotron-Nano-9B-v2-Japanese-Q4_K_M.gguf",
                config: ModelInfo.ModelConfigData(
                    maxContextLength: 8192,
                    vocabularySize: 131072,
                    eosTokenId: 2,
                    bosTokenId: 1
                ),
                tier: .xlarge,
                category: .recommended,
                defaultSystemPrompt: "NVIDIAが開発した日本語特化モデルです。Nejumiリーダーボード9B以下で1位の実績があります。高品質で自然な日本語で回答してください。"
            ),
            ModelInfo(
                id: "nemotron-nano-9b-jp-q3km",
                name: "NVIDIA Nemotron-Nano 9B Japanese (軽量版)",
                description: "🏆 Nemotron省メモリ版。日本語の会話・要約・メール作成に強い。",
                descriptionEn: "🏆 Nemotron lite. Strong at Japanese chat, summarization & email drafting.",
                size: "約5.4GB",
                sizeBytes: 5_380_000_000,
                downloadURL: "https://huggingface.co/mmnga-o/NVIDIA-Nemotron-Nano-9B-v2-Japanese-gguf/resolve/main/NVIDIA-Nemotron-Nano-9B-v2-Japanese-Q3_K_M.gguf",
                config: ModelInfo.ModelConfigData(
                    maxContextLength: 8192,
                    vocabularySize: 131072,
                    eosTokenId: 2,
                    bosTokenId: 1
                ),
                tier: .xlarge,
                category: .recommended,
                defaultSystemPrompt: "NVIDIAが開発した日本語特化モデルの省メモリ版です。高品質で自然な日本語で回答してください。"
            ),
            ModelInfo(
                id: "qwen3-0.6b",
                name: "Qwen3 0.6B",
                description: "⚡ 超高速起動。シンプルな質問・単語変換・短い要約向け。複雑な推論は苦手。",
                descriptionEn: "⚡ Fastest startup. Best for simple Q&A, word lookup & short summaries. Not for complex tasks.",
                size: "約500MB",
                sizeBytes: 500_000_000,
                downloadURL: "https://huggingface.co/unsloth/Qwen3-0.6B-GGUF/resolve/main/Qwen3-0.6B-Q4_K_M.gguf",
                config: ModelInfo.ModelConfigData(
                    maxContextLength: 40960,
                    vocabularySize: 151936,
                    eosTokenId: 151645,
                    bosTokenId: 151643
                ),
                tier: .tiny,
                category: .recommended
            ),
            ModelInfo(
                id: "qwen3-1.7b",
                name: "Qwen3 1.7B",
                description: "日常会話・要約・翻訳・簡単なコード生成が得意。軽量で使いやすい入門モデル。",
                descriptionEn: "Great for daily chat, summarization, translation & basic coding. Lightweight and easy to use.",
                size: "約1.2GB",
                sizeBytes: 1_200_000_000,
                downloadURL: "https://huggingface.co/unsloth/Qwen3-1.7B-GGUF/resolve/main/Qwen3-1.7B-Q4_K_M.gguf",
                config: ModelInfo.ModelConfigData(
                    maxContextLength: 40960,
                    vocabularySize: 151936,
                    eosTokenId: 151645,
                    bosTokenId: 151643
                ),
                tier: .small,
                category: .recommended
            ),
            ModelInfo(
                id: "qwen3-4b",
                name: "Qwen3 4B",
                description: "複雑な質問・多段階推論・コード生成・多言語対応に強い。日常からプロ用途まで幅広く対応。",
                descriptionEn: "Strong at complex Q&A, multi-step reasoning, code & multilingual tasks. Versatile from daily use to professional tasks.",
                size: "約2.7GB",
                sizeBytes: 2_700_000_000,
                downloadURL: "https://huggingface.co/unsloth/Qwen3-4B-GGUF/resolve/main/Qwen3-4B-Q4_K_M.gguf",
                config: ModelInfo.ModelConfigData(
                    maxContextLength: 40960,
                    vocabularySize: 151936,
                    eosTokenId: 151645,
                    bosTokenId: 151643
                ),
                tier: .large,
                category: .recommended
            ),
            ModelInfo(
                id: "qwen3-8b",
                name: "Qwen3 8B",
                description: "全方位高性能。長文生成・高度な推論・コード・創作・学術まで何でも対応。",
                descriptionEn: "All-round high performance. Handles long text, advanced reasoning, code, creative & academic tasks.",
                size: "約5GB",
                sizeBytes: 5_000_000_000,
                downloadURL: "https://huggingface.co/unsloth/Qwen3-8B-GGUF/resolve/main/Qwen3-8B-Q4_K_M.gguf",
                config: ModelInfo.ModelConfigData(
                    maxContextLength: 40960,
                    vocabularySize: 151936,
                    eosTokenId: 151645,
                    bosTokenId: 151643
                ),
                tier: .xlarge,
                category: .recommended
            ),

            // ==================== MEMORY-EFFICIENT (省メモリ版) ====================
            // For devices with limited memory (4-6GB)
            ModelInfo(
                id: "qwen3-1.7b-iq3xxs",
                name: "Qwen3 1.7B IQ3_XXS",
                description: "🔋 省メモリ版。iPhone 13/14/15向け。日常会話・翻訳・短い要約が得意。",
                descriptionEn: "🔋 Memory-efficient for iPhone 13/14/15. Great for daily chat, translation & short summaries.",
                size: "約730MB",
                sizeBytes: 730_000_000,
                downloadURL: "https://huggingface.co/unsloth/Qwen3-1.7B-GGUF/resolve/main/Qwen3-1.7B-UD-IQ3_XXS.gguf",
                config: ModelInfo.ModelConfigData(
                    maxContextLength: 40960,
                    vocabularySize: 151936,
                    eosTokenId: 151645,
                    bosTokenId: 151643
                ),
                tier: .small,
                category: .efficient
            ),
            ModelInfo(
                id: "qwen3-1.7b-iq2xxs",
                name: "Qwen3 1.7B IQ2_XXS",
                description: "🔋 超省メモリ版。バッテリー・メモリ最優先。シンプルな質問向け。",
                descriptionEn: "🔋 Ultra memory-efficient. Minimal RAM & battery use. Best for simple questions.",
                size: "約580MB",
                sizeBytes: 580_000_000,
                downloadURL: "https://huggingface.co/unsloth/Qwen3-1.7B-GGUF/resolve/main/Qwen3-1.7B-UD-IQ2_XXS.gguf",
                config: ModelInfo.ModelConfigData(
                    maxContextLength: 40960,
                    vocabularySize: 151936,
                    eosTokenId: 151645,
                    bosTokenId: 151643
                ),
                tier: .tiny,
                category: .efficient
            ),
            ModelInfo(
                id: "qwen3-4b-iq3xxs",
                name: "Qwen3 4B IQ3_XXS",
                description: "🔋 省メモリ高性能版。iPhone 13/14/15向け。コード・分析・複雑な質問が得意。",
                descriptionEn: "🔋 Memory-efficient 4B for iPhone 13/14/15. Good at code, analysis & complex questions.",
                size: "約1.7GB",
                sizeBytes: 1_670_000_000,
                downloadURL: "https://huggingface.co/unsloth/Qwen3-4B-GGUF/resolve/main/Qwen3-4B-UD-IQ3_XXS.gguf",
                config: ModelInfo.ModelConfigData(
                    maxContextLength: 40960,
                    vocabularySize: 151936,
                    eosTokenId: 151645,
                    bosTokenId: 151643
                ),
                tier: .medium,
                category: .efficient
            ),
            ModelInfo(
                id: "qwen3-4b-iq2xxs",
                name: "Qwen3 4B IQ2_XXS",
                description: "🔋 4B超省メモリ版。メモリ6GB以下の端末でも4Bの思考力を活用。",
                descriptionEn: "🔋 4B ultra memory-efficient. Brings 4B thinking power even to 6GB RAM devices.",
                size: "約1.3GB",
                sizeBytes: 1_260_000_000,
                downloadURL: "https://huggingface.co/unsloth/Qwen3-4B-GGUF/resolve/main/Qwen3-4B-UD-IQ2_XXS.gguf",
                config: ModelInfo.ModelConfigData(
                    maxContextLength: 40960,
                    vocabularySize: 151936,
                    eosTokenId: 151645,
                    bosTokenId: 151643
                ),
                tier: .small,
                category: .efficient
            ),

            ModelInfo(
                id: "gemma-3-1b",
                name: "Gemma 3 1B",
                description: "Google最新。超軽量・高速起動。手軽な質問応答・翻訳向け。リアルタイム情報は不得意。",
                descriptionEn: "Latest Google. Ultra-light & fast. Good for quick Q&A & translation. Not for real-time data.",
                size: "約700MB",
                sizeBytes: 700_000_000,
                downloadURL: "https://huggingface.co/unsloth/gemma-3-1b-it-GGUF/resolve/main/gemma-3-1b-it-Q4_K_M.gguf",
                config: ModelInfo.ModelConfigData(
                    maxContextLength: 32768,
                    vocabularySize: 262144,
                    eosTokenId: 1,
                    bosTokenId: 2
                ),
                tier: .small,
                category: .recommended
            ),
            ModelInfo(
                id: "gemma-3-4b",
                name: "Gemma 3 4B",
                description: "Google最新。長文対応（128K）・マルチタスク・要約・翻訳に強い。Pro推奨。",
                descriptionEn: "Latest Google. Long context (128K), multi-task, summarization & translation. Pro recommended.",
                size: "約2.5GB",
                sizeBytes: 2_500_000_000,
                downloadURL: "https://huggingface.co/unsloth/gemma-3-4b-it-GGUF/resolve/main/gemma-3-4b-it-Q4_K_M.gguf",
                config: ModelInfo.ModelConfigData(
                    maxContextLength: 131072,
                    vocabularySize: 262144,
                    eosTokenId: 1,
                    bosTokenId: 2
                ),
                tier: .large,
                category: .recommended
            ),
            ModelInfo(
                id: "phi-4-mini",
                name: "Phi-4 Mini 3.8B",
                description: "🧠 MS製。推論・数学に最強。Pro推奨。",
                descriptionEn: "🧠 By Microsoft. Best at reasoning & math. Pro recommended.",
                size: "約2.4GB",
                sizeBytes: 2_400_000_000,
                downloadURL: "https://huggingface.co/unsloth/Phi-4-mini-instruct-GGUF/resolve/main/Phi-4-mini-instruct-Q4_K_M.gguf",
                config: ModelInfo.ModelConfigData(
                    maxContextLength: 16384,
                    vocabularySize: 100352,
                    eosTokenId: 100257,
                    bosTokenId: 100257
                ),
                tier: .large,
                category: .recommended
            ),

            // ==================== JAPANESE OPTIMIZED ====================
            ModelInfo(
                id: "eliochat-1.7b-v3",
                name: "ElioChat 1.7B v3",
                description: "🇯🇵 ElioChat専用ファインチューニング済み。日常会話・雑談が得意。軽量で省メモリ。",
                descriptionEn: "🇯🇵 Fine-tuned for ElioChat. Best at daily conversation & casual chat. Lightweight.",
                size: "約1.3GB",
                sizeBytes: 1_260_000_000,
                downloadURL: "https://huggingface.co/yukihamada/ElioChat-1.7B-Instruct-v3/resolve/main/ElioChat-1.7B-Instruct-v3-Q5_K_M.gguf",
                config: ModelInfo.ModelConfigData(
                    maxContextLength: 32768,
                    vocabularySize: 151936,
                    eosTokenId: 151645,
                    bosTokenId: 151643
                ),
                tier: .small,
                category: .japanese,
                defaultSystemPrompt: "ElioChat専用にファインチューニングされた日本語特化モデルです。不確かな数値や事実には「確かではありませんが、」を必ず付けてください。"
            ),
            ModelInfo(
                id: "tinyswallow-1.5b",
                name: "TinySwallow 1.5B",
                description: "🇯🇵 Sakana AI製。軽量ながら自然な日本語会話・要約・メール文章作成が得意。",
                descriptionEn: "🇯🇵 By Sakana AI. Natural Japanese chat, summarization & email drafting despite small size.",
                size: "約986MB",
                sizeBytes: 986_000_000,
                downloadURL: "https://huggingface.co/bartowski/TinySwallow-1.5B-Instruct-GGUF/resolve/main/TinySwallow-1.5B-Instruct-Q4_K_M.gguf",
                config: ModelInfo.ModelConfigData(
                    maxContextLength: 32768,
                    vocabularySize: 151936,
                    eosTokenId: 151645,
                    bosTokenId: 151643
                ),
                tier: .small,
                category: .japanese,
                defaultSystemPrompt: "Sakana AIが開発した日本語特化モデルです。自然で高品質な日本語で回答してください。"
            ),
            ModelInfo(
                id: "elyza-llama3-8b",
                name: "ELYZA Llama 3 8B",
                description: "🇯🇵 東大松尾研発。複雑な日本語質問・長文読解・ビジネス文書・要約に最強クラス。",
                descriptionEn: "🇯🇵 By UTokyo Matsuo Lab. Exceptional at complex Japanese Q&A, long-form reading & business docs.",
                size: "約5.2GB",
                sizeBytes: 5_200_000_000,
                downloadURL: "https://huggingface.co/elyza/Llama-3-ELYZA-JP-8B-GGUF/resolve/main/Llama-3-ELYZA-JP-8B-q4_k_m.gguf",
                config: ModelInfo.ModelConfigData(
                    maxContextLength: 8192,
                    vocabularySize: 128256,
                    eosTokenId: 128001,
                    bosTokenId: 128000
                ),
                tier: .xlarge,
                category: .japanese,
                defaultSystemPrompt: "東大松尾研が開発した日本語特化モデルです。日本語の複雑な質問や長文処理を得意とします。自然で高品質な日本語で回答してください。"
            ),
            ModelInfo(
                id: "swallow-8b",
                name: "Llama 3.1 Swallow 8B",
                description: "🇯🇵 東工大など製。日本の時事・文化・法律知識が豊富。ビジネス文書・報告書作成に強い。",
                descriptionEn: "🇯🇵 By Tokyo Tech. Rich Japanese cultural & legal knowledge. Strong at business & report writing.",
                size: "約5.2GB",
                sizeBytes: 5_200_000_000,
                downloadURL: "https://huggingface.co/mradermacher/Llama-3.1-Swallow-8B-Instruct-v0.3-GGUF/resolve/main/Llama-3.1-Swallow-8B-Instruct-v0.3.Q4_K_M.gguf",
                config: ModelInfo.ModelConfigData(
                    maxContextLength: 8192,
                    vocabularySize: 128256,
                    eosTokenId: 128001,
                    bosTokenId: 128000
                ),
                tier: .xlarge,
                category: .japanese,
                defaultSystemPrompt: "東工大等が開発した日本語特化モデルです。日本語の知識が豊富でビジネス文書作成も得意です。自然で高品質な日本語で回答してください。"
            ),

            // ==================== EFFICIENT (Small but powerful) ====================
            ModelInfo(
                id: "lfm2-1.2b",
                name: "LFM2 1.2B",
                description: "⚡ Liquid AI製。1.2Bながら同サイズ最高クラスの性能。日常会話・要約・翻訳向け。",
                descriptionEn: "⚡ By Liquid AI. Top performance at 1.2B size. Great for daily chat, summarization & translation.",
                size: "約731MB",
                sizeBytes: 731_000_000,
                downloadURL: "https://huggingface.co/LiquidAI/LFM2-1.2B-GGUF/resolve/main/LFM2-1.2B-Q4_K_M.gguf",
                config: ModelInfo.ModelConfigData(
                    maxContextLength: 32768,
                    vocabularySize: 128256,
                    eosTokenId: 128001,
                    bosTokenId: 128000
                ),
                tier: .small,
                category: .efficient
            ),
            ModelInfo(
                id: "lfm2-350m",
                name: "LFM2 350M",
                description: "⚡ 350MBの超軽量。Qwen3-0.6B並みの性能。即答・単語変換・最速レスポンス向け。",
                descriptionEn: "⚡ Only 350MB. Rivals Qwen3-0.6B. Best for instant answers & word lookups with minimal wait.",
                size: "約350MB",
                sizeBytes: 350_000_000,
                downloadURL: "https://huggingface.co/LiquidAI/LFM2-350M-GGUF/resolve/main/LFM2-350M-Q4_K_M.gguf",
                config: ModelInfo.ModelConfigData(
                    maxContextLength: 32768,
                    vocabularySize: 128256,
                    eosTokenId: 128001,
                    bosTokenId: 128000
                ),
                tier: .tiny,
                category: .efficient
            ),

            // ==================== VISION ====================
            ModelInfo(
                id: "qwen3-vl-2b",
                name: "Qwen3-VL 2B",
                description: "📷 最新Qwen3ベースの画像認識。写真内のテキスト読取・物体識別・図表説明が得意。",
                descriptionEn: "📷 Qwen3-based vision. Good at reading text in images, object identification & chart explanation.",
                size: "約1.1GB",
                sizeBytes: 1_100_000_000,
                downloadURL: "https://huggingface.co/Qwen/Qwen3-VL-2B-Instruct-GGUF/resolve/main/Qwen3VL-2B-Instruct-Q4_K_M.gguf",
                config: ModelInfo.ModelConfigData(
                    maxContextLength: 32768,
                    vocabularySize: 151936,
                    eosTokenId: 151645,
                    bosTokenId: 151643
                ),
                tier: .medium,
                category: .vision,
                supportsVision: true
            ),
            ModelInfo(
                id: "qwen3-vl-4b",
                name: "Qwen3-VL 4B",
                description: "📷 高精度な画像認識。複雑なシーン理解・日本語OCR・手書き文字読取が得意。Pro以上推奨。",
                descriptionEn: "📷 High-accuracy vision. Great at complex scene understanding, Japanese OCR & handwriting. Pro+.",
                size: "約2.5GB",
                sizeBytes: 2_500_000_000,
                downloadURL: "https://huggingface.co/Qwen/Qwen3-VL-4B-Instruct-GGUF/resolve/main/Qwen3VL-4B-Instruct-Q4_K_M.gguf",
                config: ModelInfo.ModelConfigData(
                    maxContextLength: 32768,
                    vocabularySize: 151936,
                    eosTokenId: 151645,
                    bosTokenId: 151643
                ),
                tier: .large,
                category: .vision,
                supportsVision: true
            ),
            ModelInfo(
                id: "qwen3-vl-8b",
                name: "Qwen3-VL 8B",
                description: "📷 最高性能の画像認識。図面・レシート・複雑な表・多言語OCRまで高精度対応。",
                descriptionEn: "📷 Best vision performance. Handles blueprints, receipts, complex tables & multilingual OCR.",
                size: "約5GB",
                sizeBytes: 5_000_000_000,
                downloadURL: "https://huggingface.co/Qwen/Qwen3-VL-8B-Instruct-GGUF/resolve/main/Qwen3VL-8B-Instruct-Q4_K_M.gguf",
                config: ModelInfo.ModelConfigData(
                    maxContextLength: 32768,
                    vocabularySize: 151936,
                    eosTokenId: 151645,
                    bosTokenId: 151643
                ),
                tier: .xlarge,
                category: .vision,
                supportsVision: true
            ),

            // ==================== OTHERS ====================
            ModelInfo(
                id: "smolvlm-instruct",
                name: "SmolVLM 2B",
                description: "📷 HuggingFace製の軽量画像認識。写真の簡単な説明・物体識別向け。",
                descriptionEn: "📷 Lightweight vision by HuggingFace. Good for simple image descriptions & object detection.",
                size: "約1.5GB",
                sizeBytes: 1_500_000_000,
                downloadURL: "https://huggingface.co/mradermacher/SmolVLM-Instruct-GGUF/resolve/main/SmolVLM-Instruct.Q4_K_M.gguf",
                config: ModelInfo.ModelConfigData(
                    maxContextLength: 8192,
                    vocabularySize: 49152,
                    eosTokenId: 2,
                    bosTokenId: 1
                ),
                tier: .medium,
                category: .others,
                supportsVision: true
            ),
            ModelInfo(
                id: "llama-3.2-3b",
                name: "Llama 3.2 3B",
                description: "Meta製。英語・多言語タスク・指示への忠実な応答が得意。汎用モデル。",
                descriptionEn: "By Meta. Strong at English, multilingual tasks & instruction following. Versatile all-rounder.",
                size: "約2GB",
                sizeBytes: 2_000_000_000,
                downloadURL: "https://huggingface.co/bartowski/Llama-3.2-3B-Instruct-GGUF/resolve/main/Llama-3.2-3B-Instruct-Q4_K_M.gguf",
                config: ModelInfo.ModelConfigData(
                    maxContextLength: 131072,
                    vocabularySize: 128256,
                    eosTokenId: 128001,
                    bosTokenId: 128000
                ),
                tier: .medium,
                category: .others
            ),
            ModelInfo(
                id: "deepseek-r1-distill-qwen-1.5b",
                name: "DeepSeek-R1 1.5B",
                description: "🧮 数学・論理パズル・ステップ別問題解決に特化。Think機能で推論過程を表示。軽量版。",
                descriptionEn: "🧮 Specialized in math, logic puzzles & step-by-step problem solving. Shows reasoning with Think mode.",
                size: "約1.1GB",
                sizeBytes: 1_100_000_000,
                downloadURL: "https://huggingface.co/unsloth/DeepSeek-R1-Distill-Qwen-1.5B-GGUF/resolve/main/DeepSeek-R1-Distill-Qwen-1.5B-Q4_K_M.gguf",
                config: ModelInfo.ModelConfigData(
                    maxContextLength: 32768,
                    vocabularySize: 151936,
                    eosTokenId: 151645,
                    bosTokenId: 151643
                ),
                tier: .small,
                category: .others
            ),
            ModelInfo(
                id: "deepseek-r1-distill-qwen-7b",
                name: "DeepSeek-R1 7B",
                description: "🧮 高度な数学・科学・コード推論に最適。複雑な論理問題を段階的に解く。Pro推奨。",
                descriptionEn: "🧮 Ideal for advanced math, science & code reasoning. Solves complex logic step-by-step. Pro+.",
                size: "約4.7GB",
                sizeBytes: 4_700_000_000,
                downloadURL: "https://huggingface.co/unsloth/DeepSeek-R1-Distill-Qwen-7B-GGUF/resolve/main/DeepSeek-R1-Distill-Qwen-7B-Q4_K_M.gguf",
                config: ModelInfo.ModelConfigData(
                    maxContextLength: 32768,
                    vocabularySize: 151936,
                    eosTokenId: 151645,
                    bosTokenId: 151643
                ),
                tier: .xlarge,
                category: .others
            ),
            ModelInfo(
                id: "deepseek-r1-distill-llama-8b",
                name: "DeepSeek-R1 8B",
                description: "🧮 最高クラスの推論性能。数学・プログラミング・複雑な論証に最強。Pro Max推奨。",
                descriptionEn: "🧮 Top-tier reasoning. Best for math, programming & complex argumentation. Pro Max recommended.",
                size: "約5GB",
                sizeBytes: 5_000_000_000,
                downloadURL: "https://huggingface.co/unsloth/DeepSeek-R1-Distill-Llama-8B-GGUF/resolve/main/DeepSeek-R1-Distill-Llama-8B-Q4_K_M.gguf",
                config: ModelInfo.ModelConfigData(
                    maxContextLength: 131072,
                    vocabularySize: 128256,
                    eosTokenId: 128001,
                    bosTokenId: 128000
                ),
                tier: .xlarge,
                category: .others
            ),

            // ==================== ENTERPRISE & SPECIALIZED ====================
            ModelInfo(
                id: "granite-3.1-2b",
                name: "Granite 3.1 2B",
                description: "IBM製。低ハルシネーション。コード・長文処理に強い。",
                descriptionEn: "By IBM. Low hallucination. Strong at code & long text.",
                size: "約1.5GB",
                sizeBytes: 1_500_000_000,
                downloadURL: "https://huggingface.co/bartowski/granite-3.1-2b-instruct-GGUF/resolve/main/granite-3.1-2b-instruct-Q4_K_M.gguf",
                config: ModelInfo.ModelConfigData(
                    maxContextLength: 131072,
                    vocabularySize: 49152,
                    eosTokenId: 0,
                    bosTokenId: 0
                ),
                tier: .small,
                category: .others
            ),
            ModelInfo(
                id: "granite-3.1-8b",
                name: "Granite 3.1 8B",
                description: "IBM製。高性能版。長文・ビジネス文書向け。Pro Max推奨。",
                descriptionEn: "By IBM. High performance. For long docs. Pro Max recommended.",
                size: "約5GB",
                sizeBytes: 5_000_000_000,
                downloadURL: "https://huggingface.co/bartowski/granite-3.1-8b-instruct-GGUF/resolve/main/granite-3.1-8b-instruct-Q4_K_M.gguf",
                config: ModelInfo.ModelConfigData(
                    maxContextLength: 131072,
                    vocabularySize: 49152,
                    eosTokenId: 0,
                    bosTokenId: 0
                ),
                tier: .xlarge,
                category: .others
            ),
            ModelInfo(
                id: "h2o-danube3-4b",
                name: "H2O Danube3 4B",
                description: "H2O.ai製のモバイル特化モデル。自然な会話応答・FAQ応答・カスタマーサポート向け。",
                descriptionEn: "Mobile-optimized by H2O.ai. Great for natural conversation, FAQ responses & customer support.",
                size: "約2.6GB",
                sizeBytes: 2_600_000_000,
                downloadURL: "https://huggingface.co/bartowski/h2o-danube3-4b-chat-GGUF/resolve/main/h2o-danube3-4b-chat-Q4_K_M.gguf",
                config: ModelInfo.ModelConfigData(
                    maxContextLength: 8192,
                    vocabularySize: 32000,
                    eosTokenId: 2,
                    bosTokenId: 1
                ),
                tier: .large,
                category: .others
            ),
            ModelInfo(
                id: "ministral-8b",
                name: "Ministral 8B",
                description: "Mistral社製エッジ特化。英語・多言語・長文生成・構造化応答（JSON等）が得意。Pro Max推奨。",
                descriptionEn: "Mistral's edge model. Strong at English, multilingual, long-form & structured output (JSON). Pro Max.",
                size: "約5GB",
                sizeBytes: 5_000_000_000,
                downloadURL: "https://huggingface.co/bartowski/Ministral-8B-Instruct-2410-GGUF/resolve/main/Ministral-8B-Instruct-2410-Q4_K_M.gguf",
                config: ModelInfo.ModelConfigData(
                    maxContextLength: 131072,
                    vocabularySize: 131072,
                    eosTokenId: 2,
                    bosTokenId: 1
                ),
                tier: .xlarge,
                category: .others
            ),
            ModelInfo(
                id: "yi-1.5-6b",
                name: "Yi 1.5 6B",
                description: "01.AI製。英語・中国語・日本語の多言語対応。会話・要約・コードが得意。Pro推奨。",
                descriptionEn: "By 01.AI. Multilingual (EN/ZH/JA). Good at conversation, summarization & code. Pro recommended.",
                size: "約4GB",
                sizeBytes: 4_000_000_000,
                downloadURL: "https://huggingface.co/bartowski/Yi-1.5-6B-Chat-GGUF/resolve/main/Yi-1.5-6B-Chat-Q4_K_M.gguf",
                config: ModelInfo.ModelConfigData(
                    maxContextLength: 32768,
                    vocabularySize: 64000,
                    eosTokenId: 7,
                    bosTokenId: 1
                ),
                tier: .large,
                category: .others
            ),

            // ==================== ABLITERATED (Uncensored) ====================
            ModelInfo(
                id: "qwen3-4b-abliterated",
                name: "Qwen3 4B Abliterated",
                description: "🔓 制限解除版。huihui-ai製。Pro以上推奨。",
                descriptionEn: "🔓 Uncensored version by huihui-ai. Pro recommended.",
                size: "約2.5GB",
                sizeBytes: 2_500_000_000,
                downloadURL: "https://huggingface.co/DevQuasar/huihui-ai.Qwen3-4B-abliterated-GGUF/resolve/main/huihui-ai.Qwen3-4B-abliterated.Q4_K_M.gguf",
                config: ModelInfo.ModelConfigData(
                    maxContextLength: 40960,
                    vocabularySize: 151936,
                    eosTokenId: 151645,
                    bosTokenId: 151643
                ),
                tier: .large,
                category: .others
            ),
            ModelInfo(
                id: "qwen3-8b-abliterated",
                name: "Qwen3 8B Abliterated",
                description: "🔓 制限解除版。高性能。Pro Max推奨。",
                descriptionEn: "🔓 Uncensored. High performance. Pro Max recommended.",
                size: "約5GB",
                sizeBytes: 5_000_000_000,
                downloadURL: "https://huggingface.co/DevQuasar/huihui-ai.Qwen3-8B-abliterated-GGUF/resolve/main/huihui-ai.Qwen3-8B-abliterated.Q4_K_M.gguf",
                config: ModelInfo.ModelConfigData(
                    maxContextLength: 40960,
                    vocabularySize: 151936,
                    eosTokenId: 151645,
                    bosTokenId: 151643
                ),
                tier: .xlarge,
                category: .others
            ),
            ModelInfo(
                id: "qwen3-8b-erp-jp",
                name: "Qwen3 8B ERP 日本語",
                description: "🇯🇵🔓 日本語RP特化。Aratako製。Pro Max推奨。",
                descriptionEn: "🇯🇵🔓 Japanese RP optimized by Aratako. Pro Max recommended.",
                size: "約5GB",
                sizeBytes: 5_030_000_000,
                downloadURL: "https://huggingface.co/Aratako/Qwen3-8B-ERP-v0.1-GGUF/resolve/main/Qwen3-8B-ERP-v0.1-Q4_K_M.gguf",
                config: ModelInfo.ModelConfigData(
                    maxContextLength: 40960,
                    vocabularySize: 151936,
                    eosTokenId: 151645,
                    bosTokenId: 151643
                ),
                tier: .xlarge,
                category: .others
            ),

            // ==================== LEGACY (旧世代モデル) ====================
            ModelInfo(
                id: "gemma-2-2b",
                name: "Gemma 2 2B",
                description: "📦 旧世代。Gemma 3推奨。",
                descriptionEn: "📦 Legacy. Gemma 3 recommended.",
                size: "約1.6GB",
                sizeBytes: 1_600_000_000,
                downloadURL: "https://huggingface.co/bartowski/gemma-2-2b-it-GGUF/resolve/main/gemma-2-2b-it-Q4_K_M.gguf",
                config: ModelInfo.ModelConfigData(
                    maxContextLength: 8192,
                    vocabularySize: 256000,
                    eosTokenId: 1,
                    bosTokenId: 2
                ),
                tier: .medium,
                category: .others
            ),
            ModelInfo(
                id: "phi-3.5-mini",
                name: "Phi-3.5 Mini",
                description: "📦 旧世代。Phi-4 Mini推奨。",
                descriptionEn: "📦 Legacy. Phi-4 Mini recommended.",
                size: "約2.2GB",
                sizeBytes: 2_200_000_000,
                downloadURL: "https://huggingface.co/bartowski/Phi-3.5-mini-instruct-GGUF/resolve/main/Phi-3.5-mini-instruct-Q4_K_M.gguf",
                config: ModelInfo.ModelConfigData(
                    maxContextLength: 131072,
                    vocabularySize: 32064,
                    eosTokenId: 32000,
                    bosTokenId: 1
                ),
                tier: .medium,
                category: .others
            ),
            ModelInfo(
                id: "llama-3.2-1b",
                name: "Llama 3.2 1B",
                description: "📦 旧世代。Qwen3 1.7B推奨。",
                descriptionEn: "📦 Legacy. Qwen3 1.7B recommended.",
                size: "約700MB",
                sizeBytes: 700_000_000,
                downloadURL: "https://huggingface.co/bartowski/Llama-3.2-1B-Instruct-GGUF/resolve/main/Llama-3.2-1B-Instruct-Q4_K_M.gguf",
                config: ModelInfo.ModelConfigData(
                    maxContextLength: 131072,
                    vocabularySize: 128256,
                    eosTokenId: 128001,
                    bosTokenId: 128000
                ),
                tier: .small,
                category: .others
            ),
            ModelInfo(
                id: "rakuten-2.0-mini",
                name: "Rakuten AI 2.0 mini",
                description: "📦🇯🇵 旧世代。TinySwallow推奨。",
                descriptionEn: "📦🇯🇵 Legacy. TinySwallow recommended.",
                size: "約936MB",
                sizeBytes: 936_000_000,
                downloadURL: "https://huggingface.co/mmnga/RakutenAI-2.0-mini-instruct-gguf/resolve/main/RakutenAI-2.0-mini-instruct-Q4_K_M.gguf",
                config: ModelInfo.ModelConfigData(
                    maxContextLength: 32768,
                    vocabularySize: 151936,
                    eosTokenId: 151645,
                    bosTokenId: 151643
                ),
                tier: .small,
                category: .others
            ),
            ModelInfo(
                id: "japanese-stablelm-2-1.6b",
                name: "Japanese StableLM 2 1.6B",
                description: "📦🇯🇵 旧世代。TinySwallow推奨。",
                descriptionEn: "📦🇯🇵 Legacy. TinySwallow recommended.",
                size: "約1GB",
                sizeBytes: 1_030_000_000,
                downloadURL: "https://huggingface.co/mmnga/japanese-stablelm-2-instruct-1_6b-gguf/resolve/main/japanese-stablelm-2-instruct-1_6b-Q4_K_M.gguf",
                config: ModelInfo.ModelConfigData(
                    maxContextLength: 4096,
                    vocabularySize: 100352,
                    eosTokenId: 100278,
                    bosTokenId: 100257
                ),
                tier: .small,
                category: .others
            ),
            // MARK: - Jan Nano Models
            ModelInfo(
                id: "jan-nano-128k",
                name: "Jan Nano 128K",
                description: "⚡🔥 超軽量・高速！ 128Kコンテキスト対応。",
                descriptionEn: "⚡🔥 Ultra-light and fast! 128K context support.",
                size: "約500MB",
                sizeBytes: 500_000_000,
                downloadURL: "https://huggingface.co/janhq/jan-nano-128k-GGUF/resolve/main/jan-nano-128k-Q4_K_M.gguf",
                config: ModelInfo.ModelConfigData(
                    maxContextLength: 131072,
                    vocabularySize: 151936,
                    eosTokenId: 151645,
                    bosTokenId: 151643
                ),
                tier: .tiny,
                category: .efficient
            ),
            ModelInfo(
                id: "jan-nano-1m",
                name: "Jan Nano 1M",
                description: "⚡🔥 超軽量！ 1Mトークンの超長コンテキスト対応。",
                descriptionEn: "⚡🔥 Ultra-light! 1M token ultra-long context support.",
                size: "約500MB",
                sizeBytes: 500_000_000,
                downloadURL: "https://huggingface.co/janhq/jan-nano-1m-GGUF/resolve/main/jan-nano-1m-Q4_K_M.gguf",
                config: ModelInfo.ModelConfigData(
                    maxContextLength: 1048576,
                    vocabularySize: 151936,
                    eosTokenId: 151645,
                    bosTokenId: 151643
                ),
                tier: .tiny,
                category: .efficient
            )
        ]
    }

    // Get models by category
    func models(for category: ModelCategory) -> [ModelInfo] {
        availableModels.filter { $0.category == category }
    }

    // Calculate total size of downloaded models
    func totalDownloadedSize() -> Int64 {
        let downloadedIds = Set(getDownloadedModels())
        return availableModels
            .filter { downloadedIds.contains($0.id) }
            .reduce(0) { $0 + $1.sizeBytes }
    }

    // Format size in bytes to human readable string
    static func formatSize(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
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

    /// Get all downloaded vision-capable models
    func getDownloadedVisionModels() -> [ModelInfo] {
        let downloadedIds = Set(getDownloadedModels())
        return availableModels.filter { $0.supportsVision && downloadedIds.contains($0.id) }
    }

    /// Get the best vision model for the current device tier
    func getRecommendedVisionModel(for deviceTier: DeviceTier) -> ModelInfo? {
        let visionModels = availableModels.filter { $0.supportsVision && !$0.isTooHeavy(for: deviceTier) }
        // Prefer models that are recommended for this device tier
        if let recommended = visionModels.first(where: { $0.isRecommended(for: deviceTier) }) {
            return recommended
        }
        // Otherwise return the smallest vision model that isn't too heavy
        return visionModels.min(by: { $0.sizeBytes < $1.sizeBytes })
    }

    /// Get all models suitable for a specific device tier
    func getModelsForDeviceTier(_ deviceTier: DeviceTier) -> [ModelInfo] {
        availableModels.filter { !$0.isTooHeavy(for: deviceTier) }
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
        // Check available storage before downloading
        switch StorageChecker.checkStorage(for: model.sizeBytes) {
        case .success:
            break
        case .failure(let error):
            throw error
        }

        // Check if ODR is available for this model
        if OnDemandResourceManager.isODRSupported(for: model.id) {
            try await downloadModelViaODR(model)
            return
        }

        // Fallback to URL Session download
        try await downloadModelViaURLSession(model)
    }

    /// Download model using On-Demand Resources (App Store CDN)
    private func downloadModelViaODR(_ model: ModelInfo) async throws {
        let odrManager = OnDemandResourceManager.shared

        isDownloading = true

        // Re-assign entire dictionary to trigger @Published notification
        var newProgress = downloadProgress
        newProgress[model.id] = 0
        downloadProgress = newProgress

        var newInfo = downloadProgressInfo
        newInfo[model.id] = DownloadProgressInfo(
            progress: 0,
            bytesDownloaded: 0,
            totalBytes: model.sizeBytes,
            speed: 0,
            estimatedTimeRemaining: nil
        )
        downloadProgressInfo = newInfo

        defer {
            isDownloading = false
            // Set progress to 100% before removing (allow UI to update)
            var finalProgress = downloadProgress
            finalProgress[model.id] = 1.0
            downloadProgress = finalProgress

            // Delay removal to allow UI to see 100%
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 second delay
                var newProgress = self.downloadProgress
                newProgress.removeValue(forKey: model.id)
                self.downloadProgress = newProgress

                var newInfo = self.downloadProgressInfo
                newInfo.removeValue(forKey: model.id)
                self.downloadProgressInfo = newInfo
            }
        }

        do {
            // Request ODR resource with progress tracking
            let resourceURL = try await odrManager.requestResource(for: model.id) { [weak self] (progress: Double) in
                Task { @MainActor in
                    guard let self = self else { return }
                    var newProgress = self.downloadProgress
                    newProgress[model.id] = progress
                    self.downloadProgress = newProgress

                    var newInfo = self.downloadProgressInfo
                    newInfo[model.id] = DownloadProgressInfo(
                        progress: progress,
                        bytesDownloaded: Int64(Double(model.sizeBytes) * progress),
                        totalBytes: model.sizeBytes,
                        speed: 0,
                        estimatedTimeRemaining: nil
                    )
                    self.downloadProgressInfo = newInfo
                }
            }

            // Create models directory if needed
            if !fileManager.fileExists(atPath: modelsDirectory.path) {
                try fileManager.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)
            }

            // Copy ODR resource to Documents/Models for persistent access
            let destinationPath = modelsDirectory.appendingPathComponent("\(model.id).gguf")
            if fileManager.fileExists(atPath: destinationPath.path) {
                try fileManager.removeItem(at: destinationPath)
            }
            try fileManager.copyItem(at: resourceURL, to: destinationPath)

            // Release ODR resources (the copy is in Documents now)
            odrManager.endAccessingResources(for: model.id)

        } catch {
            // If ODR fails, try URL Session fallback
            print("ODR download failed: \(error.localizedDescription). Falling back to URL Session.")
            try await downloadModelViaURLSession(model)
        }
    }

    /// Get actual file size using HEAD request (follows redirects)
    private func getActualFileSize(from url: URL) async -> Int64? {
        // Create a session that follows redirects
        let config = URLSessionConfiguration.default
        config.httpShouldSetCookies = false

        // Create a delegate that converts redirects to HEAD requests
        let delegate = HeadRedirectDelegate()
        let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)

        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 15

        do {
            let (_, response) = try await session.data(for: request)
            if let httpResponse = response as? HTTPURLResponse {
                let contentLength = httpResponse.expectedContentLength
                print("[ModelLoader] HEAD request (status: \(httpResponse.statusCode)) - Content-Length: \(contentLength)")
                return contentLength > 0 ? contentLength : nil
            }
        } catch {
            print("[ModelLoader] HEAD request failed: \(error.localizedDescription)")
        }
        return nil
    }

    /// Download model using URL Session (direct HTTP download)
    private func downloadModelViaURLSession(_ model: ModelInfo) async throws {
        guard let url = URL(string: model.downloadURL) else {
            throw ModelLoaderError.invalidURL
        }

        print("[ModelLoader] Starting download for \(model.id) from \(url)")

        isDownloading = true

        // Get actual file size from server (HEAD request) or use model.sizeBytes as fallback
        let actualSize = await getActualFileSize(from: url) ?? model.sizeBytes
        print("[ModelLoader] Using file size: \(actualSize) bytes (model.sizeBytes: \(model.sizeBytes))")

        // Re-assign entire dictionary to trigger @Published notification
        var newProgress = downloadProgress
        newProgress[model.id] = 0
        downloadProgress = newProgress

        // Also re-assign downloadProgressInfo dictionary
        var newInfo = downloadProgressInfo
        newInfo[model.id] = DownloadProgressInfo(
            progress: 0,
            bytesDownloaded: 0,
            totalBytes: actualSize,
            speed: 0,
            estimatedTimeRemaining: nil
        )
        downloadProgressInfo = newInfo
        print("[ModelLoader] Initial progress set for \(model.id) - keys now: \(Array(downloadProgressInfo.keys))")

        defer {
            isDownloading = false
            // Set progress to 100% before removing (allow UI to update)
            var finalProgress = downloadProgress
            finalProgress[model.id] = 1.0
            downloadProgress = finalProgress

            // Delay removal to allow UI to see 100%
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 second delay
                var newProgress = self.downloadProgress
                newProgress.removeValue(forKey: model.id)
                self.downloadProgress = newProgress

                var newInfo = self.downloadProgressInfo
                newInfo.removeValue(forKey: model.id)
                self.downloadProgressInfo = newInfo
            }
        }

        // Create models directory if needed
        if !fileManager.fileExists(atPath: modelsDirectory.path) {
            try fileManager.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)
        }

        // Use URLSessionDownloadTask with delegate for progress
        // Pass actual size for accurate progress calculation
        let (tempURL, _) = try await downloadWithProgress(from: url, modelId: model.id, expectedSize: actualSize)

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

    private func downloadWithProgress(from url: URL, modelId: String, expectedSize: Int64) async throws -> (URL, URLResponse) {
        // Keep a strong reference to the session to prevent deallocation
        var downloadSession: URLSession?

        return try await withCheckedThrowingContinuation { continuation in
            let delegate = DownloadDelegate(
                expectedSize: expectedSize,
                progressHandler: { [weak self] progress, bytesWritten, totalBytes, speed, eta in
                    Task { @MainActor in
                        guard let self = self else { return }

                        if progress >= 0 {
                            // Re-assign entire dictionary to trigger @Published notification
                            var newProgress = self.downloadProgress
                            newProgress[modelId] = progress
                            self.downloadProgress = newProgress

                            var newInfo = self.downloadProgressInfo
                            newInfo[modelId] = DownloadProgressInfo(
                                progress: progress,
                                bytesDownloaded: bytesWritten,
                                totalBytes: totalBytes,
                                speed: speed,
                                estimatedTimeRemaining: eta
                            )
                            self.downloadProgressInfo = newInfo
                        } else {
                            // Indeterminate progress
                            print("[ModelLoader] Indeterminate progress: \(bytesWritten) bytes downloaded")
                        }
                    }
                },
                completionHandler: { result in
                    // Clean up session
                    downloadSession?.invalidateAndCancel()
                    downloadSession = nil

                    switch result {
                    case .success(let tempURL):
                        // Create a dummy response since we don't have access to it here
                        let response = URLResponse(url: url, mimeType: nil, expectedContentLength: Int(expectedSize), textEncodingName: nil)
                        continuation.resume(returning: (tempURL, response))
                    case .failure(let error):
                        continuation.resume(throwing: error)
                    }
                }
            )

            print("[ModelLoader] Starting URLSession download task (delegate-based)...")
            let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
            downloadSession = session

            // Use delegate-based download task (NO completion handler)
            // This ensures didWriteData delegate method gets called
            let task = session.downloadTask(with: url)
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
    private let progressHandler: (Double, Int64, Int64, Double, TimeInterval?) -> Void
    private let completionHandler: (Result<URL, Error>) -> Void
    private let expectedSize: Int64
    private var startTime: Date?
    private var lastUpdateTime: Date?
    private var lastBytesWritten: Int64 = 0
    private var speedSamples: [Double] = []  // 速度のサンプルを保持して平滑化
    private var lastLoggedPercent: Int = -1  // 重複ログ防止

    init(expectedSize: Int64,
         progressHandler: @escaping (Double, Int64, Int64, Double, TimeInterval?) -> Void,
         completionHandler: @escaping (Result<URL, Error>) -> Void) {
        self.expectedSize = expectedSize
        self.progressHandler = progressHandler
        self.completionHandler = completionHandler
        super.init()
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        let now = Date()
        if startTime == nil {
            startTime = now
            lastUpdateTime = now
            // Log first callback with size info
            print("[Download] First callback - serverSize: \(totalBytesExpectedToWrite), expectedSize: \(expectedSize)")
        }

        // Use server-provided size if available, otherwise use expected size from model info
        let totalSize: Int64
        if totalBytesExpectedToWrite > 0 {
            totalSize = totalBytesExpectedToWrite
        } else if expectedSize > 0 {
            totalSize = expectedSize
        } else {
            // Fallback: show indeterminate progress
            print("[Download] No size available - indeterminate progress")
            progressHandler(-1, totalBytesWritten, 0, 0, nil)
            return
        }

        // 速度計算 (直近の間隔から計算)
        let elapsed = now.timeIntervalSince(lastUpdateTime ?? now)
        var currentSpeed: Double = 0
        if elapsed > 0.1 {  // 最低0.1秒間隔で更新
            let bytesInInterval = totalBytesWritten - lastBytesWritten
            currentSpeed = Double(bytesInInterval) / elapsed

            // 速度サンプルを追加 (最大10個で平滑化)
            speedSamples.append(currentSpeed)
            if speedSamples.count > 10 {
                speedSamples.removeFirst()
            }

            lastUpdateTime = now
            lastBytesWritten = totalBytesWritten
        }

        // 平均速度を計算
        let averageSpeed = speedSamples.isEmpty ? 0 : speedSamples.reduce(0, +) / Double(speedSamples.count)

        // 残り時間計算
        let remainingBytes = totalSize - totalBytesWritten
        let eta: TimeInterval? = averageSpeed > 0 ? TimeInterval(remainingBytes) / averageSpeed : nil

        let progress = Double(totalBytesWritten) / Double(totalSize)

        // Log progress every 10% (without duplicates)
        let percentProgress = Int(progress * 100)
        let roundedPercent = (percentProgress / 10) * 10
        if roundedPercent > lastLoggedPercent {
            lastLoggedPercent = roundedPercent
            let mbWritten = Double(totalBytesWritten) / 1_000_000
            let mbTotal = Double(totalSize) / 1_000_000
            let mbps = averageSpeed / 1_000_000
            print("[Download] \(String(format: "%.1f", mbWritten))MB / \(String(format: "%.1f", mbTotal))MB (\(percentProgress)%) - \(String(format: "%.1f", mbps)) MB/s")
        }

        progressHandler(min(progress, 1.0), totalBytesWritten, totalSize, averageSpeed, eta)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        print("[Download] Finished downloading to: \(location.path)")
        // Move to a persistent temp location before returning
        let persistentTemp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        do {
            try FileManager.default.moveItem(at: location, to: persistentTemp)
            completionHandler(.success(persistentTemp))
        } catch {
            completionHandler(.failure(error))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            print("[Download] Completed with error: \(error.localizedDescription)")
            completionHandler(.failure(error))
        }
        // Note: Success case is handled in didFinishDownloadingTo
    }
}

/// Delegate to handle redirects for HEAD requests
/// By default, URLSession converts HEAD to GET on redirects - this preserves HEAD method
private final class HeadRedirectDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        // Create a new HEAD request for the redirect URL
        var newRequest = request
        newRequest.httpMethod = "HEAD"
        print("[ModelLoader] Following redirect to: \(request.url?.host ?? "unknown")...")
        completionHandler(newRequest)
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
    case insufficientStorage(available: Int64, required: Int64)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "無効なURL"
        case .downloadFailed: return "ダウンロードに失敗しました"
        case .extractionFailed: return "展開に失敗しました"
        case .modelNotFound: return "モデルが見つかりません"
        case .configNotFound: return "設定ファイルが見つかりません"
        case .insufficientStorage(let available, let required):
            let availableGB = String(format: "%.1f", Double(available) / 1_000_000_000)
            let requiredGB = String(format: "%.1f", Double(required) / 1_000_000_000)
            return "ストレージが不足しています（残り: \(availableGB) GB、必要: \(requiredGB) GB）"
        }
    }
}

// MARK: - Storage Checker

/// Utility for checking available device storage before model downloads
struct StorageChecker {
    /// Buffer size required beyond the model file itself (500 MB)
    static let requiredBufferBytes: Int64 = 500_000_000

    /// Check available storage on device
    /// - Returns: Available storage in bytes, or nil if unable to determine
    static func availableStorageBytes() -> Int64? {
        let fileManager = FileManager.default
        guard let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return nil
        }

        do {
            let values = try documentsURL.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            if let capacity = values.volumeAvailableCapacityForImportantUsage {
                return capacity
            }
        } catch {
            print("[StorageChecker] Failed to get storage via importantUsage: \(error)")
        }

        // Fallback to older API
        do {
            let values = try documentsURL.resourceValues(forKeys: [.volumeAvailableCapacityKey])
            if let capacity = values.volumeAvailableCapacity {
                return Int64(capacity)
            }
        } catch {
            print("[StorageChecker] Failed to get storage via availableCapacity: \(error)")
        }

        return nil
    }

    /// Check if there is enough storage for a model download
    /// - Parameter modelSizeBytes: Size of the model in bytes
    /// - Returns: A result indicating success or an insufficientStorage error with details
    static func checkStorage(for modelSizeBytes: Int64) -> Result<Void, ModelLoaderError> {
        guard let available = availableStorageBytes() else {
            // If we cannot determine storage, allow the download to proceed
            print("[StorageChecker] Could not determine available storage, allowing download")
            return .success(())
        }

        let required = modelSizeBytes + requiredBufferBytes

        if available >= required {
            print("[StorageChecker] Storage OK: available=\(available / 1_000_000)MB, required=\(required / 1_000_000)MB")
            return .success(())
        } else {
            print("[StorageChecker] Insufficient storage: available=\(available / 1_000_000)MB, required=\(required / 1_000_000)MB")
            return .failure(.insufficientStorage(available: available, required: required))
        }
    }

    /// Format bytes as a human-readable GB string (e.g., "2.5 GB")
    static func formatGB(_ bytes: Int64) -> String {
        String(format: "%.1f GB", Double(bytes) / 1_000_000_000)
    }
}
