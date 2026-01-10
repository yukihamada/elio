import SwiftUI
import UIKit

enum AppTheme: String, CaseIterable {
    case system = "system"
    case light = "light"
    case dark = "dark"

    var displayName: String {
        switch self {
        case .system: return String(localized: "theme.system")
        case .light: return String(localized: "theme.light")
        case .dark: return String(localized: "theme.dark")
        }
    }

    var icon: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max.fill"
        case .dark: return "moon.fill"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

@MainActor
final class ThemeManager: ObservableObject {
    @AppStorage("appTheme") private var themeRawValue: String = AppTheme.system.rawValue

    var currentTheme: AppTheme {
        get { AppTheme(rawValue: themeRawValue) ?? .system }
        set {
            themeRawValue = newValue.rawValue
            objectWillChange.send()
        }
    }

    var colorScheme: ColorScheme? {
        currentTheme.colorScheme
    }
}

// MARK: - Theme Colors

extension Color {
    // ChatGPT-style colors
    static let chatBackground = Color("ChatBackground")
    static let chatUserBubble = Color("UserBubble")
    static let chatInputBackground = Color("InputBackground")
    static let chatBorder = Color("ChatBorder")

    // Fallback colors for runtime
    static var chatBackgroundDynamic: Color {
        Color(UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark
                ? UIColor(red: 0.07, green: 0.07, blue: 0.07, alpha: 1) // #121212
                : UIColor.systemBackground
        })
    }

    static var chatUserBubbleDynamic: Color {
        Color(UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark
                ? UIColor(red: 0.17, green: 0.17, blue: 0.17, alpha: 1) // #2b2b2b
                : UIColor(red: 0.95, green: 0.95, blue: 0.95, alpha: 1) // #f2f2f2
        })
    }

    static var chatInputBackgroundDynamic: Color {
        Color(UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark
                ? UIColor(red: 0.17, green: 0.17, blue: 0.17, alpha: 1) // #2b2b2b
                : UIColor(red: 0.95, green: 0.95, blue: 0.95, alpha: 1)
        })
    }

    static var chatBorderDynamic: Color {
        Color(UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark
                ? UIColor(red: 0.25, green: 0.25, blue: 0.25, alpha: 1)
                : UIColor(red: 0.85, green: 0.85, blue: 0.85, alpha: 1)
        })
    }

    static var chatSecondaryText: Color {
        Color(UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark
                ? UIColor(red: 0.6, green: 0.6, blue: 0.6, alpha: 1)
                : UIColor(red: 0.4, green: 0.4, blue: 0.4, alpha: 1)
        })
    }
}
