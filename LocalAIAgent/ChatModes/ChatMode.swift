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
            return String(localized: "chatmode.local.desc", defaultValue: "On-device • Free • Private")
        case .chatweb:
            return String(localized: "chatmode.chatweb.desc", defaultValue: "クラウドを使って色々なLLMを最速で比較できます")
        case .privateP2P:
            return String(localized: "chatmode.private.desc", defaultValue: "Trusted devices • Your network")
        case .fast:
            return String(localized: "chatmode.fast.desc", defaultValue: "Groq API • Super fast")
        case .genius:
            return String(localized: "chatmode.genius.desc", defaultValue: "GPT-5/Claude • Best quality")
        case .publicP2P:
            return String(localized: "chatmode.public.desc", defaultValue: "Community • Shared computing")
        case .p2pMesh:
            return String(localized: "chatmode.mesh.desc", defaultValue: "Offline Grid • Community mesh network")
        case .speculative:
            return String(localized: "chatmode.speculative.desc", defaultValue: "Ultra-fast • Draft + P2P Verification")
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

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .openai: return "OpenAI (GPT-4o)"
        case .anthropic: return "Anthropic (Claude 3.5)"
        case .google: return "Google (Gemini 1.5)"
        }
    }

    var icon: String {
        switch self {
        case .openai: return "brain"
        case .anthropic: return "sparkles"
        case .google: return "globe"
        }
    }

    /// Default model ID for each provider
    var defaultModel: String {
        switch self {
        case .openai: return "gpt-4o"
        case .anthropic: return "claude-3-5-sonnet-20241022"
        case .google: return "gemini-1.5-pro"
        }
    }

    /// API endpoint base URL
    var baseURL: String {
        switch self {
        case .openai: return "https://api.openai.com/v1"
        case .anthropic: return "https://api.anthropic.com/v1"
        case .google: return "https://generativelanguage.googleapis.com/v1beta"
        }
    }

    /// Corresponding API key provider
    var apiKeyProvider: APIKeyProvider {
        switch self {
        case .openai: return .openai
        case .anthropic: return .anthropic
        case .google: return .google
        }
    }
}
