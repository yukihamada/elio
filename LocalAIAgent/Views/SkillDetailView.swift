import SwiftUI

// MARK: - Skill Detail View

struct SkillDetailView: View {
    let skill: Skill

    @StateObject private var manager = SkillMarketplaceManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var reviews: [SkillReview] = []
    @State private var showingMCPConfig = false
    @State private var showingReviewSheet = false
    @State private var showingUninstallAlert = false
    @State private var installSuccess = false

    private var isInstalled: Bool {
        manager.isInstalled(skill.id)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.chatBackgroundDynamic
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        // Header
                        headerSection

                        // Stats
                        statsSection

                        // Description
                        descriptionSection

                        // Tags
                        if !skill.tags.isEmpty {
                            tagsSection
                        }

                        // MCP Config Preview
                        mcpConfigSection

                        // Reviews
                        reviewsSection

                        // Action button
                        actionButton
                            .padding(.bottom, 20)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                }
            }
            .navigationTitle("スキル詳細")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("閉じる") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
            .task {
                if let detail = await manager.fetchSkillDetail(id: skill.id) {
                    reviews = detail.reviews ?? []
                }
            }
            .sheet(isPresented: $showingReviewSheet) {
                WriteReviewSheet(skillId: skill.id, skillName: skill.name)
            }
            .alert("スキルをアンインストール", isPresented: $showingUninstallAlert) {
                Button("アンインストール", role: .destructive) {
                    if let installed = manager.installedSkill(for: skill.id) {
                        manager.uninstallSkill(installed)
                    }
                }
                Button("キャンセル", role: .cancel) {}
            } message: {
                Text("\(skill.name) をアンインストールしますか？")
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 14) {
            // Icon
            ZStack {
                RoundedRectangle(cornerRadius: 20)
                    .fill(
                        LinearGradient(
                            colors: [skill.category.color, skill.category.color.opacity(0.6)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 80, height: 80)
                    .shadow(color: skill.category.color.opacity(0.3), radius: 12, y: 4)

                if let iconUrl = skill.iconUrl, let url = URL(string: iconUrl) {
                    AsyncImage(url: url) { image in
                        image
                            .resizable()
                            .scaledToFit()
                            .frame(width: 44, height: 44)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    } placeholder: {
                        Image(systemName: skill.category.iconName)
                            .font(.system(size: 36))
                            .foregroundStyle(.white)
                    }
                } else {
                    Image(systemName: skill.category.iconName)
                        .font(.system(size: 36))
                        .foregroundStyle(.white)
                }
            }

            // Name
            Text(skill.name)
                .font(.system(size: 22, weight: .bold))
                .multilineTextAlignment(.center)

            // Author
            HStack(spacing: 6) {
                Image(systemName: "person.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                Text(skill.authorName)
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }

            // Category badge
            HStack(spacing: 6) {
                Image(systemName: skill.category.iconName)
                    .font(.system(size: 12))
                Text(skill.category.displayName)
                    .font(.system(size: 12, weight: .medium))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(skill.category.color.opacity(0.12))
            )
            .foregroundStyle(skill.category.color)

            // Version
            Text("v\(skill.version)")
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Stats

    private var statsSection: some View {
        HStack(spacing: 0) {
            statItem(value: String(format: "%.1f", skill.averageRating), label: "評価", icon: "star.fill", color: .yellow)
            Divider().frame(height: 30)
            statItem(value: "\(skill.ratingCount)", label: "レビュー", icon: "text.bubble", color: .blue)
            Divider().frame(height: 30)
            statItem(value: "\(skill.installCount)", label: "インストール", icon: "arrow.down.circle", color: .green)
            Divider().frame(height: 30)
            statItem(value: skill.priceTokens == 0 ? "無料" : "\(skill.priceTokens)", label: "価格", icon: "dollarsign.circle", color: .orange)
        }
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.subtleSeparator, lineWidth: 0.5)
        )
    }

    private func statItem(value: String, label: String, icon: String, color: Color) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                    .foregroundStyle(color)
                Text(value)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
            }
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Description

    private var descriptionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            ModernSectionHeader(title: "説明", icon: "text.alignleft", color: .blue)

            Text(skill.description)
                .font(.system(size: 14))
                .foregroundStyle(.primary)
                .lineSpacing(4)
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
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

    // MARK: - Tags

    private var tagsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            ModernSectionHeader(title: "タグ", icon: "tag", color: .teal)

            FlowLayout(spacing: 6) {
                ForEach(skill.tags, id: \.self) { tag in
                    Text("#\(tag)")
                        .font(.system(size: 12, weight: .medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            Capsule()
                                .fill(Color.teal.opacity(0.1))
                        )
                        .foregroundStyle(.teal)
                }
            }
        }
    }

    // MARK: - MCP Config

    private var mcpConfigSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            ModernSectionHeader(title: "MCP設定", icon: "gearshape.2", color: .orange)

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "server.rack")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                    Text(skill.mcpConfig.serverName)
                        .font(.system(size: 14, weight: .medium))
                }

                Text(skill.mcpConfig.serverDescription)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)

                Divider()

                // Tools list
                Text("ツール (\(skill.mcpConfig.tools.count))")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)

                ForEach(skill.mcpConfig.tools, id: \.name) { tool in
                    HStack(spacing: 8) {
                        Image(systemName: "wrench.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.orange)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(tool.name)
                                .font(.system(size: 13, weight: .medium))
                            Text(tool.description)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                }

                // Action type badge
                if let firstTool = skill.mcpConfig.tools.first {
                    HStack(spacing: 4) {
                        Image(systemName: actionTypeIcon(firstTool.actionType))
                            .font(.system(size: 10))
                        Text(actionTypeLabel(firstTool.actionType))
                            .font(.system(size: 11, weight: .medium))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(Color.orange.opacity(0.1))
                    )
                    .foregroundStyle(.orange)
                }
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

    private func actionTypeIcon(_ type: String) -> String {
        switch type {
        case "httpRequest": return "network"
        case "shortcut": return "command"
        case "urlScheme": return "link"
        case "javascript": return "curlybraces"
        default: return "questionmark.circle"
        }
    }

    private func actionTypeLabel(_ type: String) -> String {
        switch type {
        case "httpRequest": return "HTTP Request"
        case "shortcut": return "ショートカット"
        case "urlScheme": return "URL Scheme"
        case "javascript": return "JavaScript"
        default: return type
        }
    }

    // MARK: - Reviews

    private var reviewsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                ModernSectionHeader(title: "レビュー", icon: "text.bubble", color: .purple)

                Spacer()

                if isInstalled {
                    Button(action: { showingReviewSheet = true }) {
                        HStack(spacing: 4) {
                            Image(systemName: "square.and.pencil")
                                .font(.system(size: 12))
                            Text("書く")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .foregroundStyle(.purple)
                    }
                }
            }

            if reviews.isEmpty {
                Text("まだレビューはありません")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color.cardBackground)
                    )
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(reviews.prefix(5).enumerated()), id: \.element.id) { index, review in
                        reviewRow(review)

                        if index < min(reviews.count, 5) - 1 {
                            Divider()
                                .padding(.horizontal, 14)
                        }
                    }
                }
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
    }

    private func reviewRow(_ review: SkillReview) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(review.userName)
                    .font(.system(size: 13, weight: .semibold))

                HStack(spacing: 2) {
                    ForEach(1...5, id: \.self) { star in
                        Image(systemName: star <= review.rating ? "star.fill" : "star")
                            .font(.system(size: 10))
                            .foregroundStyle(star <= review.rating ? .yellow : .secondary.opacity(0.3))
                    }
                }

                Spacer()

                Text(formatDate(review.createdAt))
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }

            Text(review.comment)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .lineLimit(3)
        }
        .padding(14)
    }

    // MARK: - Action Button

    private var actionButton: some View {
        VStack(spacing: 10) {
            if isInstalled {
                // Uninstall button
                Button(action: { showingUninstallAlert = true }) {
                    HStack(spacing: 8) {
                        Image(systemName: "trash")
                        Text("アンインストール")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color.red.opacity(0.1))
                    )
                    .foregroundStyle(.red)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color.red.opacity(0.3), lineWidth: 1)
                    )
                }

                if installSuccess {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("インストール済み")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.green)
                    }
                }
            } else {
                // Install button
                Button(action: {
                    Task {
                        let success = await manager.installSkill(skill)
                        if success {
                            installSuccess = true
                        }
                    }
                }) {
                    if manager.isInstalling {
                        ProgressView()
                            .tint(.white)
                    } else {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.down.circle.fill")
                            if skill.priceTokens > 0 {
                                Text("インストール (\(skill.priceTokens) トークン)")
                                    .font(.system(size: 16, weight: .semibold))
                            } else {
                                Text("インストール (無料)")
                                    .font(.system(size: 16, weight: .semibold))
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    LinearGradient(
                        colors: [.purple, .indigo],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .shadow(color: .purple.opacity(0.3), radius: 8, y: 4)
                .disabled(manager.isInstalling)
            }

            // Error message
            if let error = manager.error {
                Text(error)
                    .font(.system(size: 13))
                    .foregroundStyle(.red)
            }
        }
    }

    // MARK: - Helpers

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy/MM/dd"
        return formatter.string(from: date)
    }
}

// MARK: - Write Review Sheet

struct WriteReviewSheet: View {
    let skillId: String
    let skillName: String

    @StateObject private var manager = SkillMarketplaceManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var rating = 5
    @State private var comment = ""
    @State private var isSubmitting = false
    @State private var submitError: String?

    var body: some View {
        NavigationStack {
            ZStack {
                Color.chatBackgroundDynamic
                    .ignoresSafeArea()

                VStack(spacing: 24) {
                    // Skill name
                    Text(skillName)
                        .font(.system(size: 18, weight: .bold))
                        .padding(.top, 20)

                    // Star rating
                    HStack(spacing: 12) {
                        ForEach(1...5, id: \.self) { star in
                            Button(action: { rating = star }) {
                                Image(systemName: star <= rating ? "star.fill" : "star")
                                    .font(.system(size: 32))
                                    .foregroundStyle(star <= rating ? .yellow : .secondary.opacity(0.3))
                            }
                        }
                    }

                    Text(ratingLabel)
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)

                    // Comment
                    VStack(alignment: .leading, spacing: 6) {
                        Text("コメント")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)

                        TextField("このスキルについてのレビュー...", text: $comment, axis: .vertical)
                            .textFieldStyle(.plain)
                            .lineLimit(3...6)
                            .padding(12)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.cardBackground)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.subtleSeparator, lineWidth: 0.5)
                            )
                    }
                    .padding(.horizontal, 20)

                    if let error = submitError {
                        Text(error)
                            .font(.system(size: 13))
                            .foregroundStyle(.red)
                    }

                    // Submit button
                    Button(action: {
                        isSubmitting = true
                        Task {
                            let success = await manager.reviewSkill(
                                skillId: skillId,
                                rating: rating,
                                comment: comment
                            )
                            isSubmitting = false
                            if success {
                                dismiss()
                            } else {
                                submitError = "送信に失敗しました"
                            }
                        }
                    }) {
                        if isSubmitting {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Text("レビューを送信")
                                .font(.system(size: 16, weight: .semibold))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        LinearGradient(
                            colors: [.purple, .indigo],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .padding(.horizontal, 20)
                    .disabled(comment.isEmpty || isSubmitting)
                    .opacity(comment.isEmpty ? 0.6 : 1)

                    Spacer()
                }
            }
            .navigationTitle("レビューを書く")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
            }
        }
    }

    private var ratingLabel: String {
        switch rating {
        case 1: return "不満"
        case 2: return "改善の余地あり"
        case 3: return "普通"
        case 4: return "良い"
        case 5: return "素晴らしい"
        default: return ""
        }
    }
}

#Preview {
    SkillDetailView(skill: Skill(
        id: "preview-1",
        name: "Translation Helper",
        description: "AI翻訳ヘルパー。日本語と英語の翻訳をサポートします。",
        authorId: "user-1",
        authorName: "Yuki",
        category: .language,
        version: "1.0.0",
        mcpConfig: SkillMCPConfig(
            serverId: "translation-helper",
            serverName: "Translation Helper",
            serverDescription: "翻訳ツール",
            icon: "globe",
            tools: []
        ),
        iconUrl: nil,
        tags: ["翻訳", "言語", "英語"],
        priceTokens: 0,
        installCount: 42,
        averageRating: 4.5,
        ratingCount: 12,
        status: .approved,
        createdAt: Date()
    ))
}
