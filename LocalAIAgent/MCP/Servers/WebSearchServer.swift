import Foundation

/// MCP Server for Web Search - Privacy-focused web search via DuckDuckGo
final class WebSearchServer: MCPServer {
    let id = "websearch"
    let name = "Web検索"
    let serverDescription = "DuckDuckGoでWeb検索"
    let icon = "magnifyingglass"

    /// Check network connectivity using the shared monitor (no semaphore blocking)
    private func isOnline() async -> Bool {
        await MainActor.run { NetworkMonitor.shared.isConnected }
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
                MCPPromptMessage(role: "user", content: .text("Web検索を使って「\(topic)」について調べてください。検索結果をまとめて、重要なポイントを教えてください。"))
            ])
        case "news_search":
            let topic = arguments["topic"] ?? "最新ニュース"
            return MCPPromptResult(messages: [
                MCPPromptMessage(role: "user", content: .text("Web検索で「\(topic)」の最新ニュースを検索してください。主要なニュースをまとめてください。"))
            ])
        default:
            return nil
        }
    }

    func listTools() -> [MCPTool] {
        [
            MCPTool(
                name: "web_search",
                description: "Web検索を行い、最新情報を取得します",
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
        case "web_search":
            return try await performWebSearch(arguments)
        default:
            throw MCPClientError.toolNotFound(name)
        }
    }

    private func performWebSearch(_ arguments: [String: JSONValue]) async throws -> MCPResult {
        guard case .string(let query) = arguments["query"] else {
            throw MCPClientError.invalidArguments("queryは必須です")
        }

        // Check network connectivity first
        guard await isOnline() else {
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
            limit = min(limitValue, 10)
        } else {
            limit = 5
        }

        // Use DuckDuckGo HTML search for real web search results
        let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        let urlString = "https://html.duckduckgo.com/html/?q=\(encodedQuery)"

        guard let url = URL(string: urlString) else {
            throw MCPClientError.executionFailed("Invalid URL")
        }

        do {
            var request = URLRequest(url: url)
            request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")
            request.setValue("text/html", forHTTPHeaderField: "Accept")

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                throw MCPClientError.executionFailed("Web検索接続に失敗しました")
            }

            guard let html = String(data: data, encoding: .utf8) else {
                throw MCPClientError.executionFailed("レスポンスの解析に失敗しました")
            }

            let results = parseHTMLSearchResults(html, limit: limit)
            let formattedResult = formatSearchResults(results, query: query)

            return MCPResult(content: [MCPContent.text(formattedResult)])
        } catch let error as MCPClientError {
            throw error
        } catch {
            // Fallback: return message when search fails
            let fallbackResult = """
            【Web検索: "\(query)"】

            検索に失敗しました: \(error.localizedDescription)
            インターネット接続を確認してください。
            """
            return MCPResult(content: [MCPContent.text(fallbackResult)])
        }
    }

    /// Parse DuckDuckGo HTML search results
    private func parseHTMLSearchResults(_ html: String, limit: Int) -> [SearchResult] {
        var results: [SearchResult] = []

        // Find all result links and snippets using simple regex patterns
        let linkPattern = #"<a rel="nofollow" class="result__a" href="([^"]+)">(.+?)</a>"#
        let snippetPattern = #"<a class="result__snippet"[^>]*>(.+?)</a>"#

        // Try to extract using regex
        do {
            let linkRegex = try NSRegularExpression(pattern: linkPattern, options: [.dotMatchesLineSeparators])
            let snippetRegex = try NSRegularExpression(pattern: snippetPattern, options: [.dotMatchesLineSeparators])

            let linkMatches = linkRegex.matches(in: html, options: [], range: NSRange(html.startIndex..., in: html))
            let snippetMatches = snippetRegex.matches(in: html, options: [], range: NSRange(html.startIndex..., in: html))

            for (index, match) in linkMatches.prefix(limit).enumerated() {
                guard let urlRange = Range(match.range(at: 1), in: html),
                      let titleRange = Range(match.range(at: 2), in: html) else {
                    continue
                }

                var url = String(html[urlRange])
                let title = cleanHTML(String(html[titleRange]))

                // DuckDuckGo uses redirect URLs, extract the actual URL
                if url.contains("uddg=") {
                    if let encodedURL = url.components(separatedBy: "uddg=").last?.components(separatedBy: "&").first,
                       let decodedURL = encodedURL.removingPercentEncoding {
                        url = decodedURL
                    }
                }

                var snippet = ""
                if index < snippetMatches.count {
                    if let snippetRange = Range(snippetMatches[index].range(at: 1), in: html) {
                        snippet = cleanHTML(String(html[snippetRange]))
                    }
                }

                if !title.isEmpty && !url.isEmpty {
                    results.append(SearchResult(title: title, url: url, snippet: snippet))
                }
            }
        } catch {
            print("[WebSearch] Regex error: \(error)")
        }

        return results
    }

    /// Remove HTML tags and decode entities
    private func cleanHTML(_ text: String) -> String {
        var result = text

        // Remove HTML tags
        result = result.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)

        // Decode common HTML entities
        result = result.replacingOccurrences(of: "&amp;", with: "&")
        result = result.replacingOccurrences(of: "&lt;", with: "<")
        result = result.replacingOccurrences(of: "&gt;", with: ">")
        result = result.replacingOccurrences(of: "&quot;", with: "\"")
        result = result.replacingOccurrences(of: "&#39;", with: "'")
        result = result.replacingOccurrences(of: "&nbsp;", with: " ")
        result = result.replacingOccurrences(of: "&#x27;", with: "'")
        result = result.replacingOccurrences(of: "&#x2F;", with: "/")

        // Trim whitespace
        result = result.trimmingCharacters(in: .whitespacesAndNewlines)

        return result
    }

    private func formatSearchResults(_ results: [SearchResult], query: String) -> String {
        if results.isEmpty {
            return """
            【Web検索: "\(query)"】

            検索結果が見つかりませんでした。
            別のキーワードで試してください。
            """
        }

        var output = "【Web検索: \"\(query)\" - DuckDuckGo経由・追跡なし】\n\n"

        for (index, result) in results.enumerated() {
            output += "[\(index + 1)] \(result.title)\n"
            output += "    URL: \(result.url)\n"
            if !result.snippet.isEmpty {
                output += "    \(result.snippet)\n"
            }
            output += "\n"
        }

        return output
    }
}

// MARK: - Search Result

struct SearchResult {
    let title: String
    let url: String
    let snippet: String
}

