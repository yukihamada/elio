import Foundation
import SwiftUI

/// Extracts readable content from web pages
actor WebContentExtractor {
    static let shared = WebContentExtractor()

    private init() {}

    /// Extract text content from a URL
    func extractContent(from urlString: String) async throws -> WebContent {
        guard let url = URL(string: urlString) else {
            throw WebContentError.invalidURL
        }

        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw WebContentError.fetchFailed
        }

        guard let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .ascii) else {
            throw WebContentError.encodingError
        }

        let title = extractTitle(from: html)
        let text = extractText(from: html)

        return WebContent(
            url: url,
            title: title,
            text: text,
            fetchedAt: Date()
        )
    }

    /// Check if a string contains a URL
    func detectURL(in text: String) -> URL? {
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let matches = detector?.matches(in: text, options: [], range: NSRange(text.startIndex..., in: text))

        if let match = matches?.first,
           let range = Range(match.range, in: text) {
            let urlString = String(text[range])
            return URL(string: urlString)
        }
        return nil
    }

    // MARK: - Private Methods

    private func extractTitle(from html: String) -> String {
        // Try to find <title> tag
        if let titleRange = html.range(of: "<title>", options: .caseInsensitive),
           let titleEndRange = html.range(of: "</title>", options: .caseInsensitive, range: titleRange.upperBound..<html.endIndex) {
            let title = String(html[titleRange.upperBound..<titleEndRange.lowerBound])
            return decodeHTMLEntities(title).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // Try og:title
        if let ogTitle = extractMetaContent(from: html, property: "og:title") {
            return ogTitle
        }

        return "Untitled"
    }

    private func extractMetaContent(from html: String, property: String) -> String? {
        let pattern = "<meta[^>]*property=[\"']\(property)[\"'][^>]*content=[\"']([^\"']*)[\"']"
        if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
           let match = regex.firstMatch(in: html, options: [], range: NSRange(html.startIndex..., in: html)),
           let range = Range(match.range(at: 1), in: html) {
            return decodeHTMLEntities(String(html[range]))
        }
        return nil
    }

    private func extractText(from html: String) -> String {
        var text = html

        // Remove script and style tags with their content
        text = removeTag(text, tag: "script")
        text = removeTag(text, tag: "style")
        text = removeTag(text, tag: "noscript")
        text = removeTag(text, tag: "header")
        text = removeTag(text, tag: "footer")
        text = removeTag(text, tag: "nav")
        text = removeTag(text, tag: "aside")

        // Try to extract main content areas
        if let mainContent = extractTagContent(from: text, tag: "article") ??
                            extractTagContent(from: text, tag: "main") {
            text = mainContent
        }

        // Remove all HTML tags
        text = text.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)

        // Decode HTML entities
        text = decodeHTMLEntities(text)

        // Clean up whitespace
        text = text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Limit length to prevent overwhelming the model
        let maxLength = 10000
        if text.count > maxLength {
            let index = text.index(text.startIndex, offsetBy: maxLength)
            text = String(text[..<index]) + "..."
        }

        return text
    }

    private func removeTag(_ html: String, tag: String) -> String {
        let pattern = "<\(tag)[^>]*>.*?</\(tag)>"
        return html.replacingOccurrences(of: pattern, with: "", options: [.regularExpression, .caseInsensitive])
    }

    private func extractTagContent(from html: String, tag: String) -> String? {
        let pattern = "<\(tag)[^>]*>(.*?)</\(tag)>"
        if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]),
           let match = regex.firstMatch(in: html, options: [], range: NSRange(html.startIndex..., in: html)),
           let range = Range(match.range(at: 1), in: html) {
            return String(html[range])
        }
        return nil
    }

    private func decodeHTMLEntities(_ text: String) -> String {
        var result = text
        let entities: [String: String] = [
            "&nbsp;": " ",
            "&amp;": "&",
            "&lt;": "<",
            "&gt;": ">",
            "&quot;": "\"",
            "&apos;": "'",
            "&#39;": "'",
            "&mdash;": "—",
            "&ndash;": "–",
            "&hellip;": "...",
            "&copy;": "©",
            "&reg;": "®",
            "&trade;": "™"
        ]

        for (entity, char) in entities {
            result = result.replacingOccurrences(of: entity, with: char)
        }

        // Handle numeric entities like &#123;
        let numericPattern = "&#(\\d+);"
        var searchRange = result.startIndex..<result.endIndex
        while let matchRange = result.range(of: numericPattern, options: .regularExpression, range: searchRange) {
            let matchedString = String(result[matchRange])
            // Extract the number
            let numString = matchedString.dropFirst(2).dropLast(1)
            if let num = Int(numString), let scalar = Unicode.Scalar(num) {
                result.replaceSubrange(matchRange, with: String(Character(scalar)))
                searchRange = result.startIndex..<result.endIndex  // Reset after replacement
            } else {
                searchRange = matchRange.upperBound..<result.endIndex
            }
        }

        return result
    }
}

// MARK: - Models

struct WebContent {
    let url: URL
    let title: String
    let text: String
    let fetchedAt: Date

    var summary: String {
        let preview = text.prefix(200)
        return preview.count < text.count ? "\(preview)..." : String(preview)
    }
}

enum WebContentError: LocalizedError {
    case invalidURL
    case fetchFailed
    case encodingError

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .fetchFailed:
            return "Failed to fetch page"
        case .encodingError:
            return "Failed to decode page content"
        }
    }
}
