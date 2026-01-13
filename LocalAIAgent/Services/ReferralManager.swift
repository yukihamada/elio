import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// 紹介プログラムを管理するマネージャー
/// 将来の特典付与の基盤として、紹介コードと紹介数を追跡
@MainActor
final class ReferralManager: ObservableObject {
    static let shared = ReferralManager()

    // MARK: - UserDefaults Keys
    private enum Keys {
        static let referralCode = "referral.myCode"
        static let referredBy = "referral.referredBy"
        static let referralCount = "referral.count"
        static let hasSharedApp = "referral.hasShared"
    }

    // MARK: - Published Properties
    @Published private(set) var myReferralCode: String
    @Published private(set) var referralCount: Int = 0
    @Published private(set) var hasSharedApp: Bool = false

    private init() {
        // 紹介コードを生成または取得
        if let existingCode = UserDefaults.standard.string(forKey: Keys.referralCode) {
            myReferralCode = existingCode
        } else {
            let newCode = ReferralManager.generateReferralCode()
            UserDefaults.standard.set(newCode, forKey: Keys.referralCode)
            myReferralCode = newCode
        }

        referralCount = UserDefaults.standard.integer(forKey: Keys.referralCount)
        hasSharedApp = UserDefaults.standard.bool(forKey: Keys.hasSharedApp)
    }

    // MARK: - Code Generation

    /// ユニークな紹介コードを生成
    private static func generateReferralCode() -> String {
        let characters = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789" // 紛らわしい文字を除外
        let codeLength = 6
        return String((0..<codeLength).map { _ in characters.randomElement()! })
    }

    // MARK: - Sharing

    /// アプリを共有する際のテキストを生成
    func getShareText() -> String {
        let appStoreURL = "https://apps.apple.com/app/elio/id6740032873"
        return """
        Elioを使ってみて！完全オフラインで動くプライベートAIアシスタントだよ。
        ChatGPTと違って、データがクラウドに送信されないから安心。

        \(appStoreURL)

        紹介コード: \(myReferralCode)
        """
    }

    /// アプリ共有を記録
    func recordAppShared() {
        hasSharedApp = true
        UserDefaults.standard.set(true, forKey: Keys.hasSharedApp)
        logInfo("ReferralManager", "App shared", ["code": myReferralCode])
    }

    // MARK: - Referral Code Input

    /// 紹介コードを入力（紹介された側）
    func applyReferralCode(_ code: String) -> Bool {
        let normalizedCode = code.uppercased().trimmingCharacters(in: .whitespaces)

        // 自分のコードは使えない
        guard normalizedCode != myReferralCode else {
            logWarning("ReferralManager", "Cannot use own referral code")
            return false
        }

        // 既に紹介コードを使用済み
        guard UserDefaults.standard.string(forKey: Keys.referredBy) == nil else {
            logWarning("ReferralManager", "Already used a referral code")
            return false
        }

        // コードを保存
        UserDefaults.standard.set(normalizedCode, forKey: Keys.referredBy)
        logInfo("ReferralManager", "Applied referral code", ["code": normalizedCode])

        // 将来: サーバーに通知して紹介者のカウントを増やす
        // notifyReferralToServer(normalizedCode)

        return true
    }

    /// 紹介された人の情報を取得
    var referredByCode: String? {
        UserDefaults.standard.string(forKey: Keys.referredBy)
    }

    // MARK: - Statistics

    /// 紹介数を手動で増加（将来のサーバー連携用）
    func incrementReferralCount() {
        referralCount += 1
        UserDefaults.standard.set(referralCount, forKey: Keys.referralCount)
        logInfo("ReferralManager", "Referral count increased", ["count": "\(referralCount)"])
    }

    // MARK: - Share Sheet

    #if canImport(UIKit)
    /// 共有シートを表示
    func showShareSheet() {
        let shareText = getShareText()

        let activityVC = UIActivityViewController(
            activityItems: [shareText],
            applicationActivities: nil
        )

        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first,
           let rootVC = window.rootViewController {
            rootVC.present(activityVC, animated: true) { [weak self] in
                self?.recordAppShared()
            }
        }
    }
    #endif

    // MARK: - Debug

    #if DEBUG
    func resetForTesting() {
        UserDefaults.standard.removeObject(forKey: Keys.referralCode)
        UserDefaults.standard.removeObject(forKey: Keys.referredBy)
        UserDefaults.standard.removeObject(forKey: Keys.referralCount)
        UserDefaults.standard.removeObject(forKey: Keys.hasSharedApp)

        let newCode = ReferralManager.generateReferralCode()
        UserDefaults.standard.set(newCode, forKey: Keys.referralCode)
        myReferralCode = newCode
        referralCount = 0
        hasSharedApp = false

        logInfo("ReferralManager", "Reset for testing", ["newCode": newCode])
    }
    #endif
}
