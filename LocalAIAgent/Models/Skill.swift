import Foundation
import SwiftUI

// MARK: - Skill Model

struct Skill: Codable, Identifiable {
    let id: String
    let name: String
    let description: String
    let authorId: String
    let authorName: String
    let category: SkillCategory
    let version: String
    let mcpConfig: SkillMCPConfig
    let iconUrl: String?
    let tags: [String]
    let priceTokens: Int
    let installCount: Int
    let averageRating: Double
    let ratingCount: Int
    let status: SkillStatus
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, name, description, version, tags, status
        case authorId = "author_id"
        case authorName = "author_name"
        case category
        case mcpConfig = "mcp_config"
        case iconUrl = "icon_url"
        case priceTokens = "price_tokens"
        case installCount = "install_count"
        case averageRating = "average_rating"
        case ratingCount = "rating_count"
        case createdAt = "created_at"
    }
}

// MARK: - Skill MCP Config

struct SkillMCPConfig: Codable {
    let serverId: String
    let serverName: String
    let serverDescription: String
    let icon: String
    let tools: [SkillToolConfig]

    enum CodingKeys: String, CodingKey {
        case serverId = "server_id"
        case serverName = "server_name"
        case serverDescription = "server_description"
        case icon, tools
    }

    /// Convert to CustomServerConfig for MCPServerRegistry
    func toCustomServerConfig() -> CustomServerConfig {
        CustomServerConfig(
            id: serverId,
            name: serverName,
            description: serverDescription,
            icon: icon,
            tools: tools.map { tool in
                CustomToolConfig(
                    name: tool.name,
                    description: tool.description,
                    inputSchema: tool.inputSchema,
                    actionType: CustomActionType(rawValue: tool.actionType) ?? .httpRequest,
                    actionConfig: tool.actionConfig
                )
            }
        )
    }
}

struct SkillToolConfig: Codable {
    let name: String
    let description: String
    let inputSchema: MCPInputSchema
    let actionType: String
    let actionConfig: [String: String]?

    enum CodingKeys: String, CodingKey {
        case name, description
        case inputSchema = "input_schema"
        case actionType = "action_type"
        case actionConfig = "action_config"
    }
}

// MARK: - Skill Category

enum SkillCategory: String, Codable, CaseIterable {
    case language = "language"
    case safety = "safety"
    case code = "code"
    case creative = "creative"
    case tools = "tools"
    case other = "other"

    var displayName: String {
        switch self {
        case .language: return "言語 / Language"
        case .safety: return "安全 / Safety"
        case .code: return "コード / Code"
        case .creative: return "クリエイティブ / Creative"
        case .tools: return "ツール / Tools"
        case .other: return "その他 / Other"
        }
    }

    var shortName: String {
        switch self {
        case .language: return "言語"
        case .safety: return "安全"
        case .code: return "コード"
        case .creative: return "クリエイティブ"
        case .tools: return "ツール"
        case .other: return "その他"
        }
    }

    var iconName: String {
        switch self {
        case .language: return "globe"
        case .safety: return "shield.checkered"
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .creative: return "paintbrush.fill"
        case .tools: return "wrench.and.screwdriver.fill"
        case .other: return "ellipsis.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .language: return .blue
        case .safety: return .red
        case .code: return .green
        case .creative: return .purple
        case .tools: return .orange
        case .other: return .gray
        }
    }
}

// MARK: - Skill Status

enum SkillStatus: String, Codable {
    case pending = "pending"
    case inReview = "in_review"
    case approved = "approved"
    case rejected = "rejected"

    var displayName: String {
        switch self {
        case .pending: return "審査待ち"
        case .inReview: return "審査中"
        case .approved: return "承認済み"
        case .rejected: return "却下"
        }
    }
}

// MARK: - Skill Review

struct SkillReview: Codable, Identifiable {
    let id: String
    let skillId: String
    let userId: String
    let userName: String
    let rating: Int
    let comment: String
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case skillId = "skill_id"
        case userId = "user_id"
        case userName = "user_name"
        case rating, comment
        case createdAt = "created_at"
    }
}

// MARK: - API Response Types

struct SkillListResponse: Codable {
    let skills: [Skill]
    let total: Int?
}

struct SkillDetailResponse: Codable {
    let skill: Skill
    let reviews: [SkillReview]?
}

struct SkillInstallResponse: Codable {
    let ok: Bool
    let error: String?
}

struct SkillPublishResponse: Codable {
    let ok: Bool
    let skillId: String?
    let error: String?

    enum CodingKeys: String, CodingKey {
        case ok
        case skillId = "skill_id"
        case error
    }
}

struct SkillReviewResponse: Codable {
    let ok: Bool
    let error: String?
}

// MARK: - Installed Skill (Local)

struct InstalledSkill: Codable, Identifiable {
    let id: String
    let skillId: String
    let name: String
    let description: String
    let authorName: String
    let category: SkillCategory
    let version: String
    let mcpConfig: SkillMCPConfig
    let iconUrl: String?
    let installedAt: Date
    var isEnabled: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case skillId = "skill_id"
        case name, description
        case authorName = "author_name"
        case category, version
        case mcpConfig = "mcp_config"
        case iconUrl = "icon_url"
        case installedAt = "installed_at"
        case isEnabled = "is_enabled"
    }
}
