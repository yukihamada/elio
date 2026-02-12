import Foundation
import Security

/// Secure storage for API keys using iOS Keychain
final class KeychainManager {
    static let shared = KeychainManager()

    private let service = "love.elio.LocalAIAgent"

    private init() {}

    // MARK: - API Key Storage

    /// Store an API key for a provider
    func setAPIKey(_ key: String, for provider: APIKeyProvider) throws {
        let data = key.data(using: .utf8)!

        // Delete existing key first
        try? deleteAPIKey(for: provider)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: provider.keychainKey,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.unableToStore(status)
        }
    }

    /// Retrieve an API key for a provider
    func getAPIKey(for provider: APIKeyProvider) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: provider.keychainKey,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let key = String(data: data, encoding: .utf8) else {
            return nil
        }

        return key
    }

    /// Delete an API key for a provider
    func deleteAPIKey(for provider: APIKeyProvider) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: provider.keychainKey
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unableToDelete(status)
        }
    }

    /// Check if an API key exists for a provider
    func hasAPIKey(for provider: APIKeyProvider) -> Bool {
        getAPIKey(for: provider) != nil
    }
}

// MARK: - API Key Providers

enum APIKeyProvider: String, CaseIterable, Identifiable {
    case groq = "groq"
    case openai = "openai"
    case anthropic = "anthropic"
    case google = "google"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .groq: return "Groq"
        case .openai: return "OpenAI"
        case .anthropic: return "Anthropic"
        case .google: return "Google AI"
        }
    }

    var keychainKey: String {
        "apikey_\(rawValue)"
    }

    var placeholder: String {
        switch self {
        case .groq: return "gsk_..."
        case .openai: return "sk-..."
        case .anthropic: return "sk-ant-..."
        case .google: return "AIza..."
        }
    }

    var helpURL: URL? {
        switch self {
        case .groq: return URL(string: "https://console.groq.com/keys")
        case .openai: return URL(string: "https://platform.openai.com/api-keys")
        case .anthropic: return URL(string: "https://console.anthropic.com/settings/keys")
        case .google: return URL(string: "https://aistudio.google.com/app/apikey")
        }
    }
}

// MARK: - Keychain Errors

enum KeychainError: Error, LocalizedError {
    case unableToStore(OSStatus)
    case unableToDelete(OSStatus)
    case itemNotFound

    var errorDescription: String? {
        switch self {
        case .unableToStore(let status):
            return "Failed to store item: \(status)"
        case .unableToDelete(let status):
            return "Failed to delete item: \(status)"
        case .itemNotFound:
            return "Item not found"
        }
    }
}
