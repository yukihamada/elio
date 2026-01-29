import SwiftUI

/// View for getting user consent before submitting feedback
struct FeedbackConsentView: View {
    let feedbackType: FeedbackType
    let aiResponse: String
    let userMessage: String?
    let conversationId: String?
    let modelId: String?
    let onSubmit: (Bool, String?) -> Void  // (rememberChoice, optionalComment)
    let onCancel: () -> Void

    @State private var comment = ""
    @State private var rememberChoice = true
    @Environment(\.dismiss) private var dismiss

    private var isPositive: Bool {
        feedbackType == .positive
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Header
                    headerSection

                    // What data will be sent
                    dataSection

                    // Privacy notes
                    privacySection

                    // Optional comment
                    commentSection

                    // Remember choice toggle
                    rememberSection

                    Spacer(minLength: 20)
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(String(localized: "feedback.consent.title", defaultValue: "フィードバックを送信"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "common.cancel")) {
                        onCancel()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "feedback.send", defaultValue: "送信")) {
                        onSubmit(rememberChoice, comment.isEmpty ? nil : comment)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }

    // MARK: - Header Section

    private var headerSection: some View {
        VStack(spacing: 12) {
            // Feedback icon
            ZStack {
                Circle()
                    .fill(isPositive ? Color.green.opacity(0.15) : Color.orange.opacity(0.15))
                    .frame(width: 60, height: 60)

                Image(systemName: isPositive ? "hand.thumbsup.fill" : "hand.thumbsdown.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(isPositive ? .green : .orange)
            }

            Text(isPositive
                 ? String(localized: "feedback.positive.title", defaultValue: "良い回答でしたか？")
                 : String(localized: "feedback.negative.title", defaultValue: "改善が必要ですか？"))
                .font(.headline)

            Text(String(localized: "feedback.explanation", defaultValue: "フィードバックはAIの品質向上に役立てられます。送信前に、どのようなデータが送られるかをご確認ください。"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical)
    }

    // MARK: - Data Section

    private var dataSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(String(localized: "feedback.data.section", defaultValue: "送信されるデータ"),
                  systemImage: "doc.text")
                .font(.headline)

            VStack(spacing: 0) {
                dataRow(
                    icon: "bubble.left.and.bubble.right",
                    title: String(localized: "feedback.data.conversation", defaultValue: "会話内容"),
                    description: String(localized: "feedback.data.conversation.desc", defaultValue: "AIの回答と、その直前のあなたのメッセージ"),
                    isLast: false
                )

                dataRow(
                    icon: "cpu",
                    title: String(localized: "feedback.data.model", defaultValue: "モデル情報"),
                    description: String(localized: "feedback.data.model.desc", defaultValue: "使用したAIモデルの名前"),
                    isLast: false
                )

                dataRow(
                    icon: "clock",
                    title: String(localized: "feedback.data.timestamp", defaultValue: "日時"),
                    description: String(localized: "feedback.data.timestamp.desc", defaultValue: "フィードバックの送信日時"),
                    isLast: true
                )
            }
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    private func dataRow(icon: String, title: String, description: String, isLast: Bool) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundStyle(.blue)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.medium)

                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            if !isLast {
                Divider()
                    .padding(.leading, 52)
            }
        }
    }

    // MARK: - Privacy Section

    private var privacySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(String(localized: "feedback.privacy.section", defaultValue: "プライバシーについて"),
                  systemImage: "lock.shield")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                privacyNote(
                    icon: "person.slash",
                    text: String(localized: "feedback.privacy.anonymous", defaultValue: "個人を特定する情報は送信されません")
                )

                privacyNote(
                    icon: "sparkles",
                    text: String(localized: "feedback.privacy.improvement", defaultValue: "AIの品質向上のみに使用されます")
                )

                privacyNote(
                    icon: "hand.raised",
                    text: String(localized: "feedback.privacy.optional", defaultValue: "フィードバックの送信は完全に任意です")
                )
            }
            .padding()
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    private func privacyNote(icon: String, text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(.green)
                .frame(width: 20)

            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Comment Section

    private var commentSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(String(localized: "feedback.comment.section", defaultValue: "コメント（任意）"),
                  systemImage: "text.bubble")
                .font(.headline)

            TextField(
                String(localized: "feedback.comment.placeholder", defaultValue: "改善点や良かった点があれば教えてください..."),
                text: $comment,
                axis: .vertical
            )
            .textFieldStyle(.plain)
            .padding(12)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .lineLimit(3...6)
        }
    }

    // MARK: - Remember Section

    private var rememberSection: some View {
        Toggle(isOn: $rememberChoice) {
            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "feedback.remember.title", defaultValue: "この選択を記憶する"))
                    .font(.subheadline)

                Text(String(localized: "feedback.remember.description", defaultValue: "次回から確認なしでフィードバックを送信します"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Preview

#Preview {
    FeedbackConsentView(
        feedbackType: .positive,
        aiResponse: "これはAIの回答のサンプルです。",
        userMessage: "これはユーザーの質問です。",
        conversationId: "conv-123",
        modelId: "eliochat-2b",
        onSubmit: { _, _ in },
        onCancel: {}
    )
}
