import Foundation
import SwiftUI
import Security  // For KeychainManager types

/// Available chat modes for the hybrid AI platform
enum ChatMode: String, CaseIterable, Codable, Identifiable {
    case local = "local"           // On this device
    case chatweb = "chatweb"       // ChatWeb.ai cloud API (fast, no API key needed)
    case privateP2P = "private"    // Nearby permitted/trusted devices
    case fast = "fast"             // Groq API
    case genius = "genius"         // Cloud APIs (OpenAI/Anthropic/Google)
    case publicP2P = "public"      // Anyone's P2P server
    case p2pMesh = "mesh"          // Offline Intelligence Grid - mesh network
    case speculative = "speculative" // Speculative Decoding - Draft + P2P Verification

    var id: String { rawValue }

    /// Display name for UI
    var displayName: String {
        switch self {
        case .local:
            return String(localized: "chatmode.local", defaultValue: "Local")
        case .chatweb:
            return String(localized: "chatmode.chatweb", defaultValue: "chatweb.ai")
        case .privateP2P:
            return String(localized: "chatmode.private", defaultValue: "Private")
        case .fast:
            return String(localized: "chatmode.fast", defaultValue: "Fast")
        case .genius:
            return String(localized: "chatmode.genius", defaultValue: "Genius")
        case .publicP2P:
            return String(localized: "chatmode.public", defaultValue: "Public")
        case .p2pMesh:
            return String(localized: "chatmode.mesh", defaultValue: "Mesh")
        case .speculative:
            return String(localized: "chatmode.speculative", defaultValue: "Speculative")
        }
    }

    /// Detailed description
    var description: String {
        switch self {
        case .local:
            return String(localized: "chatmode.local.desc", defaultValue: "完全無料 • 完全プライベート • オフライン対応")
        case .chatweb:
            return String(localized: "chatmode.chatweb.desc", defaultValue: "無料 • 通信完全暗号化 • Pro: 学習拒否モード対応")
        case .privateP2P:
            return String(localized: "chatmode.private.desc", defaultValue: "無料 • 信頼済みデバイスのみ • LAN内暗号化")
        case .fast:
            return String(localized: "chatmode.fast.desc", defaultValue: "1トークン • Groq超高速推論")
        case .genius:
            return String(localized: "chatmode.genius.desc", defaultValue: "5トークン • GPT-4o/Claude/Gemini最高品質")
        case .publicP2P:
            return String(localized: "chatmode.public.desc", defaultValue: "無料〜2トークン • 一般的に安全 • コミュニティ共有")
        case .p2pMesh:
            return String(localized: "chatmode.mesh.desc", defaultValue: "無料 • オフライン対応 • メッシュネットワーク")
        case .speculative:
            return String(localized: "chatmode.speculative.desc", defaultValue: "2トークン • ローカル下書き+P2P検証で超高速")
        }
    }

    /// Security level description
    var securityInfo: String {
        switch self {
        case .local:
            return "完全プライベート — データは一切外部に送信されません"
        case .chatweb:
            return "通信は完全に暗号化されます。Proプラン以上で学習拒否モードをONにできます"
        case .privateP2P:
            return "信頼済みデバイス間のLAN内通信。暗号化されています"
        case .fast:
            return "Groq APIへ暗号化通信。Groqのプライバシーポリシーに準拠"
        case .genius:
            return "各プロバイダへ暗号化通信。プロバイダのプライバシーポリシーに準拠"
        case .publicP2P:
            return "一般的に安全ですが、完全なプライバシー保護は保証されません"
        case .p2pMesh:
            return "ローカルメッシュネットワーク内。一般的に安全です"
        case .speculative:
            return "ローカル下書き（プライベート）+ P2P検証（一般的に安全）"
        }
    }

    /// Token cost per message
    var tokenCost: Int {
        switch self {
        case .local: return 0
        case .chatweb: return 0     // Free via ChatWeb.ai credits
        case .privateP2P: return 0  // Free for trusted devices
        case .fast: return 1
        case .genius: return 5
        case .publicP2P: return 2
        case .p2pMesh: return 0     // Free - community-powered
        case .speculative: return 2 // Draft (free) + P2P (2 tokens)
        }
    }

    /// Icon for the mode
    var icon: String {
        switch self {
        case .local: return "iphone"
        case .chatweb: return "cloud.fill"
        case .privateP2P: return "lock.shield.fill"
        case .fast: return "bolt.fill"
        case .genius: return "sparkles"
        case .publicP2P: return "globe"
        case .p2pMesh: return "network"
        case .speculative: return "bolt.trianglebadge.exclamationmark"
        }
    }

    /// Color associated with the mode
    var color: Color {
        switch self {
        case .local: return .green
        case .chatweb: return .indigo
        case .privateP2P: return .cyan
        case .fast: return .orange
        case .genius: return .purple
        case .publicP2P: return .blue
        case .p2pMesh: return .mint
        case .speculative: return .yellow
        }
    }

    /// Whether this mode requires network
    var requiresNetwork: Bool {
        switch self {
        case .local, .p2pMesh: return false  // Mesh can work offline
        case .chatweb, .privateP2P, .fast, .genius, .publicP2P: return true
        case .speculative: return false  // Uses local draft + P2P (can fallback to local)
        }
    }

    /// Whether this mode requires an API key
    var requiresAPIKey: Bool {
        switch self {
        case .local, .chatweb, .privateP2P, .publicP2P, .p2pMesh, .speculative: return false
        case .fast, .genius: return true
        }
    }

    /// Whether this mode uses P2P connection
    var isP2P: Bool {
        switch self {
        case .privateP2P, .publicP2P, .p2pMesh, .speculative: return true
        case .local, .chatweb, .fast, .genius: return false
        }
    }
}

/// Cloud provider options for Genius mode
enum CloudProvider: String, CaseIterable, Codable, Identifiable {
    case openai = "openai"
    case anthropic = "anthropic"
    case google = "google"
    case openrouter = "openrouter"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .openai: return "OpenAI (GPT-4o)"
        case .anthropic: return "Anthropic (Claude 3.5)"
        case .google: return "Google (Gemini 1.5)"
        case .openrouter: return "OpenRouter (200+ models)"
        }
    }

    var icon: String {
        switch self {
        case .openai: return "brain"
        case .anthropic: return "sparkles"
        case .google: return "globe"
        case .openrouter: return "arrow.triangle.branch"
        }
    }

    /// Default model ID for each provider
    var defaultModel: String {
        switch self {
        case .openai: return "gpt-4o"
        case .anthropic: return "claude-3-5-sonnet-20241022"
        case .google: return "gemini-1.5-pro"
        case .openrouter: return "anthropic/claude-3.5-sonnet"
        }
    }

    /// API endpoint base URL
    var baseURL: String {
        switch self {
        case .openai: return "https://api.openai.com/v1"
        case .anthropic: return "https://api.anthropic.com/v1"
        case .google: return "https://generativelanguage.googleapis.com/v1beta"
        case .openrouter: return "https://openrouter.ai/api/v1"
        }
    }

    /// Corresponding API key provider
    var apiKeyProvider: APIKeyProvider {
        switch self {
        case .openai: return .openai
        case .anthropic: return .anthropic
        case .google: return .google
        case .openrouter: return .openrouter
        }
    }
}
