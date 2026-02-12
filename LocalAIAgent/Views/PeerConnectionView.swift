import SwiftUI
import Network

/// View for connecting to nearby devices via 4-digit pairing code
struct PeerConnectionView: View {
    @ObservedObject var chatModeManager: ChatModeManager
    @State private var pairingCode = ""
    @State private var myCode: String = ""
    @State private var isHosting = false
    @State private var isConnecting = false
    @State private var connectionStatus: ConnectionStatus = .disconnected
    @State private var connectedDeviceName: String?
    @Environment(\.dismiss) private var dismiss

    enum ConnectionStatus {
        case disconnected
        case searching
        case connected
        case error(String)
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Header illustration
                    VStack(spacing: 12) {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .font(.system(size: 48))
                            .foregroundStyle(.indigo)

                        Text(String(localized: "peer.title"))
                            .font(.title2.bold())

                        Text(String(localized: "peer.desc"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 16)

                    // Your code section
                    VStack(spacing: 12) {
                        Text(String(localized: "peer.code.your"))
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.secondary)

                        Text(myCode)
                            .font(.system(size: 48, weight: .bold, design: .monospaced))
                            .foregroundStyle(.primary)
                            .tracking(12)

                        Text(String(localized: "peer.share.code.hint", defaultValue: "Share this code with a nearby device"))
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

                    // Divider
                    HStack {
                        Rectangle()
                            .fill(Color(.separator))
                            .frame(height: 1)
                        Text(String(localized: "peer.or", defaultValue: "or"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Rectangle()
                            .fill(Color(.separator))
                            .frame(height: 1)
                    }
                    .padding(.horizontal, 32)

                    // Enter code section
                    VStack(spacing: 16) {
                        Text(String(localized: "peer.code.enter"))
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.secondary)

                        HStack(spacing: 12) {
                            ForEach(0..<4, id: \.self) { index in
                                let digit = index < pairingCode.count
                                    ? String(pairingCode[pairingCode.index(pairingCode.startIndex, offsetBy: index)])
                                    : ""
                                Text(digit)
                                    .font(.system(size: 32, weight: .bold, design: .monospaced))
                                    .frame(width: 56, height: 64)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(Color(.tertiarySystemBackground))
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(
                                                index < pairingCode.count ? Color.indigo : Color(.separator),
                                                lineWidth: index < pairingCode.count ? 2 : 1
                                            )
                                    )
                            }
                        }

                        // Hidden text field for keyboard input
                        TextField("", text: $pairingCode)
                            .keyboardType(.numberPad)
                            .frame(width: 1, height: 1)
                            .opacity(0.01)
                            .onChange(of: pairingCode) { _, newValue in
                                // Limit to 4 digits
                                if newValue.count > 4 {
                                    pairingCode = String(newValue.prefix(4))
                                }
                                // Auto-connect when 4 digits entered
                                if pairingCode.count == 4 {
                                    connectWithCode()
                                }
                            }

                        Button(action: connectWithCode) {
                            HStack(spacing: 8) {
                                if isConnecting {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle())
                                        .tint(.white)
                                } else {
                                    Image(systemName: "link")
                                }
                                Text(String(localized: "peer.connect"))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(pairingCode.count == 4 ? Color.indigo : Color.gray.opacity(0.3))
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .font(.system(size: 16, weight: .semibold))
                        }
                        .disabled(pairingCode.count != 4 || isConnecting)
                    }
                    .padding(.horizontal, 16)

                    // Connection status
                    if case .connected = connectionStatus {
                        HStack(spacing: 12) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .font(.system(size: 24))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(String(localized: "peer.connected"))
                                    .font(.system(size: 15, weight: .semibold))
                                if let name = connectedDeviceName {
                                    Text(name)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Text(String(localized: "peer.inference.offload"))
                                .font(.caption)
                                .foregroundStyle(.indigo)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.indigo.opacity(0.1))
                                .clipShape(Capsule())
                        }
                        .padding(16)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color.green.opacity(0.1))
                        )
                        .padding(.horizontal, 16)
                    }

                    if case .error(let msg) = connectionStatus {
                        Text(msg)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .padding(.horizontal, 16)
                    }

                    // Info
                    VStack(alignment: .leading, spacing: 8) {
                        Label(
                            String(localized: "peer.info.local", defaultValue: "Connection stays within your local network"),
                            systemImage: "lock.shield"
                        )
                        Label(
                            String(localized: "peer.info.inference", defaultValue: "Share AI inference power between devices"),
                            systemImage: "cpu"
                        )
                        Label(
                            String(localized: "peer.info.no_internet", defaultValue: "Works without internet connection"),
                            systemImage: "wifi.slash"
                        )
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(16)
                }
            }
            .navigationTitle(String(localized: "peer.title"))
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
            .onAppear {
                generateMyCode()
                chatModeManager.p2p?.startBrowsing()
                // Start advertising our own pairing code via Bonjour
                if !PrivateServerManager.shared.isRunning {
                    Task { try? await PrivateServerManager.shared.start() }
                }
            }
            .onDisappear {
                if case .disconnected = connectionStatus {
                    chatModeManager.p2p?.stopBrowsing()
                }
            }
        }
    }

    private func generateMyCode() {
        // Use the same pairing code as PrivateServerManager (shared via UserDefaults)
        myCode = PrivateServerManager.shared.pairingCode
    }

    private func connectWithCode() {
        guard pairingCode.count == 4 else { return }
        isConnecting = true
        connectionStatus = .searching

        Task {
            if let p2p = chatModeManager.p2p {
                // Match server by pairing code from Bonjour TXT record
                if let server = p2p.findServer(byPairingCode: pairingCode) {
                    do {
                        try await p2p.connect(to: server)
                        p2p.trustDevice(server)
                        connectionStatus = .connected
                        connectedDeviceName = server.name
                        chatModeManager.setMode(.privateP2P)
                    } catch {
                        connectionStatus = .error(error.localizedDescription)
                    }
                } else {
                    // Retry after a short delay — the server may not have been discovered yet
                    try? await Task.sleep(nanoseconds: 2_000_000_000)

                    if let server = p2p.findServer(byPairingCode: pairingCode) {
                        do {
                            try await p2p.connect(to: server)
                            p2p.trustDevice(server)
                            connectionStatus = .connected
                            connectedDeviceName = server.name
                            chatModeManager.setMode(.privateP2P)
                        } catch {
                            connectionStatus = .error(error.localizedDescription)
                        }
                    } else {
                        connectionStatus = .error(
                            String(localized: "peer.error.not_found", defaultValue: "No device found with this code. Make sure both devices are on the same network.")
                        )
                    }
                }
            }
            isConnecting = false
        }
    }
}
