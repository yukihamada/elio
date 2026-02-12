#if targetEnvironment(macCatalyst)
import SwiftUI

struct ServerDashboardView: View {
    @ObservedObject private var serverManager = PrivateServerManager.shared
    @ObservedObject private var tokenManager = TokenManager.shared
    @State private var animateGradient = false

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // MARK: - Hero Status Card
                heroCard

                // MARK: - Stats Grid
                statsGrid

                // MARK: - Connection Info
                connectionCard

                // MARK: - Token Economy
                tokenCard
            }
            .padding(24)
        }
        .background(Color.chatBackgroundDynamic)
        .navigationTitle(String(localized: "mac.server.dashboard.title", defaultValue: "Server Dashboard"))
        .onAppear {
            withAnimation(.easeInOut(duration: 3).repeatForever(autoreverses: true)) {
                animateGradient = true
            }
        }
    }

    // MARK: - Hero Card

    private var heroCard: some View {
        VStack(spacing: 20) {
            // Animated status icon
            ZStack {
                Circle()
                    .fill(
                        .linearGradient(
                            colors: serverManager.isRunning
                                ? [.green, .mint]
                                : [.gray.opacity(0.5), .gray.opacity(0.3)],
                            startPoint: animateGradient ? .topLeading : .bottomTrailing,
                            endPoint: animateGradient ? .bottomTrailing : .topLeading
                        )
                    )
                    .frame(width: 80, height: 80)
                    .shadow(color: serverManager.isRunning ? .green.opacity(0.4) : .clear, radius: 20)

                Image(systemName: serverManager.isRunning ? "server.rack" : "server.rack")
                    .font(.system(size: 32, weight: .medium))
                    .foregroundStyle(.white)
                    .symbolEffect(.pulse, isActive: serverManager.isRunning)
            }

            VStack(spacing: 6) {
                Text(serverManager.isRunning
                     ? String(localized: "mac.server.status.running", defaultValue: "Server Running")
                     : String(localized: "mac.server.status.stopped", defaultValue: "Server Stopped"))
                    .font(.system(size: 22, weight: .bold, design: .rounded))

                Text(serverManager.isRunning
                     ? String(localized: "mac.server.status.subtitle.running", defaultValue: "Providing inference to nearby devices")
                     : String(localized: "mac.server.status.subtitle.stopped", defaultValue: "Start to share your Mac's power"))
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }

            Button {
                Task {
                    if serverManager.isRunning {
                        serverManager.stop()
                    } else {
                        try? await serverManager.start()
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: serverManager.isRunning ? "stop.fill" : "play.fill")
                        .font(.system(size: 14, weight: .bold))
                    Text(serverManager.isRunning
                         ? String(localized: "mac.server.stop", defaultValue: "Stop Server")
                         : String(localized: "mac.server.start", defaultValue: "Start Server"))
                        .font(.system(size: 15, weight: .semibold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(
                            .linearGradient(
                                colors: serverManager.isRunning ? [.red, .orange] : [.blue, .purple],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                )
                .shadow(color: (serverManager.isRunning ? Color.red : Color.blue).opacity(0.3), radius: 8, y: 4)
            }
            .buttonStyle(.plain)
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .stroke(Color.glassBorder, lineWidth: 0.5)
        )
    }

    // MARK: - Stats Grid

    private var statsGrid: some View {
        HStack(spacing: 16) {
            statCard(
                icon: "person.2.fill",
                value: "\(serverManager.connectedClients)",
                label: String(localized: "mac.server.clients", defaultValue: "Clients"),
                gradient: [.blue, .cyan]
            )

            statCard(
                icon: "arrow.triangle.2.circlepath",
                value: "\(serverManager.todayRequestsServed)",
                label: String(localized: "mac.server.requests.short", defaultValue: "Requests"),
                gradient: [.purple, .pink]
            )

            statCard(
                icon: "bitcoinsign.circle.fill",
                value: "\(serverManager.todayTokensEarned)",
                label: String(localized: "mac.server.earned.short", defaultValue: "Earned"),
                gradient: [.green, .mint]
            )
        }
    }

    private func statCard(icon: String, value: String, label: String, gradient: [Color]) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(
                    .linearGradient(colors: gradient, startPoint: .topLeading, endPoint: .bottomTrailing)
                )

            Text(value)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .monospacedDigit()

            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.5)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.cardBackground)
                .shadow(color: .black.opacity(0.06), radius: 12, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.subtleSeparator, lineWidth: 0.5)
        )
    }

    // MARK: - Connection Card

    private var connectionCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            ModernSectionHeader(title: String(localized: "mac.server.section.connection", defaultValue: "Connection"), icon: "link", gradient: [.blue, .cyan])

            VStack(spacing: 0) {
                if let address = serverManager.serverAddress {
                    connectionRow(
                        icon: "network",
                        label: String(localized: "mac.server.address", defaultValue: "Address"),
                        value: address,
                        isMonospaced: true,
                        showDivider: true
                    )
                }

                connectionRow(
                    icon: "number",
                    label: String(localized: "mac.server.pairing.code", defaultValue: "Pairing Code"),
                    value: serverManager.pairingCode,
                    isMonospaced: true,
                    isLarge: true,
                    showDivider: false
                )
            }
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

    private func connectionRow(icon: String, label: String, value: String, isMonospaced: Bool = false, isLarge: Bool = false, showDivider: Bool) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 20)

                Text(label)
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)

                Spacer()

                Text(value)
                    .font(isLarge
                          ? .system(size: 24, weight: .bold, design: .monospaced)
                          : .system(size: 14, weight: .medium, design: isMonospaced ? .monospaced : .default))
                    .foregroundStyle(.primary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            if showDivider {
                Divider()
                    .padding(.leading, 48)
            }
        }
    }

    // MARK: - Token Card

    private var tokenCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            ModernSectionHeader(title: String(localized: "mac.server.section.tokens", defaultValue: "Token Economy"), icon: "bitcoinsign.circle", gradient: [.yellow, .orange])

            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(localized: "mac.server.balance", defaultValue: "Balance"))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                        .tracking(0.5)

                    Text("\(tokenManager.balance)")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(
                            .linearGradient(
                                colors: [.yellow, .orange],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )

                    Text(String(localized: "mac.server.tokens.unit", defaultValue: "tokens"))
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 8) {
                    Label(String(localized: "mac.server.total.earned", defaultValue: "Total Earned"), systemImage: "arrow.up.circle.fill")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.green)

                    Text("\(tokenManager.totalEarned)")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .monospacedDigit()
                }
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color.cardBackground)
                    .shadow(color: .black.opacity(0.06), radius: 12, y: 4)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(Color.subtleSeparator, lineWidth: 0.5)
            )
        }
    }
}
#endif
