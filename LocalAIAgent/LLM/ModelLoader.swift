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
        let sizeBytes: Int64  // Exact size in bytes for total calculation
        let downloadURL: String
        let config: ModelConfigData
        let tier: ModelTier
        let category: ModelCategory
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
            sizeBytes: Int64 = 0,
            downloadURL: String,
            config: ModelConfigData,
            tier: ModelTier,
            category: ModelCategory = .others,
            supportsVision: Bool = false
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
                id: "qwen3-0.6b",
                name: "Qwen3 0.6B",
                description: "超軽量・高速。全デバイス対応。",
                descriptionEn: "Ultra-light and fast. Works on all devices.",
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
                description: "軽量でバランスの良い性能。",
                descriptionEn: "Lightweight with balanced performance.",
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
                description: "高性能モデル。Pro以上推奨。",
                descriptionEn: "High performance. Pro or higher recommended.",
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
                description: "最高性能。Pro Max推奨。",
                descriptionEn: "Best performance. Pro Max recommended.",
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
            ModelInfo(
                id: "gemma-3-1b",
                name: "Gemma 3 1B",
                description: "Google最新。超軽量で高速。",
                descriptionEn: "Latest Google. Ultra-light and fast.",
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
                description: "Google最新。バランス良好。Pro推奨。",
                descriptionEn: "Latest Google. Well balanced. Pro recommended.",
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
                id: "tinyswallow-1.5b",
                name: "TinySwallow 1.5B",
                description: "🇯🇵 Sakana AI製。日本語特化の高品質モデル。",
                descriptionEn: "🇯🇵 By Sakana AI. High-quality Japanese-optimized model.",
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
                category: .japanese
            ),
            ModelInfo(
                id: "elyza-llama3-8b",
                name: "ELYZA Llama 3 8B",
                description: "🇯🇵 東大松尾研発。日本語チャット最高峰。Pro Max推奨。",
                descriptionEn: "🇯🇵 By UTokyo Matsuo Lab. Top Japanese chat. Pro Max recommended.",
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
                category: .japanese
            ),
            ModelInfo(
                id: "swallow-8b",
                name: "Llama 3.1 Swallow 8B",
                description: "🇯🇵 東工大など製。日本知識豊富。ビジネス文書に強い。Pro Max推奨。",
                descriptionEn: "🇯🇵 By Tokyo Tech. Rich Japanese knowledge. Pro Max recommended.",
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
                category: .japanese
            ),

            // ==================== EFFICIENT (Small but powerful) ====================
            ModelInfo(
                id: "lfm2-1.2b",
                name: "LFM2 1.2B",
                description: "⚡ Liquid AI製。Gemma超え性能。超高効率。",
                descriptionEn: "⚡ By Liquid AI. Outperforms Gemma. Ultra-efficient.",
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
                description: "⚡ 超軽量ながらQwen3-0.6B並みの性能。",
                descriptionEn: "⚡ Ultra-light but rivals Qwen3-0.6B performance.",
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
                description: "📷 最新Qwen3ベースの画像認識。軽量で全デバイス対応。",
                descriptionEn: "📷 Latest Qwen3-based vision. Light, works on all devices.",
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
                description: "📷 バランス良好な画像認識。Pro以上推奨。",
                descriptionEn: "📷 Well-balanced vision model. Pro or higher recommended.",
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
                description: "📷 最高性能の画像認識。Pro Max推奨。",
                descriptionEn: "📷 Best vision performance. Pro Max recommended.",
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
                description: "📷 軽量画像認識モデル。",
                descriptionEn: "📷 Lightweight vision model.",
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
                description: "Meta製。バランス良好。",
                descriptionEn: "By Meta. Well balanced.",
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
                description: "高度な推論能力。軽量版。",
                descriptionEn: "Advanced reasoning. Lightweight.",
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
                description: "高い推論性能。Pro推奨。",
                descriptionEn: "High reasoning performance. Pro recommended.",
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
                description: "最高の推論性能。Pro Max推奨。",
                descriptionEn: "Best reasoning performance. Pro Max recommended.",
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
                description: "モバイル特化。自然な応答。",
                descriptionEn: "Mobile optimized. Natural responses.",
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
                description: "Mistral社のエッジ向けモデル。Pro Max推奨。",
                descriptionEn: "Mistral's edge-optimized model. Pro Max recommended.",
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
                description: "01.AI製。6Bサイズで高性能。",
                descriptionEn: "By 01.AI. High performance at 6B size.",
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
        // Pass expected size from model info for accurate progress when Content-Length is missing
        let (tempURL, _) = try await downloadWithProgress(from: url, modelId: model.id, expectedSize: model.sizeBytes)

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
        try await withCheckedThrowingContinuation { continuation in
            let delegate = DownloadDelegate(expectedSize: expectedSize) { [weak self] progress, bytesWritten, totalBytes in
                Task { @MainActor in
                    if progress >= 0 {
                        self?.downloadProgress[modelId] = progress
                    }
                    // Log progress for debugging
                    #if DEBUG
                    let mbWritten = Double(bytesWritten) / 1_000_000
                    let mbTotal = Double(totalBytes) / 1_000_000
                    if Int(mbWritten) % 50 == 0 {
                        print("Download progress: \(String(format: "%.1f", mbWritten))MB / \(String(format: "%.1f", mbTotal))MB (\(Int(progress * 100))%)")
                    }
                    #endif
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
    private let progressHandler: (Double, Int64, Int64) -> Void
    private let expectedSize: Int64

    init(expectedSize: Int64, progressHandler: @escaping (Double, Int64, Int64) -> Void) {
        self.expectedSize = expectedSize
        self.progressHandler = progressHandler
        super.init()
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        // Use server-provided size if available, otherwise use expected size from model info
        let totalSize: Int64
        if totalBytesExpectedToWrite > 0 {
            totalSize = totalBytesExpectedToWrite
        } else if expectedSize > 0 {
            totalSize = expectedSize
        } else {
            // Fallback: show indeterminate progress
            progressHandler(-1, totalBytesWritten, 0)
            return
        }

        let progress = Double(totalBytesWritten) / Double(totalSize)
        progressHandler(min(progress, 1.0), totalBytesWritten, totalSize)
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
