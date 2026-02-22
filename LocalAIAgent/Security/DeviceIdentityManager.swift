//
//  DeviceIdentityManager.swift
//  LocalAIAgent
//
//  Device identity and fingerprint management for ChatWeb API key authentication
//

import Foundation
import UIKit

final class DeviceIdentityManager {
    static let shared = DeviceIdentityManager()

    private let keychainService = "love.elio.LocalAIAgent"
    private let keychainAccount = "device_identity"

    struct DeviceFingerprint: Codable {
        let deviceId: String
        let model: String
        let osVersion: String
        let locale: String
        let appVersion: String
    }

    /// Persistent device ID (stored in Keychain)
    var deviceId: String {
        // Try to get from Keychain first
        if let stored = getDeviceIdFromKeychain() {
            return stored
        }

        // Generate new ID using identifierForVendor
        let newId: String
        if let vendorId = UIDevice.current.identifierForVendor?.uuidString {
            newId = "elio-device-\(vendorId.prefix(12).lowercased())"
        } else {
            // Fallback to random UUID (rare case)
            newId = "elio-device-\(UUID().uuidString.prefix(12).lowercased())"
        }

        // Store in Keychain
        storeDeviceIdInKeychain(newId)
        return newId
    }

    /// Device fingerprint for server-side validation
    var deviceFingerprint: DeviceFingerprint {
        DeviceFingerprint(
            deviceId: deviceId,
            model: getDeviceModel(),
            osVersion: UIDevice.current.systemVersion,
            locale: Locale.current.identifier,
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        )
    }

    private init() {}

    private func getDeviceModel() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        return withUnsafePointer(to: &systemInfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                String(validatingUTF8: $0) ?? "Unknown"
            }
        }
    }

    private func getDeviceIdFromKeychain() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let deviceId = String(data: data, encoding: .utf8) else {
            return nil
        }

        return deviceId
    }

    private func storeDeviceIdInKeychain(_ deviceId: String) {
        guard let data = deviceId.data(using: .utf8) else { return }

        // Delete old entry first
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        // Add new entry
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        SecItemAdd(addQuery as CFDictionary, nil)
    }

    // MARK: - Pairing Code (for P2P Messaging)

    /// Generate a 4-digit pairing code for friend requests
    func generatePairingCode() -> String {
        let code = String(format: "%04d", Int.random(in: 0...9999))
        UserDefaults.standard.set(code, forKey: "current_pairing_code")
        UserDefaults.standard.set(Date(), forKey: "pairing_code_generated_at")
        return code
    }

    /// Get current pairing code (or generate new one if expired)
    func getCurrentPairingCode() -> String {
        if let code = UserDefaults.standard.string(forKey: "current_pairing_code"),
           let generatedAt = UserDefaults.standard.object(forKey: "pairing_code_generated_at") as? Date,
           Date().timeIntervalSince(generatedAt) < 3600 { // Valid for 1 hour
            return code
        }

        return generatePairingCode()
    }

    /// Verify pairing code from another device
    func verifyPairingCode(_ code: String) -> Bool {
        // TODO: Implement P2P discovery by pairing code
        // For now, just validate format
        return code.count == 4 && Int(code) != nil
    }
}
