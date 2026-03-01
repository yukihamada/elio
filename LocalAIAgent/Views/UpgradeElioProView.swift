import SwiftUI
import StoreKit

/// アップグレード画面 — ElioChat Pro (¥2,900/月, Nemotron使い放題)
struct UpgradeElioProView: View {
    @EnvironmentObject var syncManager: SyncManager
    @StateObject private var subscriptionManager = SubscriptionManager.shared
    @Environment(\.dismiss) private var dismiss

    private let productId = SubscriptionManager.elioproProductId

    var body: some View {
        NavigationStack {
            ZStack {
                // Background gradient
                LinearGradient(
                    colors: [
                        Color(red: 0.05, green: 0.05, blue: 0.15),
                        Color(red: 0.10, green: 0.05, blue: 0.25)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 32) {
                        // Hero
                        heroSection

                        // Feature list
                        featuresSection

                        // Pricing + CTA
                        ctaSection

                        // Restore + dismiss
                        footerSection
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 40)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }
            }
        }
        .presentationDetents([.large])
    }

    // MARK: - Hero

    private var heroSection: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.green, .teal],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 88, height: 88)
                    .shadow(color: .green.opacity(0.4), radius: 20, y: 8)

                Image(systemName: "cpu.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(.white)
            }

            VStack(spacing: 8) {
                Text("ElioChat Pro")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                Text("Nemotron 9B Japanese 使い放題")
                    .font(.system(size: 16))
                    .foregroundStyle(.white.opacity(0.75))
                    .multilineTextAlignment(.center)
            }
        }
    }

    // MARK: - Features

    private var featuresSection: some View {
        VStack(spacing: 0) {
            featureRow(
                icon: "infinity",
                iconColor: .green,
                title: "Nemotron 9B Japanese 使い放題",
                subtitle: "日本語特化の9Bパラメーター高性能モデル"
            )
            Divider().background(.white.opacity(0.1))
            featureRow(
                icon: "bolt.fill",
                iconColor: .yellow,
                title: "毎月 30,000 クレジット付与",
                subtitle: "〜3,000〜30,000メッセージ相当"
            )
            Divider().background(.white.opacity(0.1))
            featureRow(
                icon: "cloud.fill",
                iconColor: .blue,
                title: "すべてのクラウドモデルで優先アクセス",
                subtitle: "Claude, GPT-4o, Gemini など"
            )
            Divider().background(.white.opacity(0.1))
            featureRow(
                icon: "lock.shield.fill",
                iconColor: .purple,
                title: "プライベート & セキュア",
                subtitle: "会話データは暗号化されて保護されます"
            )
        }
        .background(.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(.white.opacity(0.1), lineWidth: 1)
        )
    }

    private func featureRow(icon: String, iconColor: Color, title: String, subtitle: String) -> some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(iconColor.opacity(0.2))
                    .frame(width: 44, height: 44)
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundStyle(iconColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.6))
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    // MARK: - CTA

    private var ctaSection: some View {
        VStack(spacing: 16) {
            // Price display
            VStack(spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("¥2,900")
                        .font(.system(size: 42, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("/ 月")
                        .font(.system(size: 18))
                        .foregroundStyle(.white.opacity(0.7))
                }
                Text("いつでもキャンセル可能")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.5))
            }

            // Purchase button
            Button {
                Task {
                    await purchaseElioPro()
                }
            } label: {
                HStack(spacing: 10) {
                    if subscriptionManager.isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .black))
                    } else {
                        Image(systemName: "sparkles")
                            .font(.system(size: 16, weight: .semibold))
                        Text("今すぐ始める")
                            .font(.system(size: 18, weight: .bold))
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .background(
                    LinearGradient(
                        colors: [.green, .teal],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .foregroundStyle(.black)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .shadow(color: .green.opacity(0.4), radius: 12, y: 6)
            }
            .disabled(subscriptionManager.isLoading)

            if let errorMessage = subscriptionManager.errorMessage {
                Text(errorMessage)
                    .font(.system(size: 13))
                    .foregroundStyle(.red.opacity(0.8))
                    .multilineTextAlignment(.center)
            }
        }
    }

    // MARK: - Footer

    private var footerSection: some View {
        VStack(spacing: 12) {
            Button {
                Task {
                    await subscriptionManager.restorePurchases()
                    if subscriptionManager.subscriptionStatus == .elioPro {
                        dismiss()
                    }
                }
            } label: {
                Text("購入を復元")
                    .font(.system(size: 15))
                    .foregroundStyle(.white.opacity(0.6))
                    .underline()
            }

            Button {
                dismiss()
            } label: {
                Text("あとで")
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.4))
            }

            Text("App Store の規約に従い自動更新されます。")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.3))
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Purchase

    private func purchaseElioPro() async {
        // Load products if not yet loaded
        if subscriptionManager.products.isEmpty {
            await subscriptionManager.loadProducts()
        }

        guard let product = subscriptionManager.products.first(where: { $0.id == productId }) else {
            // Product not found in App Store — show error
            return
        }

        do {
            let transaction = try await subscriptionManager.purchase(product)
            if transaction != nil {
                // Purchase successful
                dismiss()
            }
        } catch {
            // Error already set in subscriptionManager.errorMessage
        }
    }
}

#Preview {
    UpgradeElioProView()
        .environmentObject(SyncManager.shared)
}
