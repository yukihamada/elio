import Foundation
import SwiftUI

enum AppLanguage: String, CaseIterable {
    case system = "system"
    case english = "en"
    case japanese = "ja"

    var displayName: String {
        switch self {
        case .system:
            return String(localized: "language.system")
        case .english:
            return "English"
        case .japanese:
            return "日本語"
        }
    }

    var icon: String {
        switch self {
        case .system:
            return "gear"
        case .english:
            return "globe.americas.fill"
        case .japanese:
            return "globe.asia.australia.fill"
        }
    }

    var localeIdentifier: String? {
        switch self {
        case .system:
            return nil
        case .english:
            return "en"
        case .japanese:
            return "ja"
        }
    }
}

@MainActor
class LanguageManager: ObservableObject {
    static let shared = LanguageManager()

    private let languageKey = "app_language"

    @Published var currentLanguage: AppLanguage {
        didSet {
            saveLanguage()
            applyLanguage()
        }
    }

    private init() {
        // Load saved language or default to system
        if let savedLanguage = UserDefaults.standard.string(forKey: languageKey),
           let language = AppLanguage(rawValue: savedLanguage) {
            self.currentLanguage = language
        } else {
            self.currentLanguage = .system
        }
        applyLanguage()
    }

    private func saveLanguage() {
        UserDefaults.standard.set(currentLanguage.rawValue, forKey: languageKey)
    }

    private func applyLanguage() {
        if let localeId = currentLanguage.localeIdentifier {
            // Set specific language
            UserDefaults.standard.set([localeId], forKey: "AppleLanguages")
        } else {
            // Remove override to use system language
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        }
        UserDefaults.standard.synchronize()
    }

    /// Get the effective locale for the app
    var effectiveLocale: Locale {
        if let localeId = currentLanguage.localeIdentifier {
            return Locale(identifier: localeId)
        }
        return Locale.current
    }

    /// Check if current language is Japanese
    var isJapanese: Bool {
        switch currentLanguage {
        case .japanese:
            return true
        case .english:
            return false
        case .system:
            return Locale.current.language.languageCode?.identifier == "ja"
        }
    }
}
