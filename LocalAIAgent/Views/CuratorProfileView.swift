import SwiftUI

// MARK: - Curator Profile View

/// Shows curator status, stats, and eligibility progress.
/// For non-curators: shows requirements with progress bars.
/// For curators: shows badge, stats, rank, and pending reviews.
struct CuratorProfileView: View {
    @ObservedObject private var curatorManager = CuratorManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var showingOGVerification = false
    @State private var showingPendingReviews = false
    @State private var showingApplyConfirmation = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.chatBackgroundDynamic
                    .ignoresSafeArea()

                ScrollView(.vertical, showsIndicators: true) {
                    VStack(spacing: 24) {
                        if curatorManager.isCurator {
                            curatorActiveView
                        } else {
                            curatorApplicationView
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
            .navigationTitle(String(localized: "curator.title", defaultValue: "Curator"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(String(localized: "common.done")) { dismiss() }
                        .fontWeight(.semibold)
                }
            }
            .task {
                if curatorManager.isCurator {
                    await curatorManager.fetchCuratorStats()
                    await curatorManager.fetchPendingSkills()
                } else {
                    await curatorManager.checkEligibility()
                }
            }
            .sheet(isPresented: $showingOGVerification) {
                OGVerificationView()
            }
            .sheet(isPresented: $showingPendingReviews) {
                PendingReviewsListView()
            }
        }
    }

    // MARK: - Curator Active View (IS a curator)

    private var curatorActiveView: some View {
        VStack(spacing: 20) {
            // Badge & rank header
            curatorHeaderCard

            // Stats section
            curatorStatsSection

            // Pending reviews button
            pendingReviewsSection

            // Specializations
            if let stats = curatorManager.curatorStats, !stats.specializations.isEmpty {
                specializationsSection(stats.specializations)
            }

            // OG badge display
            if curatorManager.isOGVerified {
                ogStatusBanner
            }
        }
    }

    private var curatorHeaderCard: some View {
        VStack(spacing: 16) {
            // Badge
            let rank = curatorManager.curatorStats?.curatorRank ?? .bronze

            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [rank.color.opacity(0.3), rank.color.opacity(0)],
                            center: .center,
                            startRadius: 15,
                            endRadius: 60
                        )
                    )
                    .frame(width: 120, height: 120)

                // Show OG badge if verified, otherwise curator rank badge
                if curatorManager.isOGVerified {
                    AnimatedOGBadge(size: .large)
                } else {
                    OGBadgeView(
                        badgeType: curatorRankBadge(rank),
                        size: .large
                    )
                }
            }

            VStack(spacing: 6) {
                HStack(spacing: 6) {
                    Text(curatorManager.isOGVerified ? "OG Curator" : "Curator")
                        .font(.system(size: 22, weight: .bold, design: .rounded))

                    if curatorManager.isOGVerified {
                        OGBadgeView(badgeType: .ogFounder, size: .tiny)
                    }
                }

                Text(rank.localizedName + " Rank")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(rank.color)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(rank.color.opacity(0.15))
                    )
            }

            // Rank progress
            rankProgressView(rank: rank)
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.cardBackground)
                .shadow(color: .black.opacity(0.04), radius: 12, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.subtleSeparator, lineWidth: 0.5)
        )
    }

    private func rankProgressView(rank: CuratorRank) -> some View {
        let reviews = curatorManager.curatorStats?.reviewsCompleted ?? 0
        let nextRank: CuratorRank? = {
            switch rank {
            case .bronze: return .silver
            case .silver: return .gold
            case .gold: return .diamond
            case .diamond: return nil
            }
        }()

        return VStack(spacing: 8) {
            if let next = nextRank {
                HStack {
                    Text(rank.localizedName)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(rank.color)
                    Spacer()
                    Text(next.localizedName)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(next.color)
                }

                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.secondary.opacity(0.15))
                            .frame(height: 6)

                        let progress = min(1.0, CGFloat(reviews - rank.minReviews) / CGFloat(next.minReviews - rank.minReviews))
                        RoundedRectangle(cornerRadius: 4)
                            .fill(
                                LinearGradient(
                                    colors: [rank.color, next.color],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: geometry.size.width * progress, height: 6)
                    }
                }
                .frame(height: 6)

                Text("\(reviews)/\(next.minReviews) " + String(localized: "curator.reviews", defaultValue: "reviews"))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            } else {
                // Diamond rank - max
                Text(String(localized: "curator.rank.max", defaultValue: "最高ランクに到達しました"))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Stats Section

    private var curatorStatsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            ModernSectionHeader(
                title: String(localized: "curator.stats.title", defaultValue: "Stats"),
                icon: "chart.bar.fill",
                gradient: [.blue, .cyan]
            )

            let stats = curatorManager.curatorStats

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
            ], spacing: 10) {
                statCard(
                    title: String(localized: "curator.stats.reviews", defaultValue: "レビュー完了"),
                    value: "\(stats?.reviewsCompleted ?? 0)",
                    icon: "checkmark.circle",
                    color: .blue
                )
                statCard(
                    title: String(localized: "curator.stats.approved", defaultValue: "承認"),
                    value: "\(stats?.skillsApproved ?? 0)",
                    icon: "hand.thumbsup",
                    color: .green
                )
                statCard(
                    title: String(localized: "curator.stats.rejected", defaultValue: "却下"),
                    value: "\(stats?.skillsRejected ?? 0)",
                    icon: "hand.thumbsdown",
                    color: .red
                )
                statCard(
                    title: String(localized: "curator.stats.reputation", defaultValue: "レピュテーション"),
                    value: String(format: "%.1f", stats?.reputationScore ?? 0),
                    icon: "star.fill",
                    color: .orange
                )
            }
        }
    }

    private func statCard(title: String, value: String, icon: String, color: Color) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundStyle(color)

            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded))

            Text(title)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.subtleSeparator, lineWidth: 0.5)
        )
    }

    // MARK: - Pending Reviews Section

    private var pendingReviewsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            ModernSectionHeader(
                title: String(localized: "curator.pending.title", defaultValue: "Pending Reviews"),
                icon: "tray.full.fill",
                gradient: [.orange, .yellow]
            )

            Button(action: { showingPendingReviews = true }) {
                HStack(spacing: 14) {
                    Image(systemName: "tray.full.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .background(
                            RoundedRectangle(cornerRadius: 9)
                                .fill(
                                    LinearGradient(
                                        colors: [.orange, .orange.opacity(0.8)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        )

                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(localized: "curator.pending.review_skills", defaultValue: "レビュー待ちスキル"))
                            .font(.system(size: 16, weight: .medium))

                        Text(String(localized: "curator.pending.count",
                                    defaultValue: "\(curatorManager.pendingSkills.count)件のスキルが審査待ち"))
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    HStack(spacing: 8) {
                        if curatorManager.pendingSkills.count > 0 {
                            Text("\(curatorManager.pendingSkills.count)")
                                .font(.system(size: 12, weight: .semibold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.orange.opacity(0.12))
                                .foregroundStyle(.orange)
                                .clipShape(Capsule())
                        }

                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 16)
            }
            .buttonStyle(.plain)
            .modernCard(cornerRadius: 16)
        }
    }

    // MARK: - Specializations

    private func specializationsSection(_ specializations: [String]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ModernSectionHeader(
                title: String(localized: "curator.specializations.title", defaultValue: "Specializations"),
                icon: "tag.fill",
                gradient: [.purple, .pink]
            )

            FlowLayout(spacing: 8) {
                ForEach(specializations, id: \.self) { spec in
                    Text(spec)
                        .font(.system(size: 13, weight: .medium))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(Color.purple.opacity(0.12))
                        )
                        .foregroundStyle(.purple)
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.cardBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.subtleSeparator, lineWidth: 0.5)
            )
        }
    }

    // MARK: - OG Status Banner

    private var ogStatusBanner: some View {
        HStack(spacing: 12) {
            OGBadgeView(badgeType: .ogFounder, size: .small)

            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "curator.og.verified", defaultValue: "HamaDAO OG Verified"))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.ogGold)

                Text(String(localized: "curator.og.member", defaultValue: "1 of 6 OG Founders"))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 20))
                .foregroundStyle(Color.ogGold)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.ogGold.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.ogGold.opacity(0.3), lineWidth: 1)
                )
        )
    }

    // MARK: - Curator Application View (NOT a curator)

    private var curatorApplicationView: some View {
        VStack(spacing: 20) {
            // Header
            applicationHeader

            // OG shortcut banner
            ogShortcutBanner

            // Requirements section
            requirementsSection

            // Apply button
            applyButton

            // Error
            if let error = curatorManager.errorMessage {
                Text(error)
                    .font(.system(size: 13))
                    .foregroundStyle(.red)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.red.opacity(0.1))
                    )
            }
        }
    }

    private var applicationHeader: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.purple.opacity(0.15), .blue.opacity(0.15)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 88, height: 88)

                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 88, height: 88)

                Image(systemName: "shield.checkered")
                    .font(.system(size: 36, weight: .medium))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.purple, .blue],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            .shadow(color: .purple.opacity(0.2), radius: 16, y: 4)

            VStack(spacing: 6) {
                Text(String(localized: "curator.apply.title", defaultValue: "キュレーターになる"))
                    .font(.system(size: 22, weight: .bold, design: .rounded))

                Text(String(localized: "curator.apply.description", defaultValue: "スキルマーケットプレイスの品質を守る審査員として活動しましょう"))
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
            }
        }
        .padding(.vertical, 8)
    }

    private var ogShortcutBanner: some View {
        Button(action: { showingOGVerification = true }) {
            HStack(spacing: 12) {
                NounsGlassesShape()
                    .fill(Color.ogGold)
                    .frame(width: 28, height: 12)

                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "curator.og.shortcut.title", defaultValue: "HamaDAO OG? 要件をスキップ"))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.ogGold)

                    Text(String(localized: "curator.og.shortcut.subtitle", defaultValue: "NFT保有を確認して即時キュレーターに"))
                        .font(.system(size: 11))
                        .foregroundStyle(Color.ogGold.opacity(0.7))
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.ogGold.opacity(0.5))
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.ogGold.opacity(0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color.ogGold.opacity(0.3), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Requirements

    private var requirementsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            ModernSectionHeader(
                title: String(localized: "curator.requirements.title", defaultValue: "Requirements"),
                icon: "checklist",
                gradient: [.blue, .indigo]
            )

            let eligibility = curatorManager.eligibility

            VStack(spacing: 0) {
                requirementRow(
                    icon: "puzzlepiece.extension.fill",
                    title: String(localized: "curator.req.skills", defaultValue: "公開スキル数"),
                    current: eligibility?.publishedSkills ?? 0,
                    required: eligibility?.requiredSkills ?? 3,
                    color: .purple
                )

                Divider().padding(.leading, 56)

                requirementRow(
                    icon: "arrow.down.circle.fill",
                    title: String(localized: "curator.req.downloads", defaultValue: "合計ダウンロード数"),
                    current: eligibility?.totalDownloads ?? 0,
                    required: eligibility?.requiredDownloads ?? 100,
                    color: .blue
                )

                Divider().padding(.leading, 56)

                requirementRow(
                    icon: "hand.thumbsup.fill",
                    title: String(localized: "curator.req.endorsements", defaultValue: "エンドースメント"),
                    current: eligibility?.endorsements ?? 0,
                    required: eligibility?.requiredEndorsements ?? 2,
                    color: .green
                )
            }
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.cardBackground)
                    .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.subtleSeparator, lineWidth: 0.5)
            )
        }
    }

    private func requirementRow(icon: String, title: String, current: Int, required: Int, color: Color) -> some View {
        let isMet = current >= required
        let progress = required > 0 ? min(1.0, Double(current) / Double(required)) : 0

        return VStack(spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundStyle(isMet ? .green : color)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 15))

                    Text("\(current)/\(required)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(isMet ? .green : .secondary)
                }

                Spacer()

                if isMet {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(.green)
                }
            }

            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.secondary.opacity(0.15))
                        .frame(height: 4)

                    RoundedRectangle(cornerRadius: 3)
                        .fill(isMet ? Color.green : color)
                        .frame(width: geometry.size.width * progress, height: 4)
                }
            }
            .frame(height: 4)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private var applyButton: some View {
        let isEligible = curatorManager.eligibility?.isEligible ?? false

        return VStack(spacing: 8) {
            Button(action: {
                showingApplyConfirmation = true
            }) {
                HStack(spacing: 8) {
                    if curatorManager.isLoading {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: "paperplane.fill")
                        Text(String(localized: "curator.apply.button", defaultValue: "キュレーターに申請"))
                            .font(.system(size: 16, weight: .semibold))
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    LinearGradient(
                        colors: isEligible ? [.purple, .indigo] : [.gray, .gray.opacity(0.7)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .shadow(color: isEligible ? .purple.opacity(0.3) : .clear, radius: 8, y: 4)
            }
            .disabled(!isEligible || curatorManager.isLoading)

            if !isEligible {
                Text(String(localized: "curator.apply.requirements_not_met", defaultValue: "全ての要件を満たしてから申請できます"))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
        .alert(String(localized: "curator.apply.confirm.title", defaultValue: "キュレーターに申請"), isPresented: $showingApplyConfirmation) {
            Button(String(localized: "common.cancel"), role: .cancel) {}
            Button(String(localized: "curator.apply.confirm.action", defaultValue: "申請"), role: .none) {
                Task {
                    _ = await curatorManager.applyForCurator()
                }
            }
        } message: {
            Text(String(localized: "curator.apply.confirm.message", defaultValue: "キュレーターとしてスキルの審査を行います。申請後は承認審査があります。"))
        }
    }

    // MARK: - Helpers

    private func curatorRankBadge(_ rank: CuratorRank) -> BadgeType {
        switch rank {
        case .bronze: return .curatorBronze
        case .silver: return .curatorSilver
        case .gold: return .curatorGold
        case .diamond: return .curatorDiamond
        }
    }
}

// MARK: - Pending Reviews List View

struct PendingReviewsListView: View {
    @ObservedObject private var curatorManager = CuratorManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var selectedSkill: PendingSkill?

    var body: some View {
        NavigationStack {
            ZStack {
                Color.chatBackgroundDynamic
                    .ignoresSafeArea()

                if curatorManager.pendingSkills.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "tray")
                            .font(.system(size: 40))
                            .foregroundStyle(.secondary)
                        Text(String(localized: "curator.pending.empty", defaultValue: "レビュー待ちのスキルはありません"))
                            .font(.system(size: 15))
                            .foregroundStyle(.secondary)
                    }
                } else {
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            ForEach(curatorManager.pendingSkills) { skill in
                                Button(action: { selectedSkill = skill }) {
                                    pendingSkillCard(skill)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                    }
                }
            }
            .navigationTitle(String(localized: "curator.pending.list_title", defaultValue: "Pending Reviews"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(String(localized: "common.done")) { dismiss() }
                        .fontWeight(.semibold)
                }
            }
            .task {
                await curatorManager.fetchPendingSkills()
            }
            .sheet(item: $selectedSkill) { skill in
                SkillReviewView(skill: skill)
            }
        }
    }

    private func pendingSkillCard(_ skill: PendingSkill) -> some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.orange.opacity(0.15))
                    .frame(width: 44, height: 44)

                Image(systemName: "puzzlepiece.extension")
                    .font(.system(size: 20))
                    .foregroundStyle(.orange)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(skill.name)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Label(skill.authorName, systemImage: "person")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)

                    if let category = skill.category {
                        Text(category)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }

                Text(skill.description)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.subtleSeparator, lineWidth: 0.5)
        )
    }
}

// MARK: - Simple FlowLayout for tags

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrangeSubviews(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrangeSubviews(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y), proposal: .unspecified)
        }
    }

    private func arrangeSubviews(proposal: ProposedViewSize, subviews: Subviews) -> (positions: [CGPoint], size: CGSize) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxX: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            maxX = max(maxX, x)
        }

        return (positions, CGSize(width: maxX, height: y + rowHeight))
    }
}

// MARK: - Preview

#Preview {
    CuratorProfileView()
}
