import Foundation
import Network

/// MCP Server for Ghost Search - Privacy-focused web search via DuckDuckGo
final class WebSearchServer: MCPServer {
    let id = "websearch"
    let name = "Ghost Search"
    let serverDescription = "DuckDuckGoで匿名検索（追跡なし）"
    let icon = "theatermasks.fill"

    /// Check network connectivity
    private var isOnline: Bool {
        // Quick sync check using NWPathMonitor cached state
        let monitor = NWPathMonitor()
        let queue = DispatchQueue(label: "NetworkCheck")
        var isConnected = false
        let semaphore = DispatchSemaphore(value: 0)

        monitor.pathUpdateHandler = { path in
            isConnected = path.status == .satisfied
            semaphore.signal()
        }
        monitor.start(queue: queue)

        // Wait briefly for network status
        _ = semaphore.wait(timeout: .now() + 0.5)
        monitor.cancel()

        return isConnected
    }

    func listPrompts() -> [MCPPrompt] {
        [
            MCPPrompt(
                name: "ghost_research",
                description: "匿名でトピックを調査します",
                descriptionEn: "Research a topic anonymously",
                arguments: [
                    MCPPromptArgument(name: "topic", description: "調査するトピック", descriptionEn: "Topic to research", required: true)
                ]
            ),
            MCPPrompt(
                name: "news_search",
                description: "最新ニュースを匿名検索します",
                descriptionEn: "Search for latest news anonymously",
                arguments: [
                    MCPPromptArgument(name: "topic", description: "ニューストピック", descriptionEn: "News topic", required: true)
                ]
            )
        ]
    }

    func getPrompt(name: String, arguments: [String: String]) -> MCPPromptResult? {
        switch name {
        case "ghost_research":
            let topic = arguments["topic"] ?? "topic"
            return MCPPromptResult(messages: [
                MCPPromptMessage(role: "user", content: .text("Ghost Searchを使って「\(topic)」について調べてください。検索結果をまとめて、重要なポイントを教えてください。"))
            ])
        case "news_search":
            let topic = arguments["topic"] ?? "最新ニュース"
            return MCPPromptResult(messages: [
                MCPPromptMessage(role: "user", content: .text("Ghost Searchで「\(topic)」の最新ニュースを検索してください。主要なニュースをまとめてください。"))
            ])
        default:
            return nil
        }
    }

    func listTools() -> [MCPTool] {
        [
            MCPTool(
                name: "ghost_search",
                description: "DuckDuckGoで匿名Web検索を行います。追跡なしでプライバシーを守りながら最新情報を検索できます。",
                inputSchema: MCPInputSchema(
                    type: "object",
                    properties: [
                        "query": MCPPropertySchema(
                            type: "string",
                            description: "検索キーワード"
                        ),
                        "limit": MCPPropertySchema(
                            type: "integer",
                            description: "検索結果の最大数（デフォルト: 5）"
                        )
                    ],
                    required: ["query"]
                )
            )
        ]
    }

    func callTool(name: String, arguments: [String: JSONValue]) async throws -> MCPResult {
        switch name {
        case "ghost_search", "web_search": // Support both names for compatibility
            return try await performGhostSearch(arguments)
        default:
            throw MCPClientError.toolNotFound(name)
        }
    }

    private func performGhostSearch(_ arguments: [String: JSONValue]) async throws -> MCPResult {
        guard case .string(let query) = arguments["query"] else {
            throw MCPClientError.invalidArguments("queryは必須です")
        }

        // Check network connectivity first
        guard isOnline else {
            let offlineResult = """
            【オフラインモード】

            現在インターネットに接続されていないため、Web検索は利用できません。

            🔒 オフラインでも利用可能な機能:
            • ローカルAIによる質問回答
            • カレンダー・リマインダーの確認
            • 連絡先の検索
            • 写真の閲覧
            • ヘルスデータの確認

            インターネットに接続すると、Web検索が利用可能になります。
            """
            return MCPResult(content: [MCPContent.text(offlineResult)])
        }

        let limit: Int
        if case .int(let limitValue) = arguments["limit"] {
            limit = limitValue
        } else {
            limit = 5
        }

        // Use DuckDuckGo Instant Answer API (no API key required, no tracking)
        let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        let urlString = "https://api.duckduckgo.com/?q=\(encodedQuery)&format=json&no_html=1&skip_disambig=1"

        guard let url = URL(string: urlString) else {
            throw MCPClientError.executionFailed("Invalid URL")
        }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                throw MCPClientError.executionFailed("Ghost Search接続に失敗しました")
            }

            let result = try JSONDecoder().decode(DuckDuckGoResponse.self, from: data)
            let formattedResult = formatGhostSearchResults(result, limit: limit, query: query)

            return MCPResult(content: [MCPContent.text(formattedResult)])
        } catch let error as MCPClientError {
            throw error
        } catch {
            // Fallback: return message when API fails
            let fallbackResult = """
            【Ghost Search: "\(query)"】

            匿名回線への接続に失敗しました。
            インターネット接続を確認してください。
            オフライン時は、ローカルAIの知識を使って回答します。
            """
            return MCPResult(content: [MCPContent.text(fallbackResult)])
        }
    }

    private func formatGhostSearchResults(_ response: DuckDuckGoResponse, limit: Int, query: String) -> String {
        var results: [String] = []

        // Abstract (main answer)
        if !response.Abstract.isEmpty {
            results.append("【概要】\n\(response.Abstract)")
            if !response.AbstractSource.isEmpty {
                results.append("出典: \(response.AbstractSource)")
            }
        }

        // Related topics
        let topics = response.RelatedTopics.prefix(limit)
        if !topics.isEmpty {
            results.append("\n【関連情報】")
            for (index, topic) in topics.enumerated() {
                if !topic.Text.isEmpty {
                    results.append("\(index + 1). \(topic.Text)")
                    if let firstURL = topic.FirstURL, !firstURL.isEmpty {
                        results.append("   URL: \(firstURL)")
                    }
                }
            }
        }

        // If no results found
        if results.isEmpty {
            return """
            【Ghost Search: "\(query)"】

            直接的な検索結果は見つかりませんでした。
            別のキーワードで試すか、ローカルAIの知識を使って回答します。
            """
        }

        return "【Ghost Search: \"\(query)\" - DuckDuckGo経由・追跡なし】\n\n" + results.joined(separator: "\n")
    }
}

// MARK: - DuckDuckGo API Response

struct DuckDuckGoResponse: Codable {
    let Abstract: String
    let AbstractSource: String
    let AbstractURL: String
    let Answer: String
    let AnswerType: String
    let Heading: String
    let RelatedTopics: [DuckDuckGoTopic]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        Abstract = try container.decodeIfPresent(String.self, forKey: .Abstract) ?? ""
        AbstractSource = try container.decodeIfPresent(String.self, forKey: .AbstractSource) ?? ""
        AbstractURL = try container.decodeIfPresent(String.self, forKey: .AbstractURL) ?? ""
        Answer = try container.decodeIfPresent(String.self, forKey: .Answer) ?? ""
        AnswerType = try container.decodeIfPresent(String.self, forKey: .AnswerType) ?? ""
        Heading = try container.decodeIfPresent(String.self, forKey: .Heading) ?? ""

        // RelatedTopics can contain mixed types (topics and groups)
        if let topics = try? container.decode([DuckDuckGoTopic].self, forKey: .RelatedTopics) {
            RelatedTopics = topics
        } else {
            RelatedTopics = []
        }
    }

    enum CodingKeys: String, CodingKey {
        case Abstract
        case AbstractSource
        case AbstractURL
        case Answer
        case AnswerType
        case Heading
        case RelatedTopics
    }
}

struct DuckDuckGoTopic: Codable {
    let Text: String
    let FirstURL: String?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        Text = try container.decodeIfPresent(String.self, forKey: .Text) ?? ""
        FirstURL = try container.decodeIfPresent(String.self, forKey: .FirstURL)
    }

    enum CodingKeys: String, CodingKey {
        case Text
        case FirstURL
    }
}
