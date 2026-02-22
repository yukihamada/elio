import Foundation

/// API client for news.xyz news aggregation service
@MainActor
final class NewsAPIClient {
    static let shared = NewsAPIClient()

    private let baseURL = "https://news.xyz"
    private let session: URLSession
    private let decoder: JSONDecoder

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        session = URLSession(configuration: config)

        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    // MARK: - Public API

    /// Fetch articles with optional category filter and pagination
    func fetchArticles(
        category: NewsCategory? = nil,
        limit: Int = 10,
        cursor: String? = nil
    ) async throws -> NewsArticlesResponse {
        var components = URLComponents(string: "\(baseURL)/api/articles")!
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "limit", value: "\(limit)")
        ]
        if let category {
            queryItems.append(URLQueryItem(name: "category", value: category.rawValue))
        }
        if let cursor {
            queryItems.append(URLQueryItem(name: "cursor", value: cursor))
        }
        components.queryItems = queryItems

        let request = buildRequest(url: components.url!)
        let (data, response) = try await session.data(for: request)
        try validateResponse(response)
        return try decoder.decode(NewsArticlesResponse.self, from: data)
    }

    /// Search articles by query
    func searchArticles(query: String, limit: Int = 10) async throws -> NewsArticlesResponse {
        var components = URLComponents(string: "\(baseURL)/api/search")!
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "limit", value: "\(limit)")
        ]

        let request = buildRequest(url: components.url!)
        let (data, response) = try await session.data(for: request)
        try validateResponse(response)
        return try decoder.decode(NewsArticlesResponse.self, from: data)
    }

    /// Get a summarized news digest for the given time period
    func summarizeNews(minutes: Int = 60) async throws -> String {
        var components = URLComponents(string: "\(baseURL)/api/summarize")!
        components.queryItems = [
            URLQueryItem(name: "minutes", value: "\(minutes)")
        ]

        let request = buildRequest(url: components.url!)
        let (data, response) = try await session.data(for: request)
        try validateResponse(response)

        struct SummaryResponse: Codable {
            let summary: String
        }
        let result = try decoder.decode(SummaryResponse.self, from: data)
        return result.summary
    }

    // MARK: - Private

    private func buildRequest(url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Elio Chat iOS", forHTTPHeaderField: "User-Agent")
        request.setValue(DeviceIdentityManager.shared.deviceId, forHTTPHeaderField: "x-device-id")
        return request
    }

    private func validateResponse(_ response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NewsAPIError.invalidResponse
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw NewsAPIError.serverError(httpResponse.statusCode)
        }
    }
}

// MARK: - Errors

enum NewsAPIError: Error, LocalizedError {
    case invalidResponse
    case serverError(Int)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from news server"
        case .serverError(let code):
            return "News server error: \(code)"
        }
    }
}
