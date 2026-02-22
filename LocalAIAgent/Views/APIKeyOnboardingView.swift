import SwiftUI

/// Onboarding view shown when user first tries Fast/Genius mode without API keys
struct APIKeyOnboardingView: View {
    let mode: ChatMode
    @Environment(\.dismiss) private var dismiss
    @State private var showingSettings = false

    var body: some View {
        NavigationView {
            ZStack {
                Color.chatBackgroundDynamic
                    .ignoresSafeArea()

                VStack(spacing: 24) {
                    Spacer()

                    // Icon + Title
                    VStack(spacing: 16) {
                        Image(systemName: mode == .fast ? "bolt.fill" : "brain")
                            .font(.system(size: 64))
                            .foregroundStyle(mode.color.gradient)

                        Text(mode.displayName)
                            .font(.title.bold())

                        Text(explainerText)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal)
                    }

                    Spacer()

                    // Two options
                    VStack(spacing: 12) {
                        // Option A: Use own API key
                        Button(action: {
                            markOnboardingSeen()
                            showingSettings = true
                        }) {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Image(systemName: "key.fill")
                                        .foregroundStyle(mode.color)
                                    Text("自分のAPIキーを使う")
                                        .font(.headline)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                }
                                Text(apiKeyOptionText)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.leading)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                            .background(Color(.tertiarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)

                        // Option B: Use Elio tokens
                        Button(action: {
                            markOnboardingSeen()
                            dismiss()
                        }) {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Image(systemName: "creditcard.fill")
                                        .foregroundStyle(mode.color)
                                    Text("Elioトークンで使う")
                                        .font(.headline)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                }
                                Text("コスト: \(mode.tokenCost) トークン/メッセージ")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                            .background(Color(.tertiarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal)

                    Spacer()
                }
                .padding()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        markOnboardingSeen()
                        dismiss()
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
                .environmentObject(AppState.shared)
                .environmentObject(ThemeManager.shared)
                .environmentObject(SyncManager.shared)
        }
    }

    private var explainerText: String {
        mode == .fast
            ? "Groq APIを使った超高速推論モード。自分のAPIキーを設定するか、Elioトークンで利用できます。"
            : "OpenAI、Anthropic、Geminiなど最高峰のAIモデルを利用。自分のAPIキーを設定するか、Elioトークンで利用できます。"
    }

    private var apiKeyOptionText: String {
        mode == .fast
            ? "Groq APIキーを設定。プロバイダー料金のみで利用可能。"
            : "OpenAI、Anthropic、Google等のAPIキーを設定。プロバイダー料金のみで利用可能。"
    }

    private func markOnboardingSeen() {
        UserDefaults.standard.set(true, forKey: "onboarding_\(mode.rawValue)")
    }
}

#Preview {
    APIKeyOnboardingView(mode: .fast)
}

#Preview {
    APIKeyOnboardingView(mode: .genius)
}
