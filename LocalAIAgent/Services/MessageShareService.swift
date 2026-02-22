import Foundation
import UIKit
import CryptoKit

/// Service for sharing conversation messages via elio.love/s/{id}#key links.
/// Messages are encrypted client-side with AES-256-GCM before upload.
/// The decryption key is embedded in the URL fragment (never sent to server).
@MainActor
final class MessageShareService: ObservableObject {
    static let shared = MessageShareService()

    @Published var isSharing = false
    @Published var lastError: String?

    private let shareEndpoint = "https://api.elio.love/api/v1/share"

    private init() {}

    // MARK: - Public API

    /// Share a conversation up to (and including) the specified message index
    /// - Returns: The share URL with encryption key in fragment, or nil on failure
    func shareMessage(
        conversation: Conversation,
        upToMessageIndex: Int,
        modelName: String?
    ) async -> URL? {
        isSharing = true
        lastError = nil
        defer { isSharing = false }

        // Build messages (user and assistant only)
        let messagesToShare = Array(conversation.messages.prefix(upToMessageIndex + 1))
            .filter { $0.role == .user || $0.role == .assistant }

        guard !messagesToShare.isEmpty else {
            lastError = "No messages to share"
            return nil
        }

        // Find highlighted index after filtering
        let targetMessage = conversation.messages[upToMessageIndex]
        let sharedIndex = messagesToShare.lastIndex(where: { $0.id == targetMessage.id }) ?? (messagesToShare.count - 1)

        // Build plaintext payload
        let shareMessages: [[String: String]] = messagesToShare.map { msg in
            [
                "role": msg.role.rawValue,
                "content": msg.content,
                "timestamp": ISO8601DateFormatter().string(from: msg.timestamp)
            ]
        }

        let payload: [String: Any] = [
            "title": conversation.title,
            "messages": shareMessages,
            "model_name": modelName ?? ""
        ]

        do {
            let plaintext = try JSONSerialization.data(withJSONObject: payload)

            // Encrypt with AES-256-GCM
            let key = SymmetricKey(size: .bits256)
            let nonce = AES.GCM.Nonce()
            let sealed = try AES.GCM.seal(plaintext, using: key, nonce: nonce)

            guard let combined = sealed.combined else {
                lastError = "Encryption failed"
                return nil
            }

            // Encode for transport
            // combined = nonce(12) + ciphertext + tag(16) — nonce embedded, no separate IV needed
            let encryptedData = combined.base64EncodedString()
            let keyData = key.withUnsafeBytes { Data($0) }
            let keyB64 = base64UrlEncode(keyData)

            // Send encrypted data to API
            let body: [String: Any] = [
                "encrypted_data": encryptedData,
                "shared_message_index": sharedIndex,
                "message_count": messagesToShare.count
            ]

            let jsonData = try JSONSerialization.data(withJSONObject: body)

            guard let url = URL(string: shareEndpoint) else {
                lastError = "Invalid endpoint URL"
                return nil
            }

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("ElioChat-iOS", forHTTPHeaderField: "User-Agent")
            request.httpBody = jsonData
            request.timeoutInterval = 30

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                lastError = "Server error"
                return nil
            }

            guard let result = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let ok = result["ok"] as? Bool, ok,
                  let urlString = result["url"] as? String else {
                lastError = "Invalid response"
                return nil
            }

            // Append encryption key as URL fragment (never sent to server)
            let shareURL = URL(string: urlString + "#" + keyB64)
            return shareURL

        } catch {
            lastError = error.localizedDescription
            print("[MessageShareService] Error: \(error)")
            return nil
        }
    }

    /// Present a share sheet with the given URL
    func presentShareSheet(url: URL) {
        let activityVC = UIActivityViewController(
            activityItems: [url],
            applicationActivities: nil
        )
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first,
           let rootVC = window.rootViewController {
            if let popover = activityVC.popoverPresentationController {
                popover.sourceView = window
                popover.sourceRect = CGRect(x: window.bounds.midX, y: window.bounds.midY, width: 0, height: 0)
                popover.permittedArrowDirections = []
            }
            rootVC.present(activityVC, animated: true)
        }
    }

    // MARK: - Helpers

    /// Base64url encode (URL-safe, no padding)
    private func base64UrlEncode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
