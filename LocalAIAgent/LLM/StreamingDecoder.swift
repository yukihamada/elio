import Foundation

actor StreamingDecoder {
    private var buffer: String = ""
    private var isDecoding = false
    private var continuation: AsyncStream<String>.Continuation?

    func startDecoding() -> AsyncStream<String> {
        AsyncStream { continuation in
            self.continuation = continuation

            continuation.onTermination = { @Sendable _ in
                Task {
                    await self.stopDecoding()
                }
            }
        }
    }

    func decode(token: String) {
        buffer += token

        if let continuation = continuation {
            var outputBuffer = ""

            while let (char, remaining) = extractNextChar() {
                outputBuffer += char
                buffer = remaining
            }

            if !outputBuffer.isEmpty {
                continuation.yield(outputBuffer)
            }
        }
    }

    func finishDecoding() {
        if let continuation = continuation {
            if !buffer.isEmpty {
                continuation.yield(buffer)
                buffer = ""
            }
            continuation.finish()
        }
        isDecoding = false
        self.continuation = nil
    }

    func stopDecoding() {
        continuation?.finish()
        isDecoding = false
        buffer = ""
        self.continuation = nil
    }

    private func extractNextChar() -> (String, String)? {
        guard !buffer.isEmpty else { return nil }

        let data = buffer.data(using: .utf8)!
        var validEnd = 0

        for i in 1...min(4, data.count) {
            let prefix = data.prefix(i)
            if String(data: prefix, encoding: .utf8) != nil {
                validEnd = i
                break
            }
        }

        guard validEnd > 0 else { return nil }

        let charData = data.prefix(validEnd)
        guard let char = String(data: charData, encoding: .utf8) else { return nil }

        let remaining = String(buffer.dropFirst(validEnd))
        return (char, remaining)
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
            if let toolCallRange = remaining.range(of: "<tool_call>"),
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
            } else if let thinkingRange = remaining.range(of: "<thinking>"),
                      let thinkingEndRange = remaining.range(of: "</thinking>") {
                let beforeThinking = String(remaining[..<thinkingRange.lowerBound])
                if !beforeThinking.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    results.append(.text(beforeThinking))
                }

                let thinkingContent = String(remaining[thinkingRange.upperBound..<thinkingEndRange.lowerBound])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                results.append(.thinking(thinkingContent))

                remaining = String(remaining[thinkingEndRange.upperBound...])
            } else {
                results.append(.text(remaining))
                remaining = ""
            }
        }

        return results
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
