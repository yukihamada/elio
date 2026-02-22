import Foundation
import Combine

// MARK: - API Response Types

struct ServerConversation: Codable {
    let id: String
    let title: String
    let updatedAt: String?
    let messageCount: Int?
    let lastMessagePreview: String?

    enum CodingKeys: String, CodingKey {
        case id, title
        case updatedAt = "updated_at"
        case messageCount = "message_count"
        case lastMessagePreview = "last_message_preview"
    }
}

struct SyncListResponse: Codable {
    let conversations: [ServerConversation]
    let syncToken: String?

    enum CodingKeys: String, CodingKey {
        case conversations
        case syncToken = "sync_token"
    }
}

struct SyncConversationMessage: Codable {
    let role: String
    let content: String
    let timestamp: String?
}

struct SyncConversationDetail: Codable {
    let conversationId: String
    let title: String
    let messages: [SyncConversationMessage]

    enum CodingKeys: String, CodingKey {
        case conversationId = "conversation_id"
        case title, messages
    }
}

struct SyncPushSyncedItem: Codable {
    let clientId: String
    let serverId: String

    enum CodingKeys: String, CodingKey {
        case clientId = "client_id"
        case serverId = "server_id"
    }
}

struct SyncPushResponse: Codable {
    let synced: [SyncPushSyncedItem]
}

struct LoginResponse: Codable {
    let ok: Bool
    let token: String?
    let userId: String?
    let email: String?

    enum CodingKeys: String, CodingKey {
        case ok, token, email
        case userId = "user_id"
    }
}

struct AuthMeResponse: Codable {
    let authenticated: Bool
    let userId: String?
    let email: String?
    let creditsRemaining: Int?
    let creditsUsed: Int?
    let plan: String?

    enum CodingKeys: String, CodingKey {
        case authenticated
        case userId = "user_id"
        case email
        case creditsRemaining = "credits_remaining"
        case creditsUsed = "credits_used"
        case plan
    }
}

// MARK: - SyncManager

/// Manages ElioChat ↔ chatweb.ai account linking and conversation sync
@MainActor
class SyncManager: ObservableObject {
    @Published var isLoggedIn = false
    @Published var isSyncing = false
    @Published var email = ""
    @Published var creditsRemaining = 0
    @Published var plan = "free"
    @Published var lastSyncDate: Date?
    @Published var syncError: String?

    /// Selected ChatWeb model ID (persisted). nil or "auto" = server default.
    @Published var selectedChatWebModel: String? {
        didSet {
            UserDefaults.standard.set(selectedChatWebModel, forKey: "chatweb_selected_model")
        }
    }

    /// Last model actually used by the server (from `done` event)
    @Published var lastModelUsed: String?

    /// Auth token — stored in Keychain, exposed for ChatWebBackend
    private(set) var authToken: String?

    /// User ID from login response — used for API calls that need explicit user identification
    private(set) var userId: String?

    /// Singleton for access from non-environment contexts (e.g. SubscriptionManager)
    static let shared = SyncManager()

    let baseURL = "https://chatweb.ai"

    private let keychainService = "love.elio.LocalAIAgent"
    private let keychainAccount = "chatweb_auth_token"
    private let lastSyncTokenKey = "chatweb_last_sync_token"

    private var creditUpdateCancellable: AnyCancellable?

    init() {
        // Restore token from Keychain
        if let token = loadTokenFromKeychain() {
            authToken = token
            isLoggedIn = true
        }

        // Restore selected model
        selectedChatWebModel = UserDefaults.standard.string(forKey: "chatweb_selected_model")

        // Listen for real-time credit updates from ChatWebBackend SSE `done` events
        creditUpdateCancellable = NotificationCenter.default
            .publisher(for: .chatWebCreditsUpdated)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                guard let self else { return }
                if let credits = notification.userInfo?["credits_remaining"] as? Int {
                    self.creditsRemaining = credits
                }
                if let model = notification.userInfo?["model_used"] as? String {
                    self.lastModelUsed = model
                }
            }
    }

    // MARK: - Real-time Credit Update

    /// Update credits directly from a ChatWeb `done` event without an API call.
    /// Called by the backend or notification observer.
    func updateCreditsFromEvent(credits: Int, modelUsed: String? = nil) {
        creditsRemaining = credits
        if let model = modelUsed {
            lastModelUsed = model
        }
    }

    /// Display-friendly plan name
    var planDisplayName: String {
        switch plan.lowercased() {
        case "starter": return "Starter"
        case "pro": return "Pro"
        default: return "Free"
        }
    }

    // MARK: - Auth

    /// Login with email and password
    func login(email: String, password: String) async throws {
        let url = URL(string: "\(baseURL)/api/v1/auth/login")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Elio Chat iOS", forHTTPHeaderField: "User-Agent")

        let body: [String: Any] = [
            "email": email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
            "password": password,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw SyncError.invalidResponse
        }

        if httpResponse.statusCode == 401 {
            throw SyncError.invalidCredentials
        }

        if httpResponse.statusCode == 429 {
            throw SyncError.rateLimited
        }

        guard httpResponse.statusCode == 200 else {
            throw SyncError.serverError(httpResponse.statusCode)
        }

        let loginResponse = try JSONDecoder().decode(LoginResponse.self, from: data)
        guard loginResponse.ok, let token = loginResponse.token else {
            throw SyncError.invalidCredentials
        }

        // Save token and userId
        authToken = token
        userId = loginResponse.userId
        saveTokenToKeychain(token)

        self.email = loginResponse.email ?? email
        isLoggedIn = true

        // Fetch account info
        try? await fetchMe()
    }

    /// Logout and clear all state
    func logout() {
        authToken = nil
        userId = nil
        deleteTokenFromKeychain()
        isLoggedIn = false
        email = ""
        creditsRemaining = 0
        plan = "free"
        lastSyncDate = nil
        syncError = nil
        lastModelUsed = nil
        selectedChatWebModel = nil
        UserDefaults.standard.removeObject(forKey: lastSyncTokenKey)
        UserDefaults.standard.removeObject(forKey: "chatweb_selected_model")
    }

    /// Fetch current user info (credits, plan)
    func fetchMe() async throws {
        guard let token = authToken else { throw SyncError.notAuthenticated }

        let url = URL(string: "\(baseURL)/api/v1/auth/me")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("Elio Chat iOS", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw SyncError.serverError((response as? HTTPURLResponse)?.statusCode ?? 0)
        }

        let me = try JSONDecoder().decode(AuthMeResponse.self, from: data)
        if me.authenticated {
            email = me.email ?? email
            creditsRemaining = me.creditsRemaining ?? 0
            plan = me.plan ?? "free"
        } else {
            // Token expired
            logout()
            throw SyncError.tokenExpired
        }
    }

    // MARK: - Sync Operations

    /// Pull conversation list from server
    /// Respects sync disabled setting when active.
    func pullConversations(since: String? = nil) async throws -> [ServerConversation] {
        // Do not sync when sync is disabled
        if ChatModeManager.shared.isSyncDisabled {
            return []
        }
        guard let token = authToken else { throw SyncError.notAuthenticated }

        var urlString = "\(baseURL)/api/v1/sync/conversations"
        let syncSince = since ?? UserDefaults.standard.string(forKey: lastSyncTokenKey)
        if let s = syncSince {
            urlString += "?since=\(s)"
        }

        let url = URL(string: urlString)!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("Elio Chat iOS", forHTTPHeaderField: "User-Agent")

        isSyncing = true
        defer { isSyncing = false }

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw SyncError.serverError((response as? HTTPURLResponse)?.statusCode ?? 0)
        }

        let syncResponse = try JSONDecoder().decode(SyncListResponse.self, from: data)

        // Save sync token for next incremental pull
        if let syncToken = syncResponse.syncToken {
            UserDefaults.standard.set(syncToken, forKey: lastSyncTokenKey)
        }

        lastSyncDate = Date()
        syncError = nil
        return syncResponse.conversations
    }

    /// Get full messages for a specific conversation
    func getConversation(id: String) async throws -> SyncConversationDetail {
        guard let token = authToken else { throw SyncError.notAuthenticated }

        let url = URL(string: "\(baseURL)/api/v1/sync/conversations/\(id)")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("Elio Chat iOS", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw SyncError.serverError((response as? HTTPURLResponse)?.statusCode ?? 0)
        }

        return try JSONDecoder().decode(SyncConversationDetail.self, from: data)
    }

    /// Push local conversations to server
    /// Respects sync disabled setting when active.
    func pushConversations(_ conversations: [Conversation]) async throws -> [SyncPushSyncedItem] {
        // Do not sync when sync is disabled
        if ChatModeManager.shared.isSyncDisabled {
            return []
        }
        guard let token = authToken else { throw SyncError.notAuthenticated }

        let url = URL(string: "\(baseURL)/api/v1/sync/push")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("Elio Chat iOS", forHTTPHeaderField: "User-Agent")

        let payload = Self.buildPushPayload(for: conversations)
        let body: [String: Any] = ["conversations": payload]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        isSyncing = true
        defer { isSyncing = false }

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw SyncError.serverError((response as? HTTPURLResponse)?.statusCode ?? 0)
        }

        let pushResponse = try JSONDecoder().decode(SyncPushResponse.self, from: data)
        return pushResponse.synced
    }

    // MARK: - Helpers

    /// Convert local Conversations to push payload format
    static func buildPushPayload(for conversations: [Conversation]) -> [[String: Any]] {
        conversations.map { conv in
            let messages: [[String: Any]] = conv.messages
                .filter { $0.role == .user || $0.role == .assistant }
                .map { msg in
                    var m: [String: Any] = [
                        "role": msg.role.rawValue,
                        "content": msg.content,
                    ]
                    let formatter = ISO8601DateFormatter()
                    m["timestamp"] = formatter.string(from: msg.timestamp)
                    return m
                }
            return [
                "client_id": conv.id.uuidString,
                "title": conv.title,
                "messages": messages,
            ] as [String: Any]
        }
    }

    // MARK: - Keychain

    private func saveTokenToKeychain(_ token: String) {
        let data = token.data(using: .utf8)!

        // Delete existing
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        // Add new
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        SecItemAdd(addQuery as CFDictionary, nil)
    }

    private func loadTokenFromKeychain() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let token = String(data: data, encoding: .utf8) else {
            return nil
        }
        return token
    }

    private func deleteTokenFromKeychain() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - Errors

enum SyncError: Error, LocalizedError {
    case notAuthenticated
    case invalidCredentials
    case tokenExpired
    case rateLimited
    case invalidResponse
    case serverError(Int)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return String(localized: "sync.error.not_authenticated", defaultValue: "Not logged in to chatweb.ai")
        case .invalidCredentials:
            return String(localized: "sync.error.invalid_credentials", defaultValue: "Invalid email or password")
        case .tokenExpired:
            return String(localized: "sync.error.token_expired", defaultValue: "Session expired. Please log in again.")
        case .rateLimited:
            return String(localized: "sync.error.rate_limited", defaultValue: "Too many requests. Please try again later.")
        case .invalidResponse:
            return String(localized: "sync.error.invalid_response", defaultValue: "Invalid server response")
        case .serverError(let code):
            return String(localized: "sync.error.server", defaultValue: "Server error (\(code))")
        }
    }
}
