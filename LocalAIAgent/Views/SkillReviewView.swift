import SwiftUI

// MARK: - Skill Review View

/// For curators to review a pending skill submission.
/// Shows skill details, MCP config, safety checklist, and approve/reject actions.
struct SkillReviewView: View {
    let skill: PendingSkill

    @StateObject private var curatorManager = CuratorManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var comment = ""
    @State private var showingApproveConfirmation = false
    @State private var showingRejectConfirmation = false
    @State private var isSubmitting = false
    @State private var submissionSuccess = false

    // Safety checklist
    @State private var checkNoMaliciousCalls = false
    @State private var checkNoDataExfiltration = false
    @State private var checkPermissionsAppropriate = false
    @State private var checkDescriptionMatches = false
    @State private var checkWorksOffline = false

    private var allChecksCompleted: Bool {
        checkNoMaliciousCalls &&
        checkNoDataExfiltration &&
        checkPermissionsAppropriate &&
        checkDescriptionMatches
        // checkWorksOffline is optional
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.chatBackgroundDynamic
                    .ignoresSafeArea()

                if submissionSuccess {
                    successView
                } else {
                    reviewForm
                }
            }
            .navigationTitle(String(localized: "review.title", defaultValue: "Skill Review"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "common.cancel")) { dismiss() }
                }
            }
            .alert(String(localized: "review.approve.confirm.title", defaultValue: "スキルを承認"), isPresented: $showingApproveConfirmation) {
                Button(String(localized: "common.cancel"), role: .cancel) {}
                Button(String(localized: "review.approve.action", defaultValue: "承認"), role: .none) {
                    submitReview(approve: true)
                }
            } message: {
                Text(String(localized: "review.approve.confirm.message", defaultValue: "このスキルをマーケットプレイスに公開します。"))
            }
            .alert(String(localized: "review.reject.confirm.title", defaultValue: "スキルを却下"), isPresented: $showingRejectConfirmation) {
                Button(String(localized: "common.cancel"), role: .cancel) {}
                Button(String(localized: "review.reject.action", defaultValue: "却下"), role: .destructive) {
                    submitReview(approve: false)
                }
            } message: {
                Text(String(localized: "review.reject.confirm.message", defaultValue: "却下理由をコメントに記入してください。作者にフィードバックが送信されます。"))
            }
        }
    }

    // MARK: - Review Form

    private var reviewForm: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(spacing: 20) {
                // Skill info card
                skillInfoCard

                // MCP Config section
                if let config = skill.mcpConfig, !config.isEmpty {
                    mcpConfigSection(config)
                }

                // Safety checklist
                safetyChecklistSection

                // Comment field
                commentSection

                // Action buttons
                actionButtons
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    // MARK: - Skill Info

    private var skillInfoCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Skill header
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(
                            LinearGradient(
                                colors: [.purple.opacity(0.15), .indigo.opacity(0.15)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 52, height: 52)

                    Image(systemName: "puzzlepiece.extension.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.purple, .indigo],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(skill.name)
                        .font(.system(size: 18, weight: .bold))

                    if let category = skill.category {
                        Text(category)
                            .font(.system(size: 12, weight: .medium))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Color.purple.opacity(0.12))
                            .foregroundStyle(.purple)
                            .clipShape(Capsule())
                    }
                }

                Spacer()
            }

            Divider()

            // Description
            VStack(alignment: .leading, spacing: 4) {
                Text(String(localized: "review.description.label", defaultValue: "説明"))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)

                Text(skill.description)
                    .font(.system(size: 14))
                    .lineSpacing(4)
            }

            Divider()

            // Author info
            HStack(spacing: 8) {
                Image(systemName: "person.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)

                Text(skill.authorName)
                    .font(.system(size: 14, weight: .medium))

                Spacer()

                Text(skill.submittedAt)
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(16)
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

    // MARK: - MCP Config

    private func mcpConfigSection(_ config: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ModernSectionHeader(
                title: "MCP Config",
                icon: "gearshape.2.fill",
                gradient: [.indigo, .purple]
            )

            ScrollView(.horizontal, showsIndicators: true) {
                Text(config)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.primary)
                    .padding(14)
            }
            .frame(maxHeight: 200)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.tertiarySystemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.subtleSeparator, lineWidth: 0.5)
            )
        }
    }

    // MARK: - Safety Checklist

    private var safetyChecklistSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            ModernSectionHeader(
                title: String(localized: "review.safety.title", defaultValue: "Safety Checklist"),
                icon: "shield.checkered",
                gradient: [.green, .teal]
            )

            VStack(spacing: 0) {
                safetyCheckItem(
                    title: String(localized: "review.check.no_malicious", defaultValue: "悪意のあるネットワーク通信がない"),
                    isChecked: $checkNoMaliciousCalls,
                    isRequired: true
                )

                Divider().padding(.leading, 52)

                safetyCheckItem(
                    title: String(localized: "review.check.no_exfiltration", defaultValue: "データの外部送信がない"),
                    isChecked: $checkNoDataExfiltration,
                    isRequired: true
                )

                Divider().padding(.leading, 52)

                safetyCheckItem(
                    title: String(localized: "review.check.permissions", defaultValue: "要求パーミッションが適切"),
                    isChecked: $checkPermissionsAppropriate,
                    isRequired: true
                )

                Divider().padding(.leading, 52)

                safetyCheckItem(
                    title: String(localized: "review.check.description_matches", defaultValue: "説明と機能が一致する"),
                    isChecked: $checkDescriptionMatches,
                    isRequired: true
                )

                Divider().padding(.leading, 52)

                safetyCheckItem(
                    title: String(localized: "review.check.works_offline", defaultValue: "オフラインで動作する（該当する場合）"),
                    isChecked: $checkWorksOffline,
                    isRequired: false
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

            if !allChecksCompleted {
                Text(String(localized: "review.safety.incomplete", defaultValue: "全ての必須チェック項目を確認してください"))
                    .font(.system(size: 12))
                    .foregroundStyle(.orange)
                    .padding(.leading, 4)
            }
        }
    }

    private func safetyCheckItem(title: String, isChecked: Binding<Bool>, isRequired: Bool) -> some View {
        Button(action: {
            withAnimation(.easeInOut(duration: 0.15)) {
                isChecked.wrappedValue.toggle()
            }
        }) {
            HStack(spacing: 12) {
                Image(systemName: isChecked.wrappedValue ? "checkmark.square.fill" : "square")
                    .font(.system(size: 20))
                    .foregroundStyle(isChecked.wrappedValue ? .green : .secondary)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 15))
                        .foregroundStyle(.primary)

                    if isRequired {
                        Text(String(localized: "review.check.required", defaultValue: "必須"))
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.orange)
                    }
                }

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Comment Section

    private var commentSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            ModernSectionHeader(
                title: String(localized: "review.comment.title", defaultValue: "Comment"),
                icon: "text.bubble.fill",
                gradient: [.blue, .cyan]
            )

            TextEditor(text: $comment)
                .font(.system(size: 14))
                .scrollContentBackground(.hidden)
                .frame(minHeight: 80, maxHeight: 150)
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.cardBackground)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.subtleSeparator, lineWidth: 0.5)
                )
                .overlay(alignment: .topLeading) {
                    if comment.isEmpty {
                        Text(String(localized: "review.comment.placeholder", defaultValue: "レビューコメントを入力..."))
                            .font(.system(size: 14))
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 20)
                            .allowsHitTesting(false)
                    }
                }

            Text(String(localized: "review.comment.hint", defaultValue: "却下の場合は改善点を具体的に記入してください"))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .padding(.leading, 4)
        }
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        HStack(spacing: 12) {
            // Reject button
            Button(action: { showingRejectConfirmation = true }) {
                HStack(spacing: 6) {
                    Image(systemName: "xmark.circle.fill")
                    Text(String(localized: "review.reject.button", defaultValue: "却下"))
                        .font(.system(size: 15, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.red.opacity(0.12))
                )
                .foregroundStyle(.red)
            }
            .disabled(isSubmitting)

            // Approve button
            Button(action: { showingApproveConfirmation = true }) {
                HStack(spacing: 6) {
                    if isSubmitting {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: "checkmark.circle.fill")
                        Text(String(localized: "review.approve.button", defaultValue: "承認"))
                            .font(.system(size: 15, weight: .semibold))
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    LinearGradient(
                        colors: allChecksCompleted ? [.green, .teal] : [.gray, .gray.opacity(0.7)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .shadow(color: allChecksCompleted ? .green.opacity(0.3) : .clear, radius: 8, y: 4)
            }
            .disabled(!allChecksCompleted || isSubmitting)
        }
    }

    // MARK: - Success View

    private var successView: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 60))
                .foregroundStyle(.green)

            Text(String(localized: "review.submitted.title", defaultValue: "レビュー送信完了"))
                .font(.system(size: 22, weight: .bold, design: .rounded))

            Text(String(localized: "review.submitted.message", defaultValue: "レビューが正常に送信されました"))
                .font(.system(size: 15))
                .foregroundStyle(.secondary)

            Spacer()

            Button(action: { dismiss() }) {
                Text(String(localized: "common.done"))
                    .font(.system(size: 16, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        LinearGradient(
                            colors: [.purple, .indigo],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
    }

    // MARK: - Submit Review

    private func submitReview(approve: Bool) {
        isSubmitting = true
        Task {
            let success: Bool
            if approve {
                success = await curatorManager.approveSkill(skillId: skill.id, comment: comment)
            } else {
                success = await curatorManager.rejectSkill(skillId: skill.id, comment: comment)
            }

            isSubmitting = false
            if success {
                withAnimation(.spring(response: 0.5)) {
                    submissionSuccess = true
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    SkillReviewView(skill: PendingSkill(
        id: "test-1",
        name: "Weather MCP Server",
        description: "Get current weather data for any location. Supports temperature, humidity, wind speed, and forecast.",
        authorName: "tanaka",
        authorId: "user-123",
        mcpConfig: """
        {
          "name": "weather",
          "version": "1.0.0",
          "tools": [
            {
              "name": "get_weather",
              "description": "Get current weather",
              "parameters": {
                "location": { "type": "string" }
              }
            }
          ]
        }
        """,
        submittedAt: "2026-02-10",
        category: "Utilities"
    ))
}
