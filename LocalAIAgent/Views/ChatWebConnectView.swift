import SwiftUI
import CoreImage.CIFilterBuiltins

/// Quick connect view for ChatWeb.ai — QR code + one-tap connect
struct ChatWebConnectView: View {
    @ObservedObject var chatModeManager: ChatModeManager
    var syncManager: SyncManager?
    @Environment(\.dismiss) private var dismiss
    @State private var showingLoginSheet = false
    @State private var showingBonusAlert = false
    @State private var showingKeyActions = false
    @ObservedObject private var tokenManager = TokenManager.shared
    @ObservedObject private var chatWebAPIKeyManager = ChatWebAPIKeyManager.shared

    private var chatWebURL: String {
        "https://chatweb.ai"
    }

    private var deepLinkURL: String {
        // Deep link for ChatWeb.ai to connect back to ElioChat
        "https://chatweb.ai/?ref=elio&channel=elio"
    }

    private var hasReceivedBonus: Bool {
        UserDefaults.standard.bool(forKey: "chatweb_connection_bonus_received")
    }

    private func grantConnectionBonus() {
        guard !hasReceivedBonus else { return }
        tokenManager.earn(10000, reason: .chatWebBonus)
        UserDefaults.standard.set(true, forKey: "chatweb_connection_bonus_received")
        showingBonusAlert = true

        // Haptic feedback
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    VStack(spacing: 12) {
                        HStack(spacing: 4) {
                            Image(systemName: "cloud.fill")
                                .font(.system(size: 36))
                                .foregroundStyle(.indigo)
                            Image(systemName: "plus")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(.secondary)
                            Image(systemName: "iphone")
                                .font(.system(size: 36))
                                .foregroundStyle(.green)
                        }

                        Text("Elio Chat + ChatWeb.ai")
                            .font(.title2.bold())

                        Text(String(localized: "chatweb.connect.desc", defaultValue: "Use cloud AI when you need more power. Switch seamlessly between offline and cloud."))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 16)

                    // Device API Key Status
                    if let apiKey = chatWebAPIKeyManager.apiKey {
                        HStack(spacing: 12) {
                            Image(systemName: "checkmark.shield.fill")
                                .font(.system(size: 20))
                                .foregroundStyle(.green)

                            VStack(alignment: .leading, spacing: 4) {
                                Text("デバイス接続済み")
                                    .font(.system(size: 15, weight: .semibold))
                                Text("API Key: \(apiKey.prefix(12))...")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Button(action: { showingKeyActions = true }) {
                                Image(systemName: "ellipsis.circle")
                                    .font(.system(size: 18))
                            }
                        }
                        .padding(12)
                        .background(Color.green.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .padding(.horizontal, 16)
                    } else if chatWebAPIKeyManager.keyStatus == .generating {
                        HStack(spacing: 12) {
                            ProgressView()
                            Text("デバイスキーを生成中...")
                                .font(.system(size: 14))
                                .foregroundStyle(.secondary)
                        }
                        .padding(12)
                        .background(Color.orange.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .padding(.horizontal, 16)
                    }

                    // QR Code to open ChatWeb.ai
                    VStack(spacing: 12) {
                        Text(String(localized: "chatweb.qr.title"))
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.secondary)

                        if let qrImage = generateQRCode(from: deepLinkURL) {
                            Image(uiImage: qrImage)
                                .interpolation(.none)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 200, height: 200)
                                .padding(16)
                                .background(Color.white)
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                                .shadow(color: .black.opacity(0.1), radius: 8, y: 4)
                        }

                        Text(String(localized: "chatweb.qr.scan.hint", defaultValue: "Scan from another device to open ChatWeb.ai"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color(.tertiarySystemBackground))
                    )
                    .padding(.horizontal, 16)

                    // First-time connection bonus badge
                    if !hasReceivedBonus {
                        HStack(spacing: 8) {
                            Image(systemName: "gift.fill")
                                .foregroundStyle(.yellow)
                            Text("初回接続で10,000トークンプレゼント！")
                                .font(.system(size: 14, weight: .semibold))
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity)
                        .background(
                            LinearGradient(
                                colors: [.yellow.opacity(0.2), .orange.opacity(0.2)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.yellow.opacity(0.5), lineWidth: 1)
                        )
                        .padding(.horizontal, 16)
                    }

                    // Quick actions
                    VStack(spacing: 12) {
                        // One-click cloud mode
                        Button(action: {
                            chatModeManager.setMode(.chatweb)
                            grantConnectionBonus()
                            dismiss()
                        }) {
                            HStack(spacing: 12) {
                                Image(systemName: "bolt.fill")
                                    .font(.system(size: 18))
                                    .foregroundStyle(.white)
                                    .frame(width: 36, height: 36)
                                    .background(Color.indigo.gradient)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(String(localized: "chatweb.switch.cloud", defaultValue: "Switch to Cloud Mode"))
                                        .font(.system(size: 15, weight: .semibold))
                                    Text(String(localized: "chatweb.switch.cloud.desc", defaultValue: "Use ChatWeb.ai for faster, smarter responses"))
                                        .font(.system(size: 12))
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                Image(systemName: "chevron.right")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(16)
                            .background(
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(Color(.tertiarySystemBackground))
                            )
                        }
                        .buttonStyle(.plain)

                        // Open ChatWeb.ai in browser
                        Button(action: {
                            if let url = URL(string: chatWebURL) {
                                UIApplication.shared.open(url)
                            }
                        }) {
                            HStack(spacing: 12) {
                                Image(systemName: "safari")
                                    .font(.system(size: 18))
                                    .foregroundStyle(.white)
                                    .frame(width: 36, height: 36)
                                    .background(Color.blue.gradient)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(String(localized: "chatweb.open"))
                                        .font(.system(size: 15, weight: .semibold))
                                    Text("chatweb.ai")
                                        .font(.system(size: 12))
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                Image(systemName: "arrow.up.right.square")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(16)
                            .background(
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(Color(.tertiarySystemBackground))
                            )
                        }
                        .buttonStyle(.plain)

                        // Sign in to sync
                        if let sm = syncManager, !sm.isLoggedIn {
                            Button(action: { showingLoginSheet = true }) {
                                HStack(spacing: 12) {
                                    Image(systemName: "person.crop.circle")
                                        .font(.system(size: 18))
                                        .foregroundStyle(.white)
                                        .frame(width: 36, height: 36)
                                        .background(Color.green.gradient)
                                        .clipShape(RoundedRectangle(cornerRadius: 10))

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(String(localized: "chatweb.signin", defaultValue: "Sign in to ChatWeb.ai"))
                                            .font(.system(size: 15, weight: .semibold))
                                        Text(String(localized: "chatweb.signin.desc", defaultValue: "Sync conversations across all devices"))
                                            .font(.system(size: 12))
                                            .foregroundStyle(.secondary)
                                    }

                                    Spacer()

                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(.secondary)
                                }
                                .padding(16)
                                .background(
                                    RoundedRectangle(cornerRadius: 14)
                                        .fill(Color(.tertiarySystemBackground))
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)

                    // Benefits
                    VStack(alignment: .leading, spacing: 8) {
                        Label(
                            String(localized: "chatweb.benefit.models", defaultValue: "Access GPT-4o, Claude, Gemini & more"),
                            systemImage: "sparkles"
                        )
                        Label(
                            String(localized: "chatweb.benefit.sync", defaultValue: "Sync conversations between Elio & ChatWeb"),
                            systemImage: "arrow.triangle.2.circlepath"
                        )
                        Label(
                            String(localized: "chatweb.benefit.free", defaultValue: "Free credits included — no API key needed"),
                            systemImage: "gift"
                        )
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(16)
                }
            }
            .navigationTitle("ChatWeb.ai")
            #if !targetEnvironment(macCatalyst)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "common.close")) {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showingLoginSheet) {
                if let sm = syncManager {
                    ChatWebLoginView()
                        .environmentObject(sm)
                }
            }
            .confirmationDialog("デバイスAPIキー", isPresented: $showingKeyActions) {
                Button("APIキーをコピー") {
                    UIPasteboard.general.string = chatWebAPIKeyManager.apiKey
                }

                Button("キーを再生成") {
                    Task {
                        try? await chatWebAPIKeyManager.regenerateKey()
                    }
                }

                Button("キーを削除", role: .destructive) {
                    try? chatWebAPIKeyManager.deleteKey()
                }

                Button("キャンセル", role: .cancel) {}
            }
            .alert("🎉 ボーナス獲得！", isPresented: $showingBonusAlert) {
                Button("OK") {}
            } message: {
                Text("ChatWeb.ai接続ボーナスとして10,000トークンを獲得しました！\n\nクラウドAIでより高度な会話をお楽しみください。")
            }
        }
    }

    // MARK: - QR Code Generation

    private func generateQRCode(from string: String) -> UIImage? {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"

        guard let outputImage = filter.outputImage else { return nil }

        // Scale up the QR code
        let scale = CGAffineTransform(scaleX: 10, y: 10)
        let scaledImage = outputImage.transformed(by: scale)

        guard let cgImage = context.createCGImage(scaledImage, from: scaledImage.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
