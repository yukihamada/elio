import Foundation

/// MCP Server for news.xyz — provides news articles, search, and summaries to the LLM
final class NewsServer: MCPServer {
    let id = "news"
    let name = "ニュース"
    let serverDescription = "最新ニュースの取得・検索・要約を提供します"
    let icon = "newspaper"

    func listTools() -> [MCPTool] {
        [
            MCPTool(
                name: "get_news",
                description: "最新ニュースを取得します / Get latest news articles",
                inputSchema: MCPInputSchema(
                    properties: [
                        "category": MCPPropertySchema(
                            type: "string",
                            description: "カテゴリ (general/tech/business/entertainment/sports/science/podcast)",
                            enumValues: NewsCategory.allCases.map(\.rawValue)
                        ),
                        "limit": MCPPropertySchema(
                            type: "number",
                            description: "取得件数 (デフォルト: 10)"
                        )
                    ],
                    required: nil
                )
            ),
            MCPTool(
                name: "search_news",
                description: "ニュースをキーワードで検索します / Search news articles by keyword",
                inputSchema: MCPInputSchema(
                    properties: [
                        "query": MCPPropertySchema(
                            type: "string",
                            description: "検索キーワード / Search keyword"
                        )
                    ],
                    required: ["query"]
                )
            ),
            MCPTool(
                name: "summarize_news",
                description: "最近のニュースを要約します / Summarize recent news",
                inputSchema: MCPInputSchema(
                    properties: [
                        "minutes": MCPPropertySchema(
                            type: "number",
                            description: "何分前までのニュースを要約するか (デフォルト: 60)"
                        )
                    ],
                    required: nil
                )
            )
        ]
    }

    func callTool(name: String, arguments: [String: JSONValue]) async throws -> MCPResult {
        switch name {
        case "get_news":
            return try await handleGetNews(arguments: arguments)
        case "search_news":
            return try await handleSearchNews(arguments: arguments)
        case "summarize_news":
            return try await handleSummarizeNews(arguments: arguments)
        default:
            throw MCPClientError.toolNotFound(name)
        }
    }

    // MARK: - Tool Handlers

    private func handleGetNews(arguments: [String: JSONValue]) async throws -> MCPResult {
        let category: NewsCategory?
        if case .string(let cat) = arguments["category"] {
            category = NewsCategory(rawValue: cat)
        } else {
            category = nil
        }

        let limit: Int
        if case .int(let n) = arguments["limit"] {
            limit = min(n, 20)
        } else if case .double(let n) = arguments["limit"] {
            limit = min(Int(n), 20)
        } else {
            limit = 10
        }

        let response = try await NewsAPIClient.shared.fetchArticles(
            category: category,
            limit: limit
        )

        let text = formatArticles(response.articles)
        return MCPResult(content: [MCPContent(type: "text", text: text)])
    }

    private func handleSearchNews(arguments: [String: JSONValue]) async throws -> MCPResult {
        guard case .string(let query) = arguments["query"] else {
            throw MCPClientError.invalidArguments("query is required")
        }

        let response = try await NewsAPIClient.shared.searchArticles(query: query)
        let text = formatArticles(response.articles)
        return MCPResult(content: [MCPContent(type: "text", text: text)])
    }

    private func handleSummarizeNews(arguments: [String: JSONValue]) async throws -> MCPResult {
        let minutes: Int
        if case .int(let n) = arguments["minutes"] {
            minutes = n
        } else if case .double(let n) = arguments["minutes"] {
            minutes = Int(n)
        } else {
            minutes = 60
        }

        let summary = try await NewsAPIClient.shared.summarizeNews(minutes: minutes)
        return MCPResult(content: [MCPContent(type: "text", text: summary)])
    }

    // MARK: - Formatting

    private func formatArticles(_ articles: [NewsArticle]) -> String {
        if articles.isEmpty {
            return "ニュースが見つかりませんでした。"
        }

        return articles.enumerated().map { index, article in
            var line = "\(index + 1). \(article.title)"
            if let source = article.source {
                line += " (\(source))"
            }
            if let summary = article.summary {
                line += "\n   \(summary)"
            }
            if let date = article.publishedAt {
                let formatter = RelativeDateTimeFormatter()
                formatter.locale = Locale(identifier: "ja_JP")
                line += "\n   \(formatter.localizedString(for: date, relativeTo: Date()))"
            }
            line += "\n   URL: \(article.url)"
            return line
        }.joined(separator: "\n\n")
    }
}
