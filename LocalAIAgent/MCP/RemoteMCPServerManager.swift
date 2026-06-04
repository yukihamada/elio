import Foundation

// MARK: - Remote MCP Server Manager

/// Owns the persisted list of remote MCP server configs (UserDefaults) and their
/// bearer tokens (Keychain). Builds `RemoteMCPServer` instances and registers the
/// enabled ones with an `MCPClient`.
@MainActor
final class RemoteMCPServerManager: ObservableObject {
    static let shared = RemoteMCPServerManager()

    @Published private(set) var configs: [RemoteMCPServerConfig] = []

    private let defaultsKey = "remote_mcp_servers"

    private init() {
        load()
    }

    // MARK: - Persistence

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode([RemoteMCPServerConfig].self, from: data) else {
            configs = []
            return
        }
        configs = decoded
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(configs) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }

    // MARK: - Token storage (Keychain)

    func token(for config: RemoteMCPServerConfig) -> String? {
        KeychainManager.shared.getSecret(account: config.keychainAccount)
    }

    private func setToken(_ token: String?, for config: RemoteMCPServerConfig) {
        if let token = token, !token.isEmpty {
            try? KeychainManager.shared.setSecret(token, account: config.keychainAccount)
        } else {
            try? KeychainManager.shared.deleteSecret(account: config.keychainAccount)
        }
    }

    // MARK: - CRUD

    func addOrUpdate(_ config: RemoteMCPServerConfig, token: String?) {
        if let idx = configs.firstIndex(where: { $0.id == config.id }) {
            configs[idx] = config
        } else {
            configs.append(config)
        }
        // Only overwrite the stored token when a non-nil value is supplied so that
        // editing the name/URL doesn't wipe an existing token (pass nil to keep).
        if let token = token {
            setToken(token, for: config)
        }
        persist()
    }

    func remove(id: String) {
        if let config = configs.first(where: { $0.id == id }) {
            setToken(nil, for: config)
        }
        configs.removeAll { $0.id == id }
        persist()
    }

    func setEnabled(_ enabled: Bool, id: String) {
        guard let idx = configs.firstIndex(where: { $0.id == id }) else { return }
        configs[idx].isEnabled = enabled
        persist()
    }

    func config(id: String) -> RemoteMCPServerConfig? {
        configs.first { $0.id == id }
    }

    // MARK: - Building servers

    /// Build a `RemoteMCPServer` for a config (token pulled from Keychain).
    func makeServer(for config: RemoteMCPServerConfig) throws -> RemoteMCPServer {
        try RemoteMCPServer(config: config, token: token(for: config))
    }

    /// Register every saved remote server with the client and kick off async tool
    /// discovery for the enabled ones. Disabled servers are still registered (so they
    /// can be toggled on later) but only enabled servers refresh their tool list.
    func registerAll(with client: MCPClient) {
        for config in configs {
            guard let server = try? makeServer(for: config) else { continue }
            client.registerServer(server)
            if config.isEnabled {
                Task {
                    _ = try? await server.refreshTools()
                    // Force MCPClient to recompute serverInfos with the discovered tools.
                    await MainActor.run { client.refreshServerInfos() }
                }
            }
        }
    }

    // MARK: - Presets

    /// Verified live endpoints (probed via curl). `wearmu.com/mcp` is the HTML shop
    /// page, so the real MU endpoint `mcp.wearmu.com/mcp` is used instead.
    static let presets: [RemoteMCPServerConfig] = [
        RemoteMCPServerConfig(id: "preset_atsm", name: "ATSM 焚き火",
                              urlString: "https://atsm.wtf/mcp",
                              icon: "flame.fill", isEnabled: false, requiresToken: true),
        RemoteMCPServerConfig(id: "preset_koe", name: "Koe 声",
                              urlString: "https://mcp.koe.live/mcp",
                              icon: "waveform", isEnabled: false, requiresToken: false),
        RemoteMCPServerConfig(id: "preset_mu", name: "MU 服",
                              urlString: "https://mcp.wearmu.com/mcp",
                              icon: "tshirt.fill", isEnabled: false, requiresToken: true),
        RemoteMCPServerConfig(id: "preset_jiuflow", name: "JiuFlow",
                              urlString: "https://jiuflow.com/mcp",
                              icon: "figure.martial.arts", isEnabled: false, requiresToken: false),
        RemoteMCPServerConfig(id: "preset_bimhouse", name: "bim.house",
                              urlString: "https://bim.house/mcp",
                              icon: "house.fill", isEnabled: false, requiresToken: false),
        RemoteMCPServerConfig(id: "preset_news", name: "news.xyz",
                              urlString: "https://news.xyz/mcp",
                              icon: "newspaper.fill", isEnabled: false, requiresToken: false)
    ]

    /// Presets not yet added to the saved list.
    var availablePresets: [RemoteMCPServerConfig] {
        let existing = Set(configs.map { $0.urlString })
        return Self.presets.filter { !existing.contains($0.urlString) }
    }
}
