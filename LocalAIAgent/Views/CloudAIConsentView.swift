import SwiftUI

struct CloudAIConsentView: View {
    let onAgree: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Handle
            RoundedRectangle(cornerRadius: 2)
                .fill(Color(UIColor.tertiaryLabel))
                .frame(width: 36, height: 4)
                .padding(.top, 12)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Header
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 12) {
                            Image(systemName: "cloud.fill")
                                .font(.system(size: 28))
                                .foregroundStyle(.indigo)
                            Text(String(localized: "consent.title", defaultValue: "クラウドAIの利用について"))
                                .font(.system(size: 20, weight: .bold))
                        }

                        Text(String(localized: "consent.subtitle", defaultValue: "有効にする前に以下の内容をご確認ください"))
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 8)

                    // Data disclosure section
                    VStack(alignment: .leading, spacing: 12) {
                        Text(String(localized: "consent.dataSection", defaultValue: "送信されるデータ"))
                            .font(.system(size: 15, weight: .semibold))

                        consentRow(
                            icon: "bubble.left.and.bubble.right.fill",
                            color: .indigo,
                            title: String(localized: "consent.messages", defaultValue: "会話メッセージ"),
                            detail: String(localized: "consent.messages.detail", defaultValue: "入力したメッセージと会話履歴がchatweb.aiのサーバーに送信されます")
                        )
                        consentRow(
                            icon: "iphone",
                            color: .blue,
                            title: String(localized: "consent.deviceId", defaultValue: "デバイス識別子"),
                            detail: String(localized: "consent.deviceId.detail", defaultValue: "個人を特定しない匿名のデバイスIDが送信されます")
                        )
                        consentRow(
                            icon: "lock.shield.fill",
                            color: .green,
                            title: String(localized: "consent.encryption", defaultValue: "通信の暗号化"),
                            detail: String(localized: "consent.encryption.detail", defaultValue: "すべての通信はTLS/HTTPSで暗号化されます")
                        )
                    }
                    .padding(16)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                    // Note
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "info.circle.fill")
                            .foregroundStyle(.secondary)
                            .font(.system(size: 14))
                        Text(String(localized: "consent.note", defaultValue: "クラウドAIを無効にすると、すべての処理がデバイス上で行われ、データは外部に送信されません。設定からいつでも切り替えられます。"))
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }

                    Link(destination: URL(string: "https://chatweb.ai/privacy")!) {
                        Label(
                            String(localized: "consent.privacyPolicy", defaultValue: "プライバシーポリシーを確認する"),
                            systemImage: "arrow.up.right.square"
                        )
                        .font(.system(size: 14))
                        .foregroundStyle(.indigo)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }

            // Buttons
            VStack(spacing: 10) {
                Button(action: onAgree) {
                    Text(String(localized: "consent.agree", defaultValue: "同意してクラウドAIを有効にする"))
                        .font(.system(size: 16, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(
                            LinearGradient(
                                colors: [.indigo, .blue],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }

                Button(action: onCancel) {
                    Text(String(localized: "consent.cancel", defaultValue: "キャンセル（ローカルAIを維持）"))
                        .font(.system(size: 15, weight: .medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 30)
        }
        .background(Color(UIColor.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func consentRow(icon: String, color: Color, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(color)
                .frame(width: 24)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
    }
}
