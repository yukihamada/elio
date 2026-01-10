import Foundation

struct ToolParser {
    struct ParsedToolCall {
        let name: String
        let arguments: [String: JSONValue]
        let rawJSON: String
    }

    static func extractToolCalls(from text: String) -> [ParsedToolCall] {
        var results: [ParsedToolCall] = []
        var remaining = text

        while let startRange = remaining.range(of: "<tool_call>"),
              let endRange = remaining.range(of: "</tool_call>") {
            let jsonContent = String(remaining[startRange.upperBound..<endRange.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)

            if let toolCall = parseJSON(jsonContent) {
                results.append(toolCall)
            }

            remaining = String(remaining[endRange.upperBound...])
        }

        return results
    }

    static func parseJSON(_ json: String) -> ParsedToolCall? {
        guard let data = json.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let name = dict["name"] as? String else {
            return nil
        }

        var arguments: [String: JSONValue] = [:]

        if let args = dict["arguments"] as? [String: Any] {
            for (key, value) in args {
                arguments[key] = convertToJSONValue(value)
            }
        }

        return ParsedToolCall(name: name, arguments: arguments, rawJSON: json)
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
        case is NSNull:
            return .null
        default:
            if let number = value as? NSNumber {
                if CFGetTypeID(number) == CFBooleanGetTypeID() {
                    return .bool(number.boolValue)
                } else if floor(number.doubleValue) == number.doubleValue {
                    return .int(number.intValue)
                } else {
                    return .double(number.doubleValue)
                }
            }
            return .null
        }
    }

    static func extractTextBeforeToolCall(from text: String) -> String {
        if let range = text.range(of: "<tool_call>") {
            return String(text[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return text
    }

    static func extractTextAfterToolResult(from text: String) -> String {
        if let range = text.range(of: "</tool_call>") {
            return String(text[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return ""
    }

    static func hasToolCall(in text: String) -> Bool {
        return text.contains("<tool_call>") && text.contains("</tool_call>")
    }

    static func hasIncompleteToolCall(in text: String) -> Bool {
        let hasStart = text.contains("<tool_call>")
        let hasEnd = text.contains("</tool_call>")
        return hasStart && !hasEnd
    }
}

extension ToolParser {
    static func formatToolCallForDisplay(_ toolCall: ParsedToolCall) -> String {
        var display = "🔧 ツール: \(toolCall.name)\n"

        if !toolCall.arguments.isEmpty {
            display += "引数:\n"
            for (key, value) in toolCall.arguments {
                display += "  • \(key): \(formatJSONValue(value))\n"
            }
        }

        return display
    }

    private static func formatJSONValue(_ value: JSONValue) -> String {
        switch value {
        case .string(let s): return "\"\(s)\""
        case .int(let i): return "\(i)"
        case .double(let d): return "\(d)"
        case .bool(let b): return b ? "true" : "false"
        case .null: return "null"
        case .array(let arr):
            return "[\(arr.map { formatJSONValue($0) }.joined(separator: ", "))]"
        case .object(let obj):
            return "{\(obj.map { "\($0.key): \(formatJSONValue($0.value))" }.joined(separator: ", "))}"
        }
    }
}
