//
//  ChatWebAPIKeyManager.swift
//  LocalAIAgent
//
//  Device API key lifecycle management for ChatWeb authentication
//

import Foundation
import SwiftUI

enum ChatWebAPIKeyError: LocalizedError {
    case registrationFailed(Int)
    case networkError(Error)
    case keychainError(Error)
    case invalidResponse
    case rateLimited

    var errorDescription: String? {
        switch self {
        case .registrationFailed(let code):
            return "デバイス登録に失敗しました (コード: \(code))"
        case .networkError(let error):
            return "ネットワークエラー: \(error.localizedDescription)"
        case .keychainError(let error):
            return "Keychainエラー: \(error.localizedDescription)"
        case .invalidResponse:
            return "サーバーからの無効なレスポンス"
        case .rateLimited:
            return "リクエストが多すぎます。しばらく待ってから再試行してください"
        }
    }
}

@MainActor
final class ChatWebAPIKeyManager: ObservableObject {
    static let shared = ChatWebAPIKeyManager()

    @Published private(set) var apiKey: String?
    @Published private(set) var keyStatus: KeyStatus = .unknown
    @Published private(set) var lastError: ChatWebAPIKeyError?

    enum KeyStatus {
        case unknown
        case valid
        case expired
        case invalid
        case generating
    }

    private let registerURL = "https://api.chatweb.ai/api/v1/devices/register"

    private init() {}

    /// Initialize device API key (call on app launch)
    func initialize() async throws {
        // Check if key already exists in Keychain
        if let existingKey = KeychainManager.shared.getDeviceAPIKey() {
            apiKey = existingKey
            keyStatus = .valid

            // Validate in background
            Task {
                await validateKey()
            }
            return
        }

        // Generate new key
        try await generateKey()
    }

    /// Generate a new device API key
    private func generateKey() async throws {
        keyStatus = .generating

        do {
            let newKey = try await registerDevice()

            // Store in Keychain
            try KeychainManager.shared.setDeviceAPIKey(newKey)

            apiKey = newKey
            keyStatus = .valid
            lastError = nil

            // Haptic feedback
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)

        } catch {
            keyStatus = .invalid
            lastError = error as? ChatWebAPIKeyError ?? .networkError(error)
            throw error
        }
    }

    /// Register device with backend and get API key
    private func registerDevice() async throws -> String {
        var request = URLRequest(url: URL(string: registerURL)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let fingerprint = DeviceIdentityManager.shared.deviceFingerprint
        let body: [String: Any] = [
            "device_id": fingerprint.deviceId,
            "device_info": [
                "model": fingerprint.model,
                "os_version": fingerprint.osVersion,
                "app_version": fingerprint.appVersion,
                "locale": fingerprint.locale
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ChatWebAPIKeyError.invalidResponse
        }

        guard httpResponse.statusCode == 200 || httpResponse.statusCode == 201 else {
            if httpResponse.statusCode == 429 {
                throw ChatWebAPIKeyError.rateLimited
            }
            throw ChatWebAPIKeyError.registrationFailed(httpResponse.statusCode)
        }

        struct RegisterResponse: Codable {
            let api_key: String
            let device_id: String
            let status: String?
        }

        let result = try JSONDecoder().decode(RegisterResponse.self, from: data)

        // Log success (without full key)
        print("[ChatWebAPIKey] Device registered: \(result.api_key.prefix(12))...")

        return result.api_key
    }

    /// Validate current API key
    func validateKey() async -> Bool {
        guard let apiKey = apiKey else { return false }

        let url = URL(string: "https://api.chatweb.ai/api/v1/auth/me")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse {
                keyStatus = httpResponse.statusCode == 200 ? .valid : .invalid
                return httpResponse.statusCode == 200
            }
        } catch {
            keyStatus = .invalid
            lastError = .networkError(error)
        }

        return false
    }

    /// Regenerate API key (delete old, generate new)
    func regenerateKey() async throws {
        // Delete old key
        try? KeychainManager.shared.deleteDeviceAPIKey()
        apiKey = nil

        // Generate new key
        try await generateKey()
    }

    /// Delete API key
    func deleteKey() throws {
        try KeychainManager.shared.deleteDeviceAPIKey()
        apiKey = nil
        keyStatus = .unknown
        lastError = nil
    }
}
