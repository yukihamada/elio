import SwiftUI

// MARK: - OG Badge View (Reusable Component)

/// Displays ⌐◨-◨ Nouns glasses icon for OG Founders with animated glow.
/// Also supports Curator rank badges and Top Publisher badge.
struct OGBadgeView: View {
    let badgeType: BadgeType
    var size: BadgeSize = .small
    var showLabel: Bool = false

    enum BadgeSize {
        case tiny   // 16pt - inline next to username
        case small  // 24pt - profile list items
        case medium // 40pt - profile header
        case large  // 64pt - verification success

        var dimension: CGFloat {
            switch self {
            case .tiny: return 16
            case .small: return 24
            case .medium: return 40
            case .large: return 64
            }
        }

        var fontSize: CGFloat {
            switch self {
            case .tiny: return 8
            case .small: return 11
            case .medium: return 18
            case .large: return 28
            }
        }

        var glassesFont: CGFloat {
            switch self {
            case .tiny: return 7
            case .small: return 10
            case .medium: return 16
            case .large: return 26
            }
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            badgeIcon
            if showLabel {
                Text(labelText)
                    .font(.system(size: size.fontSize, weight: .semibold, design: .rounded))
                    .foregroundStyle(badgeColor)
            }
        }
    }

    @ViewBuilder
    private var badgeIcon: some View {
        switch badgeType {
        case .ogFounder:
            ogFounderBadge
        case .curatorBronze, .curatorSilver, .curatorGold, .curatorDiamond:
            curatorBadge
        case .topPublisher:
            topPublisherBadge
        }
    }

    // MARK: - OG Founder Badge (Nouns Glasses)

    private var ogFounderBadge: some View {
        ZStack {
            // Glow effect
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.ogGold.opacity(0.4), Color.ogGold.opacity(0)],
                        center: .center,
                        startRadius: size.dimension * 0.2,
                        endRadius: size.dimension * 0.8
                    )
                )
                .frame(width: size.dimension * 1.5, height: size.dimension * 1.5)

            // Background circle
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color.ogGold, Color.ogAmber],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: size.dimension, height: size.dimension)
                .shadow(color: Color.ogGold.opacity(0.5), radius: size.dimension * 0.15, y: 2)

            // Nouns glasses ⌐◨-◨
            NounsGlassesShape()
                .fill(.white)
                .frame(width: size.dimension * 0.7, height: size.dimension * 0.35)
        }
    }

    // MARK: - Curator Badge

    private var curatorBadge: some View {
        let rank = curatorRank
        return ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [rank.color, rank.color.opacity(0.7)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: size.dimension, height: size.dimension)
                .shadow(color: rank.color.opacity(0.3), radius: 4, y: 2)

            Image(systemName: rank.icon)
                .font(.system(size: size.fontSize * 0.8, weight: .bold))
                .foregroundStyle(.white)
        }
    }

    // MARK: - Top Publisher Badge

    private var topPublisherBadge: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [.purple, .indigo],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: size.dimension, height: size.dimension)
                .shadow(color: .purple.opacity(0.3), radius: 4, y: 2)

            Image(systemName: "star.fill")
                .font(.system(size: size.fontSize * 0.8, weight: .bold))
                .foregroundStyle(.white)
        }
    }

    // MARK: - Helpers

    private var curatorRank: CuratorRank {
        switch badgeType {
        case .curatorBronze: return .bronze
        case .curatorSilver: return .silver
        case .curatorGold: return .gold
        case .curatorDiamond: return .diamond
        default: return .bronze
        }
    }

    private var badgeColor: Color {
        switch badgeType {
        case .ogFounder: return .ogGold
        case .curatorBronze: return CuratorRank.bronze.color
        case .curatorSilver: return CuratorRank.silver.color
        case .curatorGold: return CuratorRank.gold.color
        case .curatorDiamond: return CuratorRank.diamond.color
        case .topPublisher: return .purple
        }
    }

    private var labelText: String {
        switch badgeType {
        case .ogFounder: return "OG Founder"
        case .curatorBronze: return "Curator"
        case .curatorSilver: return "Curator"
        case .curatorGold: return "Curator"
        case .curatorDiamond: return "Curator"
        case .topPublisher: return "Top Publisher"
        }
    }
}

// MARK: - Nouns Glasses Shape ⌐◨-◨

/// Pixel-art-inspired Nouns DAO glasses shape ⌐◨-◨
/// Renders as a solid shape: stem + left lens + bridge + right lens
struct NounsGlassesShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        let unit = w / 14 // 14-unit grid

        // Left stem ⌐
        path.addRect(CGRect(x: 0, y: h * 0.15, width: unit * 1.5, height: h * 0.55))

        // Left lens ◨
        let leftLens = CGRect(x: unit * 1.5, y: 0, width: unit * 5, height: h)
        path.addRoundedRect(in: leftLens, cornerSize: CGSize(width: unit * 0.8, height: unit * 0.8))

        // Bridge -
        path.addRect(CGRect(x: unit * 6.5, y: h * 0.25, width: unit * 1, height: h * 0.5))

        // Right lens ◨
        let rightLens = CGRect(x: unit * 7.5, y: 0, width: unit * 5, height: h)
        path.addRoundedRect(in: rightLens, cornerSize: CGSize(width: unit * 0.8, height: unit * 0.8))

        return path
    }
}

// MARK: - Animated OG Badge

/// Special animated variant for OG badge with pulsing glow
struct AnimatedOGBadge: View {
    var size: OGBadgeView.BadgeSize = .large
    @State private var glowPhase: CGFloat = 0

    var body: some View {
        ZStack {
            // Animated outer glow
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.ogGold.opacity(0.3 + glowPhase * 0.2),
                            Color.ogGold.opacity(0),
                        ],
                        center: .center,
                        startRadius: size.dimension * 0.3,
                        endRadius: size.dimension * 1.2
                    )
                )
                .frame(width: size.dimension * 2.5, height: size.dimension * 2.5)

            OGBadgeView(badgeType: .ogFounder, size: size)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                glowPhase = 1
            }
        }
    }
}

// MARK: - Badge Row (for displaying multiple badges inline)

/// Shows a horizontal row of badges next to a username
struct BadgeRow: View {
    let badges: [BadgeType]
    var size: OGBadgeView.BadgeSize = .tiny

    var body: some View {
        HStack(spacing: 2) {
            ForEach(badges, id: \.rawValue) { badge in
                OGBadgeView(badgeType: badge, size: size)
            }
        }
    }
}

// MARK: - OG Gold Color

extension Color {
    static let ogGold = Color(red: 1.0, green: 0.84, blue: 0.0)
    static let ogAmber = Color(red: 1.0, green: 0.65, blue: 0.0)
    static let ogGoldLight = Color(red: 1.0, green: 0.93, blue: 0.6)
}

// MARK: - Preview

#Preview("OG Badge Sizes") {
    VStack(spacing: 20) {
        HStack(spacing: 16) {
            OGBadgeView(badgeType: .ogFounder, size: .tiny)
            OGBadgeView(badgeType: .ogFounder, size: .small)
            OGBadgeView(badgeType: .ogFounder, size: .medium)
            OGBadgeView(badgeType: .ogFounder, size: .large)
        }

        HStack(spacing: 16) {
            OGBadgeView(badgeType: .curatorBronze, size: .small, showLabel: true)
            OGBadgeView(badgeType: .curatorSilver, size: .small, showLabel: true)
            OGBadgeView(badgeType: .curatorGold, size: .small, showLabel: true)
            OGBadgeView(badgeType: .curatorDiamond, size: .small, showLabel: true)
        }

        AnimatedOGBadge(size: .large)

        HStack(spacing: 4) {
            Text("yuki")
                .font(.system(size: 15, weight: .semibold))
            BadgeRow(badges: [.ogFounder, .curatorGold])
        }
    }
    .padding()
}
