import Foundation

// MARK: - Builtin Web Search (DuckDuckGo HTML scraping - no API key needed)
// Ported from NOU app. Complements the existing MCP WebSearchServer.

struct BuiltinSearchResult {
    let title: String
    let snippet: String
    let url: String
}

actor BuiltinWebSearch {
    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 15
        self.session = URLSession(configuration: config)
    }

    func search(query: String, maxResults: Int = 3) async -> [BuiltinSearchResult] {
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://html.duckduckgo.com/html/?q=\(encoded)") else {
            return []
        }

        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X)", forHTTPHeaderField: "User-Agent")

        do {
            let (data, _) = try await session.data(for: request)
            guard let html = String(data: data, encoding: .utf8) else { return [] }
            return parseResults(html: html, max: maxResults)
        } catch {
            print("[BuiltinWebSearch] Error: \(error.localizedDescription)")
            return []
        }
    }

    func fetchPage(url: String, maxChars: Int = 2000) async -> String? {
        guard let jinaURL = URL(string: "https://r.jina.ai/\(url)") else { return nil }
        var request = URLRequest(url: jinaURL)
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        request.setValue("text/plain", forHTTPHeaderField: "Accept")

        do {
            let (data, _) = try await session.data(for: request)
            guard let text = String(data: data, encoding: .utf8) else { return nil }
            return String(text.prefix(maxChars))
        } catch {
            return nil
        }
    }

    private func parseResults(html: String, max: Int) -> [BuiltinSearchResult] {
        var results: [BuiltinSearchResult] = []

        let linkPattern = #"<a rel="nofollow" class="result__a" href="([^"]*)"[^>]*>([^<]*)</a>"#
        let snippetPattern = #"<a class="result__snippet"[^>]*>([^<]*(?:<b>[^<]*</b>[^<]*)*)</a>"#

        let linkRegex = try? NSRegularExpression(pattern: linkPattern)
        let snippetRegex = try? NSRegularExpression(pattern: snippetPattern)

        let linkMatches = linkRegex?.matches(in: html, range: NSRange(html.startIndex..., in: html)) ?? []
        let snippetMatches = snippetRegex?.matches(in: html, range: NSRange(html.startIndex..., in: html)) ?? []

        for i in 0..<min(max, linkMatches.count) {
            let linkMatch = linkMatches[i]
            guard let urlRange = Range(linkMatch.range(at: 1), in: html),
                  let titleRange = Range(linkMatch.range(at: 2), in: html) else { continue }

            let resultURL = String(html[urlRange])
            let title = String(html[titleRange])
                .replacingOccurrences(of: "<b>", with: "")
                .replacingOccurrences(of: "</b>", with: "")

            var snippet = ""
            if i < snippetMatches.count {
                let sm = snippetMatches[i]
                if let sRange = Range(sm.range(at: 1), in: html) {
                    snippet = String(html[sRange])
                        .replacingOccurrences(of: "<b>", with: "")
                        .replacingOccurrences(of: "</b>", with: "")
                }
            }

            guard !resultURL.isEmpty else { continue }
            results.append(BuiltinSearchResult(title: title, snippet: snippet, url: resultURL))
        }

        return results
    }
}

// MARK: - Calculator Tool

struct BuiltinCalculator {
    func evaluate(_ expr: String) -> String {
        let cleaned = expr
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\u{00D7}", with: "*")
            .replacingOccurrences(of: "\u{00F7}", with: "/")
            .filter { "0123456789.+-*/()".contains($0) }

        guard !cleaned.isEmpty, cleaned.contains(where: { $0.isNumber }) else {
            return "No valid math expression found."
        }

        do {
            let expression = NSExpression(format: cleaned)
            if let result = expression.expressionValue(with: nil, context: nil) as? NSNumber {
                let d = result.doubleValue
                if d == d.rounded() && abs(d) < 1e15 {
                    return String(format: "%.0f", d)
                }
                return String(format: "%.6g", d)
            }
        } catch {
            // NSExpression can throw on invalid format
        }
        return "Could not calculate: \(expr)"
    }
}

// MARK: - DateTime Tool

struct BuiltinDateTime {
    func currentInfo() -> String {
        let now = Date()
        let df = DateFormatter()
        df.locale = Locale(identifier: "ja_JP")
        df.dateFormat = "yyyy\u{5E74}M\u{6708}d\u{65E5}(EEEE) HH:mm"
        let dateStr = df.string(from: now)

        let cal = Calendar.current
        let weekOfYear = cal.component(.weekOfYear, from: now)

        return "\u{73FE}\u{5728}: \(dateStr)\n\u{9031}\u{756A}\u{53F7}: \(weekOfYear)"
    }
}

// MARK: - URL Fetch Tool (via Jina Reader)

struct BuiltinURLFetch {
    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        self.session = URLSession(configuration: config)
    }

    func fetch(url: String, maxChars: Int = 1500) async -> String {
        guard let jinaURL = URL(string: "https://r.jina.ai/\(url)") else {
            return "Invalid URL"
        }
        var request = URLRequest(url: jinaURL)
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        request.setValue("text/plain", forHTTPHeaderField: "Accept")

        do {
            let (data, _) = try await session.data(for: request)
            guard let text = String(data: data, encoding: .utf8) else { return "Failed to read page" }
            return String(text.prefix(maxChars))
        } catch {
            return "Failed to fetch: \(error.localizedDescription)"
        }
    }
}

// MARK: - Unit Conversion Tool

struct BuiltinUnitConvert {
    func convert(_ input: String) -> String {
        let lower = input.lowercased()

        // Temperature
        if let _ = lower.range(of: #"([\d.]+)\s*(c|celsius|°c)\s*(to|→)\s*(f|fahrenheit|°f)"#, options: .regularExpression) {
            let nums = lower.components(separatedBy: CharacterSet.decimalDigits.inverted.subtracting(CharacterSet(charactersIn: ".")))
                .compactMap { Double($0) }
            if let c = nums.first { return "\(c)\u{00B0}C = \(String(format: "%.1f", c * 9/5 + 32))\u{00B0}F" }
        }
        if let _ = lower.range(of: #"([\d.]+)\s*(f|fahrenheit|°f)\s*(to|→)\s*(c|celsius|°c)"#, options: .regularExpression) {
            let nums = lower.components(separatedBy: CharacterSet.decimalDigits.inverted.subtracting(CharacterSet(charactersIn: ".")))
                .compactMap { Double($0) }
            if let f = nums.first { return "\(f)\u{00B0}F = \(String(format: "%.1f", (f - 32) * 5/9))\u{00B0}C" }
        }

        // Distance
        let distPairs: [(String, String, Double)] = [
            ("km", "miles", 0.621371), ("miles", "km", 1.60934),
            ("m", "feet", 3.28084), ("feet", "m", 0.3048),
            ("cm", "inches", 0.393701), ("inches", "cm", 2.54),
        ]
        for (from, to, factor) in distPairs {
            if lower.contains(from) && lower.contains(to) {
                let nums = lower.components(separatedBy: CharacterSet.decimalDigits.inverted.subtracting(CharacterSet(charactersIn: ".")))
                    .compactMap { Double($0) }
                if let val = nums.first { return "\(val) \(from) = \(String(format: "%.2f", val * factor)) \(to)" }
            }
        }

        // Weight
        let weightPairs: [(String, String, Double)] = [
            ("kg", "lbs", 2.20462), ("lbs", "kg", 0.453592),
            ("kg", "pounds", 2.20462), ("pounds", "kg", 0.453592),
        ]
        for (from, to, factor) in weightPairs {
            if lower.contains(from) && lower.contains(to) {
                let nums = lower.components(separatedBy: CharacterSet.decimalDigits.inverted.subtracting(CharacterSet(charactersIn: ".")))
                    .compactMap { Double($0) }
                if let val = nums.first { return "\(val) \(from) = \(String(format: "%.2f", val * factor)) \(to)" }
            }
        }

        if lower.contains("usd") || lower.contains("jpy") || lower.contains("eur") || lower.contains("\u{30C9}\u{30EB}") || lower.contains("\u{5186}") {
            return "Currency conversion needs live rates. Use 'search' tool instead."
        }

        return "Could not parse conversion. Supported: temperature (C\u{2194}F), distance (km\u{2194}miles, m\u{2194}feet, cm\u{2194}inches), weight (kg\u{2194}lbs)"
    }
}

// MARK: - Random Generator Tool

struct BuiltinRandom {
    func generate(_ input: String) -> String {
        let lower = input.lowercased()

        // Password
        if lower.contains("password") || lower.contains("\u{30D1}\u{30B9}\u{30EF}\u{30FC}\u{30C9}") {
            let len = extractNumber(from: lower) ?? 16
            let chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#$%^&*"
            let pw = (0..<len).map { _ in String(chars.randomElement()!) }.joined()
            return "Generated password (\(len) chars): \(pw)"
        }

        // UUID
        if lower.contains("uuid") || lower.contains("id") {
            return "UUID: \(UUID().uuidString)"
        }

        // Dice
        if lower.contains("dice") || lower.contains("\u{30B5}\u{30A4}\u{30B3}\u{30ED}") {
            let n = extractNumber(from: lower) ?? 1
            let rolls = (0..<n).map { _ in Int.random(in: 1...6) }
            return "Dice roll\(n > 1 ? "s" : ""): \(rolls.map(String.init).joined(separator: ", ")) (total: \(rolls.reduce(0, +)))"
        }

        // Coin
        if lower.contains("coin") || lower.contains("\u{30B3}\u{30A4}\u{30F3}") || lower.contains("flip") {
            return Bool.random() ? "Heads (\u{8868})" : "Tails (\u{88CF})"
        }

        // Random number
        let nums = lower.components(separatedBy: CharacterSet.decimalDigits.inverted).compactMap { Int($0) }
        if nums.count >= 2 {
            let lo = min(nums[0], nums[1])
            let hi = max(nums[0], nums[1])
            return "Random number [\(lo)-\(hi)]: \(Int.random(in: lo...hi))"
        }

        return "Random number [1-100]: \(Int.random(in: 1...100))"
    }

    private func extractNumber(from text: String) -> Int? {
        text.components(separatedBy: CharacterSet.decimalDigits.inverted).compactMap { Int($0) }.first
    }
}

// MARK: - Device Info Tool

struct BuiltinDeviceInfo {
    func info() -> String {
        let ram = ProcessInfo.processInfo.physicalMemory / 1_073_741_824
        let cores = ProcessInfo.processInfo.processorCount
        let os = ProcessInfo.processInfo.operatingSystemVersionString
        return "RAM: \(ram)GB, CPU cores: \(cores), OS: \(os)"
    }
}
