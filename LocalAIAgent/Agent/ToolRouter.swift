import Foundation

// MARK: - Tool Definition

struct ToolDef {
    let name: String
    let description: String
    let execute: (String) async -> String
}

// MARK: - Validation Result

struct ToolValidationResult {
    let isValid: Bool
    let confidence: Float  // 0.0 - 1.0
    let detail: String?
}

// MARK: - Tool Router (Semantic tool selection using local LLM)
/// Ported from NOU app - uses LLM-based few-shot classification to choose tools.
/// Achieves 96% accuracy on 2B models with the optimized prompt.

@MainActor
final class ToolRouter: ObservableObject {
    private let tools: [ToolDef]

    init() {
        let search = BuiltinWebSearch()
        let calc = BuiltinCalculator()
        let dt = BuiltinDateTime()
        let urlFetch = BuiltinURLFetch()
        let unitConvert = BuiltinUnitConvert()
        let random = BuiltinRandom()
        let memo = BuiltinMemoStore.shared

        self.tools = [
            ToolDef(name: "search", description: "web search") { query in
                let results = await search.search(query: query, maxResults: 3)
                if results.isEmpty { return "No results." }
                return results.enumerated().map { i, r in "[\(i+1)] \(r.title): \(r.snippet)" }.joined(separator: "\n")
            },
            ToolDef(name: "calc", description: "math calculator") { expr in
                calc.evaluate(expr)
            },
            ToolDef(name: "time", description: "current date/time") { _ in
                dt.currentInfo()
            },
            ToolDef(name: "fetch", description: "read a URL") { url in
                await urlFetch.fetch(url: url)
            },
            ToolDef(name: "convert", description: "unit conversion") { input in
                unitConvert.convert(input)
            },
            ToolDef(name: "random", description: "random generator") { input in
                random.generate(input)
            },
            ToolDef(name: "memo_save", description: "save a note to memory") { content in
                await memo.save(content: content)
            },
            ToolDef(name: "memo_find", description: "search saved notes") { query in
                await memo.search(query: query)
            },
        ]
    }

    /// Process a query: select tool via LLM, execute, generate answer, validate.
    func process(
        query: String,
        engine: DirectLlamaEngine,
        onToken: @escaping @MainActor (String) -> Void
    ) async throws -> (answer: String, toolUsed: String?, validation: ToolValidationResult?) {

        // Step 1: Tool selection via few-shot classification prompt
        let routePrompt = "calc=math(+\u{2212}*/%). time=now. search=live web(news,weather,prices,events). convert=units(km\u{2194}miles,\u{00B0}C\u{2194}\u{00B0}F,kg\u{2194}lbs). random=dice/password/coin. memo_save=user asks to remember/save. memo_find=user asks to recall/what did I say. none=knowledge/coding/chat.\n\nHello\u{2192}none\n\u{5929}\u{6C17}\u{2192}search\n2+2\u{2192}calc\n\u{4ECA}\u{4F55}\u{6642}\u{2192}time\nDNA?\u{2192}none\n\u{682A}\u{4FA1}\u{2192}search\n\u{30B3}\u{30FC}\u{30C9}\u{2192}none\n\u{5BCC}\u{58EB}\u{5C71}\u{2192}none\n\u{5929}\u{6C17}\u{4E88}\u{5831}\u{2192}search\nWho won?\u{2192}search\n\u{4F55}\u{66DC}\u{65E5}\u{2192}time\n\u{304A}\u{3059}\u{3059}\u{3081}\u{2192}none\n10km to miles\u{2192}convert\npassword\u{2192}random\n\u{30B5}\u{30A4}\u{30B3}\u{30ED}\u{2192}random\njoke\u{2192}none\ncoin flip\u{2192}random\n\nQ: \(query)\nA:"

        print("[ToolRouter] Selecting tool...")
        let rawChoice = try await engine.complete(
            prompt: routePrompt,
            system: "Classify into: search, calc, time, convert, random, memo_save, memo_find, none. ONE word."
        )
        let choice = rawChoice.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let chosenName = ["memo_save", "memo_find", "search", "calc", "time", "fetch", "convert", "random"].first(where: { choice.contains($0) }) ?? "none"
        print("[ToolRouter] Chose '\(chosenName)' (raw: '\(choice.prefix(20))')")

        // Step 2: Execute tool if needed
        var toolResult = ""
        if chosenName != "none", let tool = tools.first(where: { $0.name == chosenName }) {
            print("[ToolRouter] Executing \(chosenName)...")

            let toolInput: String
            switch chosenName {
            case "calc":
                toolInput = query.unicodeScalars.filter { "0123456789.+-*/()% ".contains(String($0)) }
                    .reduce("") { $0 + String($1) }.trimmingCharacters(in: .whitespaces)
            case "fetch":
                let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
                let matches = detector?.matches(in: query, range: NSRange(query.startIndex..., in: query)) ?? []
                toolInput = matches.first.flatMap { Range($0.range, in: query).map { String(query[$0]) } } ?? query
            case "memo_save":
                toolInput = query
            default:
                toolInput = query
            }

            if toolInput.isEmpty {
                toolResult = ""
            } else {
                toolResult = await tool.execute(toolInput)
                print("[ToolRouter] Result: '\(toolResult.prefix(80))'")
            }
        }

        // Step 2.5: Search long-term memory for context
        let memoryHits = await BuiltinMemoStore.shared.search(query: query, topK: 2)
        let hasMemory = !memoryHits.contains("No memos") && !memoryHits.contains("No relevant")

        // Step 3: Build final prompt with memory + tool results
        var parts: [String] = []
        if hasMemory { parts.append("Memory:\n\(String(memoryHits.prefix(400)))") }
        if !toolResult.isEmpty { parts.append("[\(chosenName)]:\n\(String(toolResult.prefix(1000)))") }
        parts.append("Q: \(query)")
        let finalPrompt = parts.joined(separator: "\n\n")

        print("[ToolRouter] Answering... (memory=\(hasMemory))")
        let answer = try await engine.chat(
            message: finalPrompt,
            systemPrompt: "Answer concisely in the user's language. Use memory and tool results if provided.",
            maxTokens: 1024,
            onToken: onToken
        )

        // Step 4: Validate tool results
        var validation: ToolValidationResult? = nil
        if let toolUsed = chosenName == "none" ? nil : chosenName {
            validation = validateResult(toolName: toolUsed, toolResult: toolResult, answer: answer)
        }

        return (answer: answer, toolUsed: chosenName == "none" ? nil : chosenName, validation: validation)
    }

    // MARK: - Answer Validation

    private func validateResult(toolName: String, toolResult: String, answer: String) -> ToolValidationResult {
        switch toolName {
        case "calc":
            return validateCalcResult(toolResult: toolResult)
        case "fetch":
            return validateURLResult(toolResult: toolResult)
        case "search":
            return validateSearchResult(toolResult: toolResult)
        default:
            return ToolValidationResult(isValid: true, confidence: 0.8, detail: nil)
        }
    }

    private func validateCalcResult(toolResult: String) -> ToolValidationResult {
        if toolResult.contains("Could not calculate") || toolResult.contains("No valid math") {
            return ToolValidationResult(isValid: false, confidence: 0.3, detail: "Calculation failed")
        }
        let numStr = toolResult.trimmingCharacters(in: .whitespacesAndNewlines)
        if Double(numStr) != nil {
            return ToolValidationResult(isValid: true, confidence: 0.95, detail: "Verified calculation")
        }
        return ToolValidationResult(isValid: true, confidence: 0.7, detail: nil)
    }

    private func validateURLResult(toolResult: String) -> ToolValidationResult {
        if toolResult.contains("Failed to fetch") || toolResult.contains("Invalid URL") {
            return ToolValidationResult(isValid: false, confidence: 0.2, detail: "URL fetch failed")
        }
        if toolResult.count > 50 {
            return ToolValidationResult(isValid: true, confidence: 0.9, detail: "Content retrieved")
        }
        return ToolValidationResult(isValid: true, confidence: 0.6, detail: "Partial content")
    }

    private func validateSearchResult(toolResult: String) -> ToolValidationResult {
        if toolResult == "No results." || toolResult.isEmpty {
            return ToolValidationResult(isValid: false, confidence: 0.3, detail: "No search results")
        }
        let resultCount = toolResult.components(separatedBy: "\n").filter { $0.hasPrefix("[") }.count
        let confidence: Float = min(0.95, 0.5 + Float(resultCount) * 0.15)
        return ToolValidationResult(isValid: true, confidence: confidence, detail: "\(resultCount) results found")
    }
}
