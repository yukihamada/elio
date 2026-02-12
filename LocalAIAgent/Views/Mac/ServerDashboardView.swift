#if targetEnvironment(macCatalyst)
import SwiftUI

struct ServerDashboardView: View {
    @ObservedObject private var serverManager = PrivateServerManager.shared
    @ObservedObject private var tokenManager = TokenManager.shared

    var body: some View {
        List {
            // MARK: - Server Status
            Section {
                HStack {
                    Circle()
                        .fill(serverManager.isRunning ? Color.green : Color.red)
                        .frame(width: 10, height: 10)
                    Text(serverManager.isRunning
                         ? String(localized: "mac.server.status.running", defaultValue: "Running")
                         : String(localized: "mac.server.status.stopped", defaultValue: "Stopped"))
                        .font(.headline)
                    Spacer()
                    Button(serverManager.isRunning
                           ? String(localized: "mac.server.stop", defaultValue: "Stop")
                           : String(localized: "mac.server.start", defaultValue: "Start")) {
                        Task {
                            if serverManager.isRunning {
                                serverManager.stop()
                            } else {
                                try? await serverManager.start()
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
            } header: {
                Text(String(localized: "mac.server.section.status", defaultValue: "Server Status"))
            }

            // MARK: - Stats
            Section {
                LabeledContent(String(localized: "mac.server.clients", defaultValue: "Connected Clients")) {
                    Text("\(serverManager.connectedClients)")
                        .font(.title3.monospacedDigit())
                }
                LabeledContent(String(localized: "mac.server.requests", defaultValue: "Requests Served Today")) {
                    Text("\(serverManager.todayRequestsServed)")
                        .font(.title3.monospacedDigit())
                }
                LabeledContent(String(localized: "mac.server.tokens.earned", defaultValue: "Tokens Earned Today")) {
                    Text("\(serverManager.todayTokensEarned)")
                        .font(.title3.monospacedDigit())
                        .foregroundStyle(.green)
                }
            } header: {
                Text(String(localized: "mac.server.section.stats", defaultValue: "Statistics"))
            }

            // MARK: - Connection Info
            Section {
                if let address = serverManager.serverAddress {
                    LabeledContent(String(localized: "mac.server.address", defaultValue: "Address")) {
                        Text(address)
                            .font(.system(.body, design: .monospaced))
                    }
                }
                LabeledContent(String(localized: "mac.server.pairing.code", defaultValue: "Pairing Code")) {
                    Text(serverManager.pairingCode)
                        .font(.system(.title2, design: .monospaced))
                        .fontWeight(.bold)
                }
            } header: {
                Text(String(localized: "mac.server.section.connection", defaultValue: "Connection"))
            }

            // MARK: - Token Balance
            Section {
                LabeledContent(String(localized: "mac.server.balance", defaultValue: "Token Balance")) {
                    Text("\(tokenManager.balance)")
                        .font(.title3.monospacedDigit())
                }
            } header: {
                Text(String(localized: "mac.server.section.tokens", defaultValue: "Token Economy"))
            }
        }
        .navigationTitle(String(localized: "mac.server.dashboard.title", defaultValue: "Server Dashboard"))
    }
}
#endif
