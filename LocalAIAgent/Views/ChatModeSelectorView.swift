import SwiftUI

/// Mode selector dropdown for switching between Local/Fast/Genius/P2P modes
struct ChatModeSelectorView: View {
    @ObservedObject var chatModeManager: ChatModeManager
    @ObservedObject var tokenManager: TokenManager
    var syncManager: SyncManager?
    @State private var isExpanded = false
    @State private var showLoginSheet = false

    var body: some View {
        VStack(spacing: 0) {
            // Collapsed header - shows current mode and token balance
            Button(action: {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    isExpanded.toggle()
                }
            }) {
                HStack(spacing: 8) {
                    // Mode icon and name
                    Image(systemName: chatModeManager.currentMode.icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(chatModeManager.currentMode.color)

                    Text(chatModeManager.currentMode.displayName)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.primary)

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)

                    Spacer()

                    // chatweb.ai credits when in Cloud mode and logged in
                    if chatModeManager.currentMode == .chatweb,
                       let sm = syncManager, sm.isLoggedIn {
                        HStack(spacing: 4) {
                            Image(systemName: "bolt.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(.indigo)
                            Text("\(sm.creditsRemaining)")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.primary)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(.tertiarySystemBackground))
                        .clipShape(Capsule())
                    }

                    // Token balance
                    HStack(spacing: 4) {
                        Image(systemName: "diamond.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.yellow)
                        Text("\(tokenManager.balance)")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.primary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(.tertiarySystemBackground))
                    .clipShape(Capsule())
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.chatInputBackgroundDynamic)
                        .shadow(color: .black.opacity(0.05), radius: 2, y: 1)
                )
            }
            .buttonStyle(.plain)

            // Expanded mode list
            if isExpanded {
                VStack(spacing: 4) {
                    ForEach(ChatMode.allCases) { mode in
                        ChatModeOptionRow(
                            mode: mode,
                            isSelected: mode == chatModeManager.currentMode,
                            isAvailable: chatModeManager.isModeAvailable(mode),
                            onSelect: {
                                chatModeManager.setMode(mode)
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    isExpanded = false
                                }
                            }
                        )
                    }
                }
                .padding(.top, 8)
                .transition(.opacity.combined(with: .move(edge: .top)))

                // Login prompt for Cloud mode when not logged in
                if chatModeManager.currentMode == .chatweb,
                   let sm = syncManager, !sm.isLoggedIn {
                    Button(action: { showLoginSheet = true }) {
                        HStack(spacing: 8) {
                            Image(systemName: "person.crop.circle.badge.plus")
                                .font(.system(size: 14))
                                .foregroundStyle(.indigo)
                            Text(String(localized: "chatmode.login_to_sync", defaultValue: "Sign in to sync conversations"))
                                .font(.system(size: 13))
                                .foregroundStyle(.indigo)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color.indigo.opacity(0.1))
                        )
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 4)
                }
            }
        }
        .padding(.horizontal, 16)
        .sheet(isPresented: $showLoginSheet) {
            if let sm = syncManager {
                ChatWebLoginView()
                    .environmentObject(sm)
            }
        }
    }
}

/// Individual mode option row
struct ChatModeOptionRow: View {
    let mode: ChatMode
    let isSelected: Bool
    let isAvailable: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                // Mode icon
                ZStack {
                    Circle()
                        .fill(mode.color.opacity(0.15))
                        .frame(width: 32, height: 32)

                    Image(systemName: mode.icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(mode.color)
                }

                // Mode info
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(mode.displayName)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(isAvailable ? .primary : .secondary)

                        if mode.tokenCost > 0 {
                            Text("\(mode.tokenCost)")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(mode.color)
                                .clipShape(Capsule())
                        } else {
                            Text(String(localized: "chatmode.free", defaultValue: "FREE"))
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.green)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Color.green.opacity(0.15))
                                .clipShape(Capsule())
                        }
                    }

                    Text(mode.description)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Selection indicator or unavailable badge
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(mode.color)
                } else if !isAvailable {
                    if mode.requiresAPIKey {
                        Text(String(localized: "chatmode.needs.key", defaultValue: "Needs Key"))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color(.tertiarySystemBackground))
                            .clipShape(Capsule())
                    } else if mode.isP2P {
                        Text(String(localized: "chatmode.no.servers", defaultValue: "No Servers"))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color(.tertiarySystemBackground))
                            .clipShape(Capsule())
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? mode.color.opacity(0.1) : Color.chatInputBackgroundDynamic)
            )
        }
        .buttonStyle(.plain)
        .disabled(!isAvailable)
        .opacity(isAvailable ? 1 : 0.6)
    }
}

/// Token balance badge for header
struct TokenBalanceBadge: View {
    @ObservedObject var tokenManager: TokenManager

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "diamond.fill")
                .font(.system(size: 10))
                .foregroundStyle(.yellow)
            Text("\(tokenManager.balance)")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(Color(.tertiarySystemBackground))
        )
    }
}

#Preview {
    VStack {
        ChatModeSelectorView(
            chatModeManager: ChatModeManager.shared,
            tokenManager: TokenManager.shared,
            syncManager: nil
        )
        Spacer()
    }
    .background(Color.chatBackgroundDynamic)
}
