import Foundation
import CryptoKit
import LocalAuthentication
import Vision
import UIKit

/// Digital Vault Manager - Secure document storage with AES-256 encryption
/// Stores important documents encrypted locally, accessible only with Face ID/Touch ID
@MainActor
final class DigitalVaultManager: ObservableObject {
    static let shared = DigitalVaultManager()

    // MARK: - Published Properties

    @Published private(set) var documents: [VaultDocument] = []
    @Published private(set) var isUnlocked = false
    @Published private(set) var lastUnlockTime: Date?

    // MARK: - Private Properties

    private let keychainService = "com.eliochat.digitalvault"
    private let masterKeyAccount = "vault_master_key"
    private let documentsFileURL: URL
    private var masterKey: SymmetricKey?

    // Auto-lock after 5 minutes
    private let autoLockInterval: TimeInterval = 300
    private var autoLockTimer: Timer?

    // MARK: - Initialization

    private init() {
        let fileManager = FileManager.default
        let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let vaultPath = documentsPath.appendingPathComponent("DigitalVault", isDirectory: true)

        // Create vault directory if needed
        if !fileManager.fileExists(atPath: vaultPath.path) {
            try? fileManager.createDirectory(at: vaultPath, withIntermediateDirectories: true)
        }

        documentsFileURL = vaultPath.appendingPathComponent("documents.encrypted")
    }

    // MARK: - Authentication

    /// Unlock vault with biometric authentication
    func unlock() async throws {
        let context = LAContext()
        var error: NSError?

        // Check if biometric authentication is available
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            throw VaultError.biometricUnavailable
        }

        // Authenticate
        let reason = "重要書類にアクセスするために認証してください"
        let success = try await context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason)

        guard success else {
            throw VaultError.authenticationFailed
        }

        // Load or create master key
        try await loadOrCreateMasterKey()

        // Load documents
        try await loadDocuments()

        isUnlocked = true
        lastUnlockTime = Date()

        // Start auto-lock timer
        startAutoLockTimer()
    }

    /// Lock vault
    func lock() {
        isUnlocked = false
        masterKey = nil
        documents.removeAll()
        autoLockTimer?.invalidate()
        autoLockTimer = nil
    }

    // MARK: - Master Key Management

    private func loadOrCreateMasterKey() async throws {
        // Try to load existing key from Keychain
        if let existingKey = loadMasterKeyFromKeychain() {
            masterKey = existingKey
            return
        }

        // Create new key
        let newKey = SymmetricKey(size: .bits256)
        try saveMasterKeyToKeychain(newKey)
        masterKey = newKey
    }

    private func loadMasterKeyFromKeychain() -> SymmetricKey? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: masterKeyAccount,
            kSecReturnData as String: true
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data else {
            return nil
        }

        return SymmetricKey(data: data)
    }

    private func saveMasterKeyToKeychain(_ key: SymmetricKey) throws {
        let keyData = key.withUnsafeBytes { Data($0) }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: masterKeyAccount,
            kSecValueData as String: keyData,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        // Delete existing item first
        SecItemDelete(query as CFDictionary)

        // Add new item
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw VaultError.keychainError
        }
    }

    // MARK: - Document Management

    /// Add document from image
    func addDocument(image: UIImage, name: String, category: DocumentCategory) async throws {
        guard isUnlocked, let masterKey = masterKey else {
            throw VaultError.vaultLocked
        }

        // Extract text from image using OCR
        let extractedText = try await extractText(from: image)

        // Compress and encrypt image
        guard let imageData = image.jpegData(compressionQuality: 0.8) else {
            throw VaultError.imageProcessingFailed
        }

        let encryptedData = try encrypt(data: imageData, using: masterKey)

        let document = VaultDocument(
            id: UUID(),
            name: name,
            category: category,
            createdAt: Date(),
            encryptedImageData: encryptedData,
            extractedText: extractedText
        )

        documents.append(document)
        try await saveDocuments()
    }

    /// Get decrypted document image
    func getDocumentImage(id: UUID) throws -> UIImage {
        guard isUnlocked, let masterKey = masterKey else {
            throw VaultError.vaultLocked
        }

        guard let document = documents.first(where: { $0.id == id }) else {
            throw VaultError.documentNotFound
        }

        let decryptedData = try decrypt(data: document.encryptedImageData, using: masterKey)
        guard let image = UIImage(data: decryptedData) else {
            throw VaultError.imageProcessingFailed
        }

        return image
    }

    /// Delete document
    func deleteDocument(id: UUID) async throws {
        guard isUnlocked else {
            throw VaultError.vaultLocked
        }

        documents.removeAll { $0.id == id }
        try await saveDocuments()
    }

    /// Update document name or category
    func updateDocument(id: UUID, name: String?, category: DocumentCategory?) async throws {
        guard isUnlocked else {
            throw VaultError.vaultLocked
        }

        guard let index = documents.firstIndex(where: { $0.id == id }) else {
            throw VaultError.documentNotFound
        }

        var document = documents[index]
        if let name = name {
            document.name = name
        }
        if let category = category {
            document.category = category
        }
        documents[index] = document

        try await saveDocuments()
    }

    // MARK: - Encryption/Decryption

    private func encrypt(data: Data, using key: SymmetricKey) throws -> Data {
        let sealedBox = try AES.GCM.seal(data, using: key)
        guard let encryptedData = sealedBox.combined else {
            throw VaultError.encryptionFailed
        }
        return encryptedData
    }

    private func decrypt(data: Data, using key: SymmetricKey) throws -> Data {
        let sealedBox = try AES.GCM.SealedBox(combined: data)
        return try AES.GCM.open(sealedBox, using: key)
    }

    // MARK: - OCR

    /// Extract text from image using Vision framework
    func extractText(from image: UIImage) async throws -> String {
        guard let cgImage = image.cgImage else {
            throw VaultError.imageProcessingFailed
        }

        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(returning: "")
                    return
                }

                let recognizedText = observations.compactMap { observation in
                    observation.topCandidates(1).first?.string
                }.joined(separator: "\n")

                continuation.resume(returning: recognizedText)
            }

            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["ja", "en"]
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    // MARK: - Persistence

    private func saveDocuments() async throws {
        guard let masterKey = masterKey else {
            throw VaultError.vaultLocked
        }

        let encoder = JSONEncoder()
        let documentsData = try encoder.encode(documents)
        let encryptedData = try encrypt(data: documentsData, using: masterKey)

        try encryptedData.write(to: documentsFileURL)
    }

    private func loadDocuments() async throws {
        guard let masterKey = masterKey else {
            throw VaultError.vaultLocked
        }

        guard FileManager.default.fileExists(atPath: documentsFileURL.path) else {
            documents = []
            return
        }

        let encryptedData = try Data(contentsOf: documentsFileURL)
        let decryptedData = try decrypt(data: encryptedData, using: masterKey)

        let decoder = JSONDecoder()
        documents = try decoder.decode([VaultDocument].self, from: decryptedData)
    }

    // MARK: - Auto-Lock

    private func startAutoLockTimer() {
        autoLockTimer?.invalidate()
        autoLockTimer = Timer.scheduledTimer(withTimeInterval: autoLockInterval, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.lock()
            }
        }
    }

    func resetAutoLockTimer() {
        if isUnlocked {
            startAutoLockTimer()
        }
    }

    // MARK: - Export

    /// Export document as PDF (unencrypted)
    func exportDocument(id: UUID) throws -> URL {
        guard isUnlocked else {
            throw VaultError.vaultLocked
        }

        let image = try getDocumentImage(id: id)
        guard let document = documents.first(where: { $0.id == id }) else {
            throw VaultError.documentNotFound
        }

        let pdfData = createPDF(from: image, title: document.name)

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(document.name).pdf")
        try pdfData.write(to: tempURL)

        return tempURL
    }

    private func createPDF(from image: UIImage, title: String) -> Data {
        let pdfMetaData = [
            kCGPDFContextCreator: "ElioChat Digital Vault",
            kCGPDFContextTitle: title
        ]
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = pdfMetaData as [String: Any]

        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792) // US Letter size
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect, format: format)

        let data = renderer.pdfData { context in
            context.beginPage()

            // Draw image
            let imageRect = AVMakeRect(aspectRatio: image.size, insideRect: pageRect.insetBy(dx: 20, dy: 20))
            image.draw(in: imageRect)
        }

        return data
    }
}

// MARK: - Supporting Types

struct VaultDocument: Identifiable, Codable {
    let id: UUID
    var name: String
    var category: DocumentCategory
    let createdAt: Date
    var encryptedImageData: Data
    var extractedText: String?

    var lastModified: Date {
        createdAt
    }
}

enum DocumentCategory: String, Codable, CaseIterable {
    case id = "身分証明書"
    case insurance = "保険証"
    case property = "権利書"
    case passport = "パスポート"
    case familyPhoto = "家族写真"
    case bankCard = "銀行カード"
    case important = "重要書類"
    case other = "その他"

    var icon: String {
        switch self {
        case .id: return "person.text.rectangle"
        case .insurance: return "cross.case"
        case .property: return "doc.text"
        case .passport: return "airplane"
        case .familyPhoto: return "photo"
        case .bankCard: return "creditcard"
        case .important: return "doc.fill"
        case .other: return "folder"
        }
    }

    var color: String {
        switch self {
        case .id: return "blue"
        case .insurance: return "red"
        case .property: return "purple"
        case .passport: return "green"
        case .familyPhoto: return "pink"
        case .bankCard: return "orange"
        case .important: return "yellow"
        case .other: return "gray"
        }
    }
}

enum VaultError: Error, LocalizedError {
    case biometricUnavailable
    case authenticationFailed
    case vaultLocked
    case keychainError
    case encryptionFailed
    case decryptionFailed
    case imageProcessingFailed
    case documentNotFound

    var errorDescription: String? {
        switch self {
        case .biometricUnavailable:
            return "Face ID/Touch IDが利用できません"
        case .authenticationFailed:
            return "認証に失敗しました"
        case .vaultLocked:
            return "金庫がロックされています"
        case .keychainError:
            return "Keychainエラーが発生しました"
        case .encryptionFailed:
            return "暗号化に失敗しました"
        case .decryptionFailed:
            return "復号化に失敗しました"
        case .imageProcessingFailed:
            return "画像処理に失敗しました"
        case .documentNotFound:
            return "書類が見つかりません"
        }
    }
}

// Helper function for PDF creation
func AVMakeRect(aspectRatio: CGSize, insideRect: CGRect) -> CGRect {
    let aspectWidth = aspectRatio.width
    let aspectHeight = aspectRatio.height
    let boundingWidth = insideRect.width
    let boundingHeight = insideRect.height

    var destWidth = boundingWidth
    var destHeight = boundingHeight

    if aspectWidth > 0 && aspectHeight > 0 {
        let aspectRatio = aspectWidth / aspectHeight
        if destWidth / destHeight > aspectRatio {
            destWidth = destHeight * aspectRatio
        } else {
            destHeight = destWidth / aspectRatio
        }
    }

    let x = insideRect.origin.x + (boundingWidth - destWidth) / 2
    let y = insideRect.origin.y + (boundingHeight - destHeight) / 2

    return CGRect(x: x, y: y, width: destWidth, height: destHeight)
}
