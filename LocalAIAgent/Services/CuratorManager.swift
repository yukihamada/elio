import Foundation
import SwiftUI

// MARK: - Curator Models

/// HamaDAO OG verification status
enum OGVerificationStatus: String, Codable {
    case unverified
    case verified
    case failed
}

/// Curator rank based on review count
enum CuratorRank: String, Codable, CaseIterable {
    case bronze = "bronze"
    case silver = "silver"
    case gold = "gold"
    case diamond = "diamond"

    var displayName: String {
        switch self {
        case .bronze: return "Bronze"
        case .silver: return "Silver"
        case .gold: return "Gold"
        case .diamond: return "Diamond"
        }
    }

    var localizedName: String {
        switch self {
        case .bronze: return String(localized: "curator.rank.bronze", defaultValue: "Bronze")
        case .silver: return String(localized: "curator.rank.silver", defaultValue: "Silver")
        case .gold: return String(localized: "curator.rank.gold", defaultValue: "Gold")
        case .diamond: return String(localized: "curator.rank.diamond", defaultValue: "Diamond")
        }
    }

    var color: Color {
        switch self {
        case .bronze: return Color(red: 0.80, green: 0.50, blue: 0.20)
        case .silver: return Color(red: 0.75, green: 0.75, blue: 0.80)
        case .gold: return Color(red: 1.0, green: 0.84, blue: 0.0)
        case .diamond: return Color(red: 0.73, green: 0.87, blue: 1.0)
        }
    }

    var icon: String {
        switch self {
        case .bronze: return "shield.fill"
        case .silver: return "shield.lefthalf.filled"
        case .gold: return "shield.checkered"
        case .diamond: return "diamond.fill"
        }
    }

    var minReviews: Int {
        switch self {
        case .bronze: return 0
        case .silver: return 11
        case .gold: return 51
        case .diamond: return 101
        }
    }

    static func rank(for reviewCount: Int) -> CuratorRank {
        if reviewCount >= 101 { return .diamond }
        if reviewCount >= 51 { return .gold }
        if reviewCount >= 11 { return .silver }
        return .bronze
    }
}

/// Badge type for display
enum BadgeType: String, Codable {
    case ogFounder = "og_founder"
    case curatorBronze = "curator_bronze"
    case curatorSilver = "curator_silver"
    case curatorGold = "curator_gold"
    case curatorDiamond = "curator_diamond"
    case topPublisher = "top_publisher"
}

/// Curator eligibility requirements
struct CuratorEligibility: Codable {
    let publishedSkills: Int
    let requiredSkills: Int
    let totalDownloads: Int
    let requiredDownloads: Int
    let endorsements: Int
    let requiredEndorsements: Int
    let isEligible: Bool
    let isOGHolder: Bool

    enum CodingKeys: String, CodingKey {
        case publishedSkills = "published_skills"
        case requiredSkills = "required_skills"
        case totalDownloads = "total_downloads"
        case requiredDownloads = "required_downloads"
        case endorsements
        case requiredEndorsements = "required_endorsements"
        case isEligible = "is_eligible"
        case isOGHolder = "is_og_holder"
    }
}

/// Curator stats from the server
struct CuratorStats: Codable {
    let reviewsCompleted: Int
    let skillsApproved: Int
    let skillsRejected: Int
    let reputationScore: Double
    let rank: String
    let specializations: [String]

    enum CodingKeys: String, CodingKey {
        case reviewsCompleted = "reviews_completed"
        case skillsApproved = "skills_approved"
        case skillsRejected = "skills_rejected"
        case reputationScore = "reputation_score"
        case rank
        case specializations
    }

    var curatorRank: CuratorRank {
        CuratorRank(rawValue: rank) ?? .bronze
    }
}

/// Pending skill for review
struct PendingSkill: Identifiable, Codable {
    let id: String
    let name: String
    let description: String
    let authorName: String
    let authorId: String
    let mcpConfig: String?
    let submittedAt: String
    let category: String?

    enum CodingKeys: String, CodingKey {
        case id, name, description
        case authorName = "author_name"
        case authorId = "author_id"
        case mcpConfig = "mcp_config"
        case submittedAt = "submitted_at"
        case category
    }
}

/// OG verification response
struct OGVerifyResponse: Codable {
    let ok: Bool
    let isHolder: Bool?
    let tokenCount: Int?
    let error: String?

    enum CodingKeys: String, CodingKey {
        case ok
        case isHolder = "is_holder"
        case tokenCount = "token_count"
        case error
    }
}

// MARK: - CuratorManager

/// Manages curator-related API calls, OG verification, and local state
@MainActor
final class CuratorManager: ObservableObject {
    static let shared = CuratorManager()

    // MARK: - Published Properties

    @Published private(set) var isCurator: Bool = false
    @Published private(set) var isOGVerified: Bool = false
    @Published private(set) var ogVerificationStatus: OGVerificationStatus = .unverified
    @Published private(set) var curatorStats: CuratorStats?
    @Published private(set) var eligibility: CuratorEligibility?
    @Published private(set) var pendingSkills: [PendingSkill] = []
    @Published private(set) var badges: [BadgeType] = []

    @Published var isLoading = false
    @Published var isVerifying = false
    @Published var errorMessage: String?

    // MARK: - Persistence Keys

    private let isCuratorKey = "curator_is_curator"
    private let isOGVerifiedKey = "curator_is_og_verified"
    private let walletAddressKey = "curator_wallet_address"
    private let badgesKey = "curator_badges"

    // MARK: - HamaDAO Contract

    static let hamadaoContract = "0x4016eec42a764cb2d5e6bbdeb9ce69a473252e7b"

    private init() {
        loadLocalState()
    }

    // MARK: - OG Verification

    /// Verify that a wallet address holds a HamaDAO NFT
    func verifyOGStatus(walletAddress: String) async -> Bool {
        guard let token = SyncManager.shared.authToken else {
            errorMessage = String(localized: "curator.error.login_required", defaultValue: "chatweb.aiにログインしてください")
            return false
        }

        let trimmedAddress = walletAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedAddress.hasPrefix("0x"), trimmedAddress.count == 42 else {
            errorMessage = String(localized: "curator.error.invalid_address", defaultValue: "有効なEthereumアドレスを入力してください")
            return false
        }

        isVerifying = true
        errorMessage = nil

        let baseURL = SyncManager.shared.baseURL
        guard let url = URL(string: "\(baseURL)/api/v1/og/verify") else {
            errorMessage = "URL error"
            isVerifying = false
            return false
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("Elio Chat iOS", forHTTPHeaderField: "User-Agent")
        // FIXME: elio-api /api/v1/og/verify expects EIP-191 signature verification
        // (walletAddress, signature, message) but this client only sends the address.
        // Either implement wallet signing (WalletConnect / MetaMask deep link) on iOS,
        // or add a simpler balance-check-only endpoint on the API side.
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "walletAddress": trimmedAddress,
            "contract_address": Self.hamadaoContract,
        ])
        request.timeoutInterval = 30

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
                errorMessage = String(localized: "curator.error.server", defaultValue: "サーバーエラー (\(statusCode))")
                isVerifying = false
                return false
            }

            let result = try JSONDecoder().decode(OGVerifyResponse.self, from: data)

            if result.ok, result.isHolder == true {
                isOGVerified = true
                ogVerificationStatus = .verified
                isCurator = true

                // Add OG badge
                if !badges.contains(.ogFounder) {
                    badges.append(.ogFounder)
                }

                saveLocalState()
                UserDefaults.standard.set(trimmedAddress, forKey: walletAddressKey)
                isVerifying = false
                return true
            } else {
                ogVerificationStatus = .failed
                errorMessage = result.error ?? String(localized: "curator.error.not_holder", defaultValue: "このウォレットにはHamaDAO NFTが見つかりませんでした")
                isVerifying = false
                return false
            }
        } catch {
            errorMessage = String(localized: "curator.error.verification_failed", defaultValue: "検証に失敗しました: \(error.localizedDescription)")
            isVerifying = false
            return false
        }
    }

    // MARK: - Curator Eligibility

    /// Check if the user meets curator requirements
    func checkEligibility() async {
        guard let token = SyncManager.shared.authToken else { return }

        isLoading = true
        defer { isLoading = false }

        let baseURL = SyncManager.shared.baseURL
        // API route: GET /api/v1/curators/:userId/status
        // TODO: Persist userId from LoginResponse in SyncManager and use it here.
        // For now, fall back to "me" which the server should resolve from the auth token.
        guard let url = URL(string: "\(baseURL)/api/v1/curators/me/status") else { return }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("Elio Chat iOS", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                print("[Curator] Eligibility check HTTP error: \((response as? HTTPURLResponse)?.statusCode ?? 0)")
                return
            }
            eligibility = try JSONDecoder().decode(CuratorEligibility.self, from: data)

            if eligibility?.isOGHolder == true {
                isOGVerified = true
                isCurator = true
                if !badges.contains(.ogFounder) {
                    badges.append(.ogFounder)
                }
                saveLocalState()
            }
        } catch {
            print("[Curator] Eligibility check error: \(error)")
        }
    }

    /// Apply to become a curator
    func applyForCurator() async -> Bool {
        guard let token = SyncManager.shared.authToken else {
            errorMessage = String(localized: "curator.error.login_required", defaultValue: "chatweb.aiにログインしてください")
            return false
        }

        isLoading = true
        errorMessage = nil

        let baseURL = SyncManager.shared.baseURL
        guard let url = URL(string: "\(baseURL)/api/v1/curators/apply") else {
            isLoading = false
            return false
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("Elio Chat iOS", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                errorMessage = String(localized: "curator.error.apply_failed", defaultValue: "申請に失敗しました")
                isLoading = false
                return false
            }
            if httpResponse.statusCode == 200,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let ok = json["ok"] as? Bool, ok {
                isCurator = true
                saveLocalState()
                isLoading = false
                return true
            } else {
                let errorMsg = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String
                errorMessage = errorMsg ?? String(localized: "curator.error.apply_failed", defaultValue: "申請に失敗しました")
            }
        } catch {
            errorMessage = String(localized: "curator.error.apply_error", defaultValue: "エラー: \(error.localizedDescription)")
        }

        isLoading = false
        return false
    }

    // MARK: - Curator Stats

    /// Fetch curator stats
    func fetchCuratorStats() async {
        guard let token = SyncManager.shared.authToken else { return }

        let baseURL = SyncManager.shared.baseURL
        // TODO: This endpoint does not exist in elio-api yet. Needs to be added.
        guard let url = URL(string: "\(baseURL)/api/v1/curators/me/stats") else { return }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("Elio Chat iOS", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                print("[Curator] Stats fetch HTTP error: \((response as? HTTPURLResponse)?.statusCode ?? 0)")
                return
            }
            curatorStats = try JSONDecoder().decode(CuratorStats.self, from: data)

            // Update curator rank badge
            if let stats = curatorStats {
                let rank = stats.curatorRank
                updateCuratorBadge(rank: rank)
            }
        } catch {
            print("[Curator] Stats fetch error: \(error)")
        }
    }

    // MARK: - Pending Skills

    /// Fetch pending skills for review
    func fetchPendingSkills() async {
        guard let token = SyncManager.shared.authToken else { return }

        isLoading = true
        defer { isLoading = false }

        let baseURL = SyncManager.shared.baseURL
        guard let url = URL(string: "\(baseURL)/api/v1/skills/pending") else { return }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("Elio Chat iOS", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                print("[Curator] Pending skills fetch HTTP error: \((response as? HTTPURLResponse)?.statusCode ?? 0)")
                return
            }
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let skillsData = try? JSONSerialization.data(withJSONObject: json["skills"] ?? []) {
                pendingSkills = (try? JSONDecoder().decode([PendingSkill].self, from: skillsData)) ?? []
            }
        } catch {
            print("[Curator] Pending skills fetch error: \(error)")
        }
    }

    // MARK: - Review Actions

    /// Approve a skill
    func approveSkill(skillId: String, comment: String) async -> Bool {
        return await submitReview(skillId: skillId, action: "approve", comment: comment)
    }

    /// Reject a skill
    func rejectSkill(skillId: String, comment: String) async -> Bool {
        return await submitReview(skillId: skillId, action: "reject", comment: comment)
    }

    private func submitReview(skillId: String, action: String, comment: String) async -> Bool {
        guard let token = SyncManager.shared.authToken else {
            errorMessage = String(localized: "curator.error.login_required", defaultValue: "chatweb.aiにログインしてください")
            return false
        }

        let baseURL = SyncManager.shared.baseURL
        guard let url = URL(string: "\(baseURL)/api/v1/skills/\(skillId)/\(action)") else { return false }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("Elio Chat iOS", forHTTPHeaderField: "User-Agent")
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "comment": comment,
        ])

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                print("[Curator] Review submit HTTP error: \((response as? HTTPURLResponse)?.statusCode ?? 0)")
                return false
            }
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let ok = json["ok"] as? Bool, ok {
                // Remove from pending list
                pendingSkills.removeAll { $0.id == skillId }
                return true
            }
        } catch {
            print("[Curator] Review submit error: \(error)")
        }
        return false
    }

    // MARK: - Badge Management

    private func updateCuratorBadge(rank: CuratorRank) {
        // Remove old curator badges
        badges.removeAll { badge in
            switch badge {
            case .curatorBronze, .curatorSilver, .curatorGold, .curatorDiamond:
                return true
            default:
                return false
            }
        }

        // Add current rank badge
        let badge: BadgeType
        switch rank {
        case .bronze: badge = .curatorBronze
        case .silver: badge = .curatorSilver
        case .gold: badge = .curatorGold
        case .diamond: badge = .curatorDiamond
        }
        badges.append(badge)
        saveLocalState()
    }

    // MARK: - Persistence

    private func loadLocalState() {
        let defaults = UserDefaults.standard
        isCurator = defaults.bool(forKey: isCuratorKey)
        isOGVerified = defaults.bool(forKey: isOGVerifiedKey)
        ogVerificationStatus = isOGVerified ? .verified : .unverified

        if let data = defaults.data(forKey: badgesKey),
           let decoded = try? JSONDecoder().decode([BadgeType].self, from: data) {
            badges = decoded
        }
    }

    private func saveLocalState() {
        let defaults = UserDefaults.standard
        defaults.set(isCurator, forKey: isCuratorKey)
        defaults.set(isOGVerified, forKey: isOGVerifiedKey)

        if let data = try? JSONEncoder().encode(badges) {
            defaults.set(data, forKey: badgesKey)
        }
    }
}
