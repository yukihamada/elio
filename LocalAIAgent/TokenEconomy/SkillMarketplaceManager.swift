import Foundation
import SwiftUI

// MARK: - Skill Marketplace Manager

@MainActor
class SkillMarketplaceManager: ObservableObject {
    static let shared = SkillMarketplaceManager()

    @Published var skills: [Skill] = []
    @Published var installedSkills: [InstalledSkill] = []
    @Published var isLoading = false
    @Published var isInstalling = false
    @Published var isPublishing = false
    @Published var error: String?

    // MARK: - Sort / Filter

    enum SortOption: String, CaseIterable {
        case popular = "popular"
        case newest = "newest"
        case highestRated = "highest_rated"

        var label: String {
            switch self {
            case .popular: return "人気順"
            case .newest: return "新着順"
            case .highestRated: return "高評価順"
            }
        }
    }

    // MARK: - Persistence Keys

    private let installedSkillsKey = "skill_marketplace_installed"

    // MARK: - Init

    private init() {
        loadInstalledSkills()
        registerEnabledSkillServers()
    }

    // MARK: - API: Fetch Skills

    func fetchSkills(sort: SortOption = .popular, category: SkillCategory? = nil, search: String? = nil) async {
        let baseURL = SyncManager.shared.baseURL
        var urlString = "\(baseURL)/api/v1/skills?sort=\(sort.rawValue)&limit=50"
        if let category = category {
            urlString += "&category=\(category.rawValue)"
        }
        if let search = search, !search.isEmpty {
            urlString += "&q=\(search.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? search)"
        }

        guard let url = URL(string: urlString) else { return }

        isLoading = true
        error = nil
        defer { isLoading = false }

        var request = URLRequest(url: url)
        if let token = SyncManager.shared.authToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.setValue("Elio Chat iOS", forHTTPHeaderField: "User-Agent")

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let response = try decoder.decode(SkillListResponse.self, from: data)
            skills = response.skills
        } catch {
            self.error = "スキルの取得に失敗しました"
            print("[SkillMarketplace] Fetch error: \(error)")
        }
    }

    // MARK: - API: Fetch Skill Detail

    func fetchSkillDetail(id: String) async -> SkillDetailResponse? {
        let baseURL = SyncManager.shared.baseURL
        guard let url = URL(string: "\(baseURL)/api/v1/skills/\(id)") else { return nil }

        var request = URLRequest(url: url)
        if let token = SyncManager.shared.authToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.setValue("Elio Chat iOS", forHTTPHeaderField: "User-Agent")

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(SkillDetailResponse.self, from: data)
        } catch {
            print("[SkillMarketplace] Detail fetch error: \(error)")
            return nil
        }
    }

    // MARK: - API: Install Skill

    func installSkill(_ skill: Skill) async -> Bool {
        guard let token = SyncManager.shared.authToken else {
            error = "ログインが必要です"
            return false
        }

        // Check token balance for paid skills
        if skill.priceTokens > 0 {
            guard TokenManager.shared.canAfford(skill.priceTokens) else {
                error = "トークンが不足しています（必要: \(skill.priceTokens)）"
                return false
            }
        }

        isInstalling = true
        error = nil
        defer { isInstalling = false }

        let baseURL = SyncManager.shared.baseURL
        guard let url = URL(string: "\(baseURL)/api/v1/skills/\(skill.id)/install") else {
            error = "URL error"
            return false
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("Elio Chat iOS", forHTTPHeaderField: "User-Agent")

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let response = try JSONDecoder().decode(SkillInstallResponse.self, from: data)

            if response.ok {
                // Spend tokens if paid
                if skill.priceTokens > 0 {
                    try? TokenManager.shared.spend(skill.priceTokens, reason: .skillPurchase)
                }

                // Save locally
                let installed = InstalledSkill(
                    id: UUID().uuidString,
                    skillId: skill.id,
                    name: skill.name,
                    description: skill.description,
                    authorName: skill.authorName,
                    category: skill.category,
                    version: skill.version,
                    mcpConfig: skill.mcpConfig,
                    iconUrl: skill.iconUrl,
                    installedAt: Date(),
                    isEnabled: true
                )
                installedSkills.append(installed)
                saveInstalledSkills()

                // Register with MCPServerRegistry
                registerSkillServer(installed)

                return true
            } else {
                error = response.error ?? "インストールに失敗しました"
            }
        } catch {
            self.error = "エラー: \(error.localizedDescription)"
            print("[SkillMarketplace] Install error: \(error)")
        }

        return false
    }

    // MARK: - Uninstall Skill

    func uninstallSkill(_ installed: InstalledSkill) {
        // Unregister from MCPServerRegistry
        MCPServerRegistry.shared.unregisterCustomServer(id: installed.mcpConfig.serverId)

        // Remove from local storage
        installedSkills.removeAll { $0.id == installed.id }
        saveInstalledSkills()
    }

    // MARK: - Toggle Skill

    func toggleSkill(_ installed: InstalledSkill) {
        guard let index = installedSkills.firstIndex(where: { $0.id == installed.id }) else { return }

        installedSkills[index].isEnabled.toggle()
        saveInstalledSkills()

        if installedSkills[index].isEnabled {
            registerSkillServer(installedSkills[index])
        } else {
            MCPServerRegistry.shared.unregisterCustomServer(id: installed.mcpConfig.serverId)
        }
    }

    // MARK: - API: Publish Skill

    func publishSkill(
        name: String,
        description: String,
        category: SkillCategory,
        mcpConfigJSON: String,
        tags: [String],
        priceTokens: Int
    ) async -> Bool {
        guard let token = SyncManager.shared.authToken else {
            error = "ログインが必要です"
            return false
        }

        isPublishing = true
        error = nil
        defer { isPublishing = false }

        let baseURL = SyncManager.shared.baseURL
        guard let url = URL(string: "\(baseURL)/api/v1/skills") else {
            error = "URL error"
            return false
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("Elio Chat iOS", forHTTPHeaderField: "User-Agent")

        let body: [String: Any] = [
            "name": name,
            "description": description,
            "category": category.rawValue,
            "mcp_config_json": mcpConfigJSON,
            "tags": tags,
            "price_tokens": priceTokens,
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let response = try JSONDecoder().decode(SkillPublishResponse.self, from: data)

            if response.ok {
                return true
            } else {
                error = response.error ?? "公開に失敗しました"
            }
        } catch {
            self.error = "エラー: \(error.localizedDescription)"
            print("[SkillMarketplace] Publish error: \(error)")
        }

        return false
    }

    // MARK: - API: Review Skill

    func reviewSkill(skillId: String, rating: Int, comment: String) async -> Bool {
        guard let token = SyncManager.shared.authToken else {
            error = "ログインが必要です"
            return false
        }

        let baseURL = SyncManager.shared.baseURL
        guard let url = URL(string: "\(baseURL)/api/v1/skills/\(skillId)/review") else {
            return false
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("Elio Chat iOS", forHTTPHeaderField: "User-Agent")
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "rating": rating,
            "comment": comment,
        ])

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let response = try JSONDecoder().decode(SkillReviewResponse.self, from: data)
            return response.ok
        } catch {
            print("[SkillMarketplace] Review error: \(error)")
            return false
        }
    }

    // MARK: - Local Persistence

    private func loadInstalledSkills() {
        guard let data = UserDefaults.standard.data(forKey: installedSkillsKey) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let decoded = try? decoder.decode([InstalledSkill].self, from: data) {
            installedSkills = decoded
        }
    }

    private func saveInstalledSkills() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(installedSkills) {
            UserDefaults.standard.set(data, forKey: installedSkillsKey)
        }
    }

    // MARK: - MCP Registration

    private func registerSkillServer(_ installed: InstalledSkill) {
        let config = installed.mcpConfig.toCustomServerConfig()
        let server = CustomMCPServer(config: config)
        MCPServerRegistry.shared.registerCustomServer(server)
    }

    /// Register all enabled installed skill servers on app launch
    private func registerEnabledSkillServers() {
        for skill in installedSkills where skill.isEnabled {
            registerSkillServer(skill)
        }
    }

    // MARK: - Helpers

    func isInstalled(_ skillId: String) -> Bool {
        installedSkills.contains { $0.skillId == skillId }
    }

    func installedSkill(for skillId: String) -> InstalledSkill? {
        installedSkills.first { $0.skillId == skillId }
    }
}

