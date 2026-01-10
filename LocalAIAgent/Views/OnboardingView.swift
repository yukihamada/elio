import SwiftUI

struct OnboardingView: View {
    @Binding var hasCompletedOnboarding: Bool
    @EnvironmentObject var appState: AppState
    @State private var currentPage = 0
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.chatBackgroundDynamic
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Skip button
                HStack {
                    Spacer()
                    Button("スキップ") {
                        completeOnboarding()
                    }
                    .foregroundStyle(.secondary)
                    .padding(.trailing, 20)
                    .padding(.top, 16)
                }

                // Page content
                TabView(selection: $currentPage) {
                    welcomePage
                        .tag(0)

                    featuresPage
                        .tag(1)

                    privacyPage
                        .tag(2)

                    getStartedPage
                        .tag(3)
                }
                .tabViewStyle(.page(indexDisplayMode: .always))

                // Bottom buttons
                VStack(spacing: 16) {
                    if currentPage < 3 {
                        Button(action: { withAnimation { currentPage += 1 } }) {
                            Text("次へ")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(Color.accentColor)
                                .foregroundColor(.white)
                                .cornerRadius(12)
                        }
                    } else {
                        Button(action: { completeOnboarding() }) {
                            Text("始める")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(Color.accentColor)
                                .foregroundColor(.white)
                                .cornerRadius(12)
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
            }
        }
    }

    private var welcomePage: some View {
        VStack(spacing: 24) {
            Spacer()

            // Gradient brain icon
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.purple.opacity(0.3), .blue.opacity(0.2)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 120, height: 120)

                Image(systemName: "brain.head.profile")
                    .font(.system(size: 60))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.purple, .blue],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }

            Text(String(localized: "onboarding.welcome.title"))
                .font(.system(size: 32, weight: .bold))
                .multilineTextAlignment(.center)

            Text(String(localized: "onboarding.welcome.subtitle"))
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            // Airplane mode badge
            HStack(spacing: 8) {
                Image(systemName: "airplane")
                    .foregroundStyle(.green)
                Text("機内モードでも動作")
                    .font(.subheadline.weight(.medium))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color.green.opacity(0.15))
            .cornerRadius(20)

            Spacer()
            Spacer()
        }
        .padding(.horizontal, 32)
    }

    private var featuresPage: some View {
        VStack(spacing: 32) {
            Spacer()

            Text(String(localized: "onboarding.features.title"))
                .font(.system(size: 24, weight: .bold))

            VStack(alignment: .leading, spacing: 20) {
                FeatureRow(
                    icon: "airplane",
                    iconColor: .green,
                    title: String(localized: "onboarding.feature.offline"),
                    description: String(localized: "onboarding.feature.offline.desc")
                )
                FeatureRow(
                    icon: "lock.shield.fill",
                    iconColor: .blue,
                    title: String(localized: "onboarding.feature.privacy"),
                    description: String(localized: "onboarding.feature.privacy.desc")
                )
                FeatureRow(
                    icon: "calendar.badge.clock",
                    iconColor: .orange,
                    title: String(localized: "onboarding.feature.vault"),
                    description: String(localized: "onboarding.feature.vault.desc")
                )
                FeatureRow(
                    icon: "briefcase.fill",
                    iconColor: .purple,
                    title: String(localized: "onboarding.feature.secure"),
                    description: String(localized: "onboarding.feature.secure.desc")
                )
            }

            Spacer()
            Spacer()
        }
        .padding(.horizontal, 32)
    }

    private var privacyPage: some View {
        VStack(spacing: 24) {
            Spacer()

            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.15))
                    .frame(width: 100, height: 100)

                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 50))
                    .foregroundStyle(.green)
            }

            Text(String(localized: "onboarding.privacy.title"))
                .font(.system(size: 24, weight: .bold))
                .multilineTextAlignment(.center)

            VStack(alignment: .leading, spacing: 16) {
                PrivacyItem(icon: "iphone", text: String(localized: "onboarding.privacy.item1"))
                PrivacyItem(icon: "xmark.icloud.fill", text: String(localized: "onboarding.privacy.item2"))
                PrivacyItem(icon: "brain.head.profile", text: String(localized: "onboarding.privacy.item3"))
            }
            .padding(.horizontal, 16)

            Spacer()
            Spacer()
        }
        .padding(.horizontal, 32)
    }

    private var getStartedPage: some View {
        VStack(spacing: 24) {
            Spacer()

            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.15))
                    .frame(width: 100, height: 100)

                Image(systemName: "hand.tap.fill")
                    .font(.system(size: 50))
                    .foregroundStyle(.blue)
            }

            Text(String(localized: "onboarding.getstarted.title"))
                .font(.system(size: 24, weight: .bold))

            Text(String(localized: "onboarding.getstarted.subtitle"))
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            VStack(spacing: 16) {
                SetupStepRow(number: 1, text: String(localized: "onboarding.step1"), isActive: true)
                SetupStepRow(number: 2, text: String(localized: "onboarding.step2"), isActive: false)
                SetupStepRow(number: 3, text: String(localized: "onboarding.step3"), isActive: false)
            }
            .padding(.horizontal, 16)

            Spacer()
            Spacer()
        }
        .padding(.horizontal, 32)
    }

    private func completeOnboarding() {
        hasCompletedOnboarding = true
        dismiss()
    }
}

struct FeatureRow: View {
    let icon: String
    var iconColor: Color = .purple
    let title: String
    let description: String

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(iconColor.opacity(0.15))
                    .frame(width: 44, height: 44)

                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundStyle(iconColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct PrivacyItem: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(.green)
                .frame(width: 24)
            Text(text)
                .font(.subheadline)
        }
    }
}

struct SetupStepRow: View {
    let number: Int
    let text: String
    let isActive: Bool

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(isActive ? Color.blue : Color.gray.opacity(0.3))
                    .frame(width: 32, height: 32)

                Text("\(number)")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(isActive ? .white : .secondary)
            }

            Text(text)
                .font(.subheadline)
                .foregroundStyle(isActive ? .primary : .secondary)

            Spacer()

            if number == 3 {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
        }
    }
}

#Preview {
    OnboardingView(hasCompletedOnboarding: .constant(false))
        .environmentObject(AppState())
}
