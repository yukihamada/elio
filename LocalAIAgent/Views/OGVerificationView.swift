import SwiftUI

// MARK: - OG Verification View

/// Allows HamaDAO NFT holders to verify their OG status.
/// Flow: Enter wallet address -> Verify -> Success animation with benefits
struct OGVerificationView: View {
    @ObservedObject private var curatorManager = CuratorManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var walletAddress = ""
    @State private var showSuccess = false
    @State private var showError = false
    @State private var animateGlasses = false
    @State private var benefitAnimations: [Bool] = Array(repeating: false, count: 5)

    var body: some View {
        NavigationStack {
            ZStack {
                Color.chatBackgroundDynamic
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {
                        if showSuccess {
                            successView
                        } else {
                            verificationForm
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                }
            }
            .navigationTitle(String(localized: "og.verification.title", defaultValue: "OG Verification"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(String(localized: "common.done")) { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
    }

    // MARK: - Verification Form

    private var verificationForm: some View {
        VStack(spacing: 28) {
            // Nouns glasses header graphic
            VStack(spacing: 16) {
                ZStack {
                    // Glow background
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [Color.ogGold.opacity(0.2), Color.ogGold.opacity(0)],
                                center: .center,
                                startRadius: 20,
                                endRadius: 80
                            )
                        )
                        .frame(width: 160, height: 160)

                    // Nouns glasses icon
                    VStack(spacing: 4) {
                        NounsGlassesShape()
                            .fill(
                                LinearGradient(
                                    colors: [Color.ogGold, Color.ogAmber],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: 80, height: 32)
                            .scaleEffect(animateGlasses ? 1.05 : 1.0)

                        Text("HamaDAO")
                            .font(.system(size: 14, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color.ogGold)
                    }
                }
                .onAppear {
                    withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                        animateGlasses = true
                    }
                }

                Text(String(localized: "og.verification.header", defaultValue: "HamaDAO OGメンバーですか?"))
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)

                Text(String(localized: "og.verification.description", defaultValue: "ウォレットアドレスを入力してHamaDAO NFTの保有を確認します。世界で6人のみのOGメンバーに特別な特典が付与されます。"))
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
            }
            .padding(.top, 12)

            // Contract info
            HStack(spacing: 8) {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Contract")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text(CuratorManager.hamadaoContract)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(.tertiarySystemBackground))
            )

            // Wallet address input
            VStack(alignment: .leading, spacing: 8) {
                Text(String(localized: "og.verification.wallet.label", defaultValue: "Ethereumウォレットアドレス"))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)

                HStack(spacing: 10) {
                    Image(systemName: "wallet.pass")
                        .font(.system(size: 16))
                        .foregroundStyle(Color.ogGold)

                    TextField("0x...", text: $walletAddress)
                        .font(.system(size: 15, design: .monospaced))
                        .textContentType(.none)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
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

            // Error message
            if showError, let error = curatorManager.errorMessage {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.red)
                    Text(error)
                        .font(.system(size: 13))
                        .foregroundStyle(.red)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.red.opacity(0.1))
                )
            }

            // Verify button
            Button(action: {
                Task {
                    showError = false
                    let success = await curatorManager.verifyOGStatus(walletAddress: walletAddress)
                    if success {
                        withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                            showSuccess = true
                        }
                        triggerBenefitAnimations()
                    } else {
                        showError = true
                    }
                }
            }) {
                HStack(spacing: 10) {
                    if curatorManager.isVerifying {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: "checkmark.shield.fill")
                        Text(String(localized: "og.verification.verify_button", defaultValue: "Verify"))
                            .font(.system(size: 16, weight: .semibold))
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    LinearGradient(
                        colors: [Color.ogGold, Color.ogAmber],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .shadow(color: Color.ogGold.opacity(0.4), radius: 12, y: 4)
            }
            .disabled(walletAddress.count < 42 || curatorManager.isVerifying)
            .opacity(walletAddress.count < 42 ? 0.6 : 1)

            // Note
            Text(String(localized: "og.verification.note", defaultValue: "ERC-721 balanceOfをチェックします。ウォレットの秘密鍵は不要です。"))
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Success View

    private var successView: some View {
        VStack(spacing: 28) {
            // Animated OG Badge
            AnimatedOGBadge(size: .large)
                .padding(.top, 20)

            VStack(spacing: 8) {
                Text(String(localized: "og.verification.success.title", defaultValue: "OG Badge Unlocked!"))
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.ogGold, Color.ogAmber],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )

                Text(String(localized: "og.verification.success.subtitle", defaultValue: "HamaDAO OGメンバーとして認証されました"))
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
            }

            // Benefits list
            VStack(spacing: 0) {
                benefitRow(
                    emoji: "🏆",
                    title: "OG Founder Badge",
                    subtitle: String(localized: "og.benefit.badge", defaultValue: "プロフィールに特別バッジを表示"),
                    index: 0
                )

                Divider().padding(.leading, 52)

                benefitRow(
                    emoji: "👑",
                    title: "Instant Curator Status",
                    subtitle: String(localized: "og.benefit.curator", defaultValue: "要件をスキップしてキュレーターに即時就任"),
                    index: 1
                )

                Divider().padding(.leading, 52)

                benefitRow(
                    emoji: "💎",
                    title: "Lifetime Pro Access",
                    subtitle: String(localized: "og.benefit.pro", defaultValue: "全てのPro機能に永久アクセス"),
                    index: 2
                )

                Divider().padding(.leading, 52)

                benefitRow(
                    emoji: "🗳️",
                    title: "2x Governance Voting Power",
                    subtitle: String(localized: "og.benefit.voting", defaultValue: "ガバナンス投票で2倍の投票力"),
                    index: 3
                )

                Divider().padding(.leading, 52)

                benefitRow(
                    emoji: "🚀",
                    title: "Alpha/Beta Priority Access",
                    subtitle: String(localized: "og.benefit.alpha", defaultValue: "新機能へのアーリーアクセス"),
                    index: 4
                )
            }
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.cardBackground)
                    .shadow(color: Color.ogGold.opacity(0.1), radius: 12, y: 4)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.ogGold.opacity(0.3), lineWidth: 1)
            )

            // Done button
            Button(action: { dismiss() }) {
                Text(String(localized: "og.verification.continue", defaultValue: "始めましょう"))
                    .font(.system(size: 16, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        LinearGradient(
                            colors: [Color.ogGold, Color.ogAmber],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            }
        }
    }

    private func benefitRow(emoji: String, title: String, subtitle: String, index: Int) -> some View {
        HStack(spacing: 14) {
            Text(emoji)
                .font(.system(size: 24))
                .frame(width: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))

                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 18))
                .foregroundStyle(Color.ogGold)
                .opacity(benefitAnimations.indices.contains(index) && benefitAnimations[index] ? 1 : 0)
                .scaleEffect(benefitAnimations.indices.contains(index) && benefitAnimations[index] ? 1 : 0.5)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private func triggerBenefitAnimations() {
        for i in 0..<5 {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.15) {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                    benefitAnimations[i] = true
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    OGVerificationView()
}
