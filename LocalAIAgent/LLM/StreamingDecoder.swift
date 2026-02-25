import Foundation

/// StreamingDecoder: converts a stream of token strings into valid UTF-8 characters.
/// Optimized to minimize String allocations by working with byte buffers directly.
actor StreamingDecoder {
    private var byteBuffer: [UInt8] = []
    private var isDecoding = false
    private var continuation: AsyncStream<String>.Continuation?

    func startDecoding() -> AsyncStream<String> {
        byteBuffer.reserveCapacity(64)
        return AsyncStream { continuation in
            self.continuation = continuation

            continuation.onTermination = { @Sendable _ in
                Task {
                    await self.stopDecoding()
                }
            }
        }
    }

    func decode(token: String) {
        // Append bytes directly instead of String concatenation
        byteBuffer.append(contentsOf: token.utf8)

        guard let continuation = continuation else { return }

        // Find the longest valid UTF-8 prefix in the byte buffer
        let validEnd = findValidUTF8End(byteBuffer)

        if validEnd > 0 {
            let validBytes = Array(byteBuffer.prefix(validEnd))
            if let output = String(bytes: validBytes, encoding: .utf8), !output.isEmpty {
                byteBuffer.removeFirst(validEnd)
                continuation.yield(output)
            }
        }
    }

    func finishDecoding() {
        if let continuation = continuation {
            if !byteBuffer.isEmpty {
                if let remaining = String(bytes: byteBuffer, encoding: .utf8), !remaining.isEmpty {
                    continuation.yield(remaining)
                }
                byteBuffer.removeAll(keepingCapacity: true)
            }
            continuation.finish()
        }
        isDecoding = false
        self.continuation = nil
    }

    func stopDecoding() {
        continuation?.finish()
        isDecoding = false
        byteBuffer.removeAll(keepingCapacity: true)
        self.continuation = nil
    }

    /// Find the end index of the longest valid UTF-8 sequence in the byte buffer.
    /// Handles incomplete multi-byte sequences at the end by excluding them.
    private func findValidUTF8End(_ bytes: [UInt8]) -> Int {
        guard !bytes.isEmpty else { return 0 }

        var validEnd = bytes.count

        // Check if the last few bytes form an incomplete multi-byte sequence
        for i in stride(from: bytes.count - 1, through: max(0, bytes.count - 4), by: -1) {
            let byte = bytes[i]
            if byte & 0x80 == 0 {
                // ASCII byte - valid boundary
                break
            } else if byte & 0xC0 == 0xC0 {
                // Start of multi-byte sequence
                let expectedLength: Int
                if byte & 0xF8 == 0xF0 { expectedLength = 4 }
                else if byte & 0xF0 == 0xE0 { expectedLength = 3 }
                else if byte & 0xE0 == 0xC0 { expectedLength = 2 }
                else { break }

                if bytes.count - i < expectedLength {
                    validEnd = i  // Incomplete sequence, exclude it
                }
                break
            }
        }

        return validEnd
    }
}

final class ResponseParser {
    enum ParsedContent {
        case text(String)
        case toolCall(name: String, arguments: [String: JSONValue])
        case thinking(String)
    }

    static func parse(_ response: String) -> [ParsedContent] {
        var results: [ParsedContent] = []
        var remaining = response

        while !remaining.isEmpty {
            // Try to find <|python_tag|> tokens first (Llama 3 tool call format)
            if let ptStart = remaining.range(of: "<|python_tag|>"),
               let ptEnd = remaining.range(of: "<|eom_id|>"),
               ptEnd.lowerBound >= ptStart.upperBound {
                let beforePT = String(remaining[..<ptStart.lowerBound])
                if !beforePT.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    results.append(.text(beforePT))
                }

                let ptContent = String(remaining[ptStart.upperBound..<ptEnd.lowerBound])
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                if let toolCall = parseToolCall(ptContent) {
                    results.append(toolCall)
                }

                remaining = String(remaining[ptEnd.upperBound...])
            }
            // Try to find <tool_call> tags (Hermes / Qwen3 format)
            else if let toolCallRange = remaining.range(of: "<tool_call>"),
               let toolCallEndRange = remaining.range(of: "</tool_call>") {
                let beforeToolCall = String(remaining[..<toolCallRange.lowerBound])
                if !beforeToolCall.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    results.append(.text(beforeToolCall))
                }

                let toolCallContent = String(remaining[toolCallRange.upperBound..<toolCallEndRange.lowerBound])
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                if let toolCall = parseToolCall(toolCallContent) {
                    results.append(toolCall)
                }

                remaining = String(remaining[toolCallEndRange.upperBound...])
            }
            // Process thinking tags BEFORE bare JSON (thinking content comes first in model output)
            else if let (thinkStart, thinkEnd, beforeThink) = findThinkingTags(in: remaining) {
                if !beforeThink.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    results.append(.text(beforeThink))
                }

                let thinkingContent = String(remaining[thinkStart.upperBound..<thinkEnd.lowerBound])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                results.append(.thinking(thinkingContent))

                remaining = String(remaining[thinkEnd.upperBound...])
            }
            // Fallback: Try to find bare JSON tool calls (for smaller models that don't follow exact format)
            else if let (toolCall, beforeJson, afterJson) = findBareJsonToolCall(in: remaining) {
                if !beforeJson.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    results.append(.text(beforeJson))
                }
                results.append(toolCall)
                remaining = afterJson
            } else {
                results.append(.text(remaining))
                remaining = ""
            }
        }

        return results
    }

    /// Find bare JSON tool call (without <tool_call> tags) - fallback for smaller models
    /// Looks for patterns like: {"name": "tool_name", "arguments": {...}}
    private static func findBareJsonToolCall(in text: String) -> (toolCall: ParsedContent, before: String, after: String)? {
        // Look for JSON that contains "name" and "arguments" - must be a tool call
        // Find the opening brace that starts a potential tool call JSON
        guard let nameMatch = text.range(of: #""name"\s*:"#, options: .regularExpression) else {
            return nil
        }

        // Find the opening brace before "name"
        let beforeName = text[..<nameMatch.lowerBound]
        guard let openBraceIndex = beforeName.lastIndex(of: "{") else {
            return nil
        }

        // Now find the matching closing brace
        var braceCount = 0
        var closeBraceIndex: String.Index?
        var index = openBraceIndex

        while index < text.endIndex {
            let char = text[index]
            if char == "{" {
                braceCount += 1
            } else if char == "}" {
                braceCount -= 1
                if braceCount == 0 {
                    closeBraceIndex = index
                    break
                }
            }
            index = text.index(after: index)
        }

        guard let closeIndex = closeBraceIndex else {
            return nil
        }

        let jsonRange = openBraceIndex...closeIndex
        let jsonString = String(text[jsonRange])
        let before = String(text[..<openBraceIndex])
        let after = String(text[text.index(after: closeIndex)...])

        // Verify it's actually a tool call JSON (has "name" and "arguments")
        guard jsonString.contains("\"arguments\"") else {
            return nil
        }

        // Try to parse it as a tool call
        guard let toolCall = parseToolCall(jsonString) else {
            return nil
        }

        return (toolCall, before, after)
    }

    /// Find thinking tags - supports both <think> and <thinking> formats
    /// Also handles cases where <think> was already in the prompt (only </think> in response)
    private static func findThinkingTags(in text: String) -> (start: Range<String.Index>, end: Range<String.Index>, before: String)? {
        // Try <think> first (more common with Qwen models)
        if let thinkRange = text.range(of: "<think>"),
           let thinkEndRange = text.range(of: "</think>") {
            let before = String(text[..<thinkRange.lowerBound])
            return (thinkRange, thinkEndRange, before)
        }

        // Try <thinking> as fallback
        if let thinkingRange = text.range(of: "<thinking>"),
           let thinkingEndRange = text.range(of: "</thinking>") {
            let before = String(text[..<thinkingRange.lowerBound])
            return (thinkingRange, thinkingEndRange, before)
        }

        // Handle case where <think> was in the prompt, so only </think> is in response
        // Everything before </think> is thinking content
        if let thinkEndRange = text.range(of: "</think>") {
            // Create a synthetic start range at the beginning
            let syntheticStart = text.startIndex..<text.startIndex
            return (syntheticStart, thinkEndRange, "")
        }

        // Same for </thinking>
        if let thinkingEndRange = text.range(of: "</thinking>") {
            let syntheticStart = text.startIndex..<text.startIndex
            return (syntheticStart, thinkingEndRange, "")
        }

        return nil
    }

    private static func parseToolCall(_ content: String) -> ParsedContent? {
        guard let data = content.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let name = json["name"] as? String else {
            return nil
        }

        var arguments: [String: JSONValue] = [:]

        if let args = json["arguments"] as? [String: Any] {
            for (key, value) in args {
                arguments[key] = convertToJSONValue(value)
            }
        }

        return .toolCall(name: name, arguments: arguments)
    }

    private static func convertToJSONValue(_ value: Any) -> JSONValue {
        switch value {
        case let string as String:
            return .string(string)
        case let int as Int:
            return .int(int)
        case let double as Double:
            return .double(double)
        case let bool as Bool:
            return .bool(bool)
        case let array as [Any]:
            return .array(array.map { convertToJSONValue($0) })
        case let dict as [String: Any]:
            return .object(dict.mapValues { convertToJSONValue($0) })
        default:
            return .null
        }
    }
}
