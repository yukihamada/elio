import Foundation
import SwiftUI

// MARK: - Agent Profile

struct AgentProfile: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var description: String
    var systemPrompt: String
    var icon: String          // SF Symbol name
    var colorHex: String      // Hex color string
    var category: AgentCategory
    var isBuiltIn: Bool       // Built-in agents can't be deleted
    var enabledTools: Set<String>?  // nil = use default, empty = no tools
    var temperature: Double?  // nil = use model default
    var createdAt: Date
    var updatedAt: Date

    var color: Color {
        Color(hex: colorHex) ?? .blue
    }

    init(
        id: UUID = UUID(),
        name: String,
        description: String,
        systemPrompt: String,
        icon: String = "brain",
        colorHex: String = "#6366F1",
        category: AgentCategory = .general,
        isBuiltIn: Bool = false,
        enabledTools: Set<String>? = nil,
        temperature: Double? = nil
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.systemPrompt = systemPrompt
        self.icon = icon
        self.colorHex = colorHex
        self.category = category
        self.isBuiltIn = isBuiltIn
        self.enabledTools = enabledTools
        self.temperature = temperature
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}

// MARK: - Agent Category

enum AgentCategory: String, Codable, CaseIterable {
    case general = "general"
    case creative = "creative"
    case technical = "technical"
    case business = "business"
    case lifestyle = "lifestyle"
    case custom = "custom"

    var displayName: String {
        switch self {
        case .general: return "汎用"
        case .creative: return "クリエイティブ"
        case .technical: return "テクニカル"
        case .business: return "ビジネス"
        case .lifestyle: return "ライフスタイル"
        case .custom: return "カスタム"
        }
    }

    var icon: String {
        switch self {
        case .general: return "sparkles"
        case .creative: return "paintbrush"
        case .technical: return "wrench.and.screwdriver"
        case .business: return "briefcase"
        case .lifestyle: return "heart"
        case .custom: return "star"
        }
    }
}

// MARK: - Color Extension

extension Color {
    init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        guard hexSanitized.count == 6,
              let rgb = UInt64(hexSanitized, radix: 16) else {
            return nil
        }

        self.init(
            red: Double((rgb >> 16) & 0xFF) / 255.0,
            green: Double((rgb >> 8) & 0xFF) / 255.0,
            blue: Double(rgb & 0xFF) / 255.0
        )
    }
}
