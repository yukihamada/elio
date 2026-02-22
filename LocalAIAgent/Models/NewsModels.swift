import Foundation

// MARK: - News Article

struct NewsArticle: Codable, Identifiable {
    let id: String
    let title: String
    let summary: String?
    let url: String
    let source: String?
    let category: String?
    let imageURL: String?
    let publishedAt: Date?
    let author: String?

    enum CodingKeys: String, CodingKey {
        case id, title, summary, url, source, category, author
        case imageURL = "image_url"
        case publishedAt = "published_at"
    }
}

// MARK: - News API Response

struct NewsArticlesResponse: Codable {
    let articles: [NewsArticle]
    let nextCursor: String?

    enum CodingKeys: String, CodingKey {
        case articles
        case nextCursor = "next_cursor"
    }
}

// MARK: - News Category

enum NewsCategory: String, CaseIterable, Identifiable {
    case general
    case tech
    case business
    case entertainment
    case sports
    case science
    case podcast

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .general: return String(localized: "news.category.general", defaultValue: "総合")
        case .tech: return String(localized: "news.category.tech", defaultValue: "テック")
        case .business: return String(localized: "news.category.business", defaultValue: "ビジネス")
        case .entertainment: return String(localized: "news.category.entertainment", defaultValue: "エンタメ")
        case .sports: return String(localized: "news.category.sports", defaultValue: "スポーツ")
        case .science: return String(localized: "news.category.science", defaultValue: "サイエンス")
        case .podcast: return String(localized: "news.category.podcast", defaultValue: "ポッドキャスト")
        }
    }

    var icon: String {
        switch self {
        case .general: return "newspaper"
        case .tech: return "desktopcomputer"
        case .business: return "chart.line.uptrend.xyaxis"
        case .entertainment: return "film"
        case .sports: return "sportscourt"
        case .science: return "atom"
        case .podcast: return "mic.fill"
        }
    }
}
