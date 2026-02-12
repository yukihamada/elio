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

    // MARK: - Modern 2026 Design Tokens

    static var glassBackground: Color {
        Color(UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark
                ? UIColor(white: 0.12, alpha: 0.8)
                : UIColor(white: 0.98, alpha: 0.8)
        })
    }

    static var glassBorder: Color {
        Color(UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark
                ? UIColor(white: 0.25, alpha: 0.5)
                : UIColor(white: 0.85, alpha: 0.7)
        })
    }

    static var cardBackground: Color {
        Color(UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark
                ? UIColor(white: 0.11, alpha: 1.0)
                : UIColor(white: 0.97, alpha: 1.0)
        })
    }

    static var surfaceElevated: Color {
        Color(UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark
                ? UIColor(white: 0.15, alpha: 1.0)
                : UIColor(white: 0.94, alpha: 1.0)
        })
    }

    static var subtleSeparator: Color {
        Color(UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark
                ? UIColor(white: 0.2, alpha: 0.6)
                : UIColor(white: 0.88, alpha: 0.8)
        })
    }
}

// MARK: - Modern Glass Card Modifier

struct GlassCard: ViewModifier {
    var cornerRadius: CGFloat = 20
    var padding: CGFloat = 16

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(Color.glassBorder, lineWidth: 0.5)
            )
    }
}

struct ModernCard: ViewModifier {
    var cornerRadius: CGFloat = 20

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(Color.cardBackground)
                    .shadow(color: .black.opacity(0.06), radius: 12, y: 4)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(Color.subtleSeparator, lineWidth: 0.5)
            )
    }
}

extension View {
    func glassCard(cornerRadius: CGFloat = 20, padding: CGFloat = 16) -> some View {
        modifier(GlassCard(cornerRadius: cornerRadius, padding: padding))
    }

    func modernCard(cornerRadius: CGFloat = 20) -> some View {
        modifier(ModernCard(cornerRadius: cornerRadius))
    }
}

// MARK: - Modern Section Header

struct ModernSectionHeader: View {
    let title: String
    let icon: String
    let gradient: [Color]

    init(title: String, icon: String, color: Color) {
        self.title = title
        self.icon = icon
        self.gradient = [color, color.opacity(0.7)]
    }

    init(title: String, icon: String, gradient: [Color]) {
        self.title = title
        self.icon = icon
        self.gradient = gradient
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(
                    .linearGradient(
                        colors: gradient,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(gradient[0].opacity(0.12))
                )

            Text(title)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
                .textCase(.uppercase)
                .tracking(0.5)
        }
        .padding(.leading, 4)
        .padding(.bottom, 4)
    }
}

// MARK: - Modern Settings Row

struct ModernSettingsRow<Trailing: View>: View {
    let icon: String
    let iconColor: Color
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(
                    RoundedRectangle(cornerRadius: 9)
                        .fill(
                            .linearGradient(
                                colors: [iconColor, iconColor.opacity(0.8)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 16, weight: .medium))

                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            trailing()
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
    }
}
