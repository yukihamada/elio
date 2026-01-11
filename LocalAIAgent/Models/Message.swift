import Foundation
import UIKit

struct Message: Identifiable, Codable, Equatable {
    let id: UUID
    let role: Role
    let content: String
    let timestamp: Date
    var toolCalls: [ToolCall]?
    var toolResults: [ToolResult]?
    var thinkingContent: String?
    var imageData: Data?  // Store image as JPEG data
    var feedbackRating: FeedbackRating?  // Good/Bad feedback state

    enum Role: String, Codable {
        case user
        case assistant
        case system
        case tool
    }

    enum FeedbackRating: String, Codable {
        case good
        case bad
    }

    init(
        id: UUID = UUID(),
        role: Role,
        content: String,
        timestamp: Date = Date(),
        toolCalls: [ToolCall]? = nil,
        toolResults: [ToolResult]? = nil,
        thinkingContent: String? = nil,
        imageData: Data? = nil,
        feedbackRating: FeedbackRating? = nil
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.toolCalls = toolCalls
        self.toolResults = toolResults
        self.thinkingContent = thinkingContent
        self.imageData = imageData
        self.feedbackRating = feedbackRating
    }

    /// Get UIImage from stored data
    var image: UIImage? {
        guard let data = imageData else { return nil }
        return UIImage(data: data)
    }

    /// Check if message has an image attachment
    var hasImage: Bool {
        imageData != nil
    }

    /// Parse raw response to extract thinking content and main content
    static func parseThinkingContent(_ rawContent: String) -> (thinking: String?, content: String) {
        // Pattern: <think>...</think> or </think> at the end
        let thinkPattern = #"<think>([\s\S]*?)</think>"#

        guard let regex = try? NSRegularExpression(pattern: thinkPattern, options: []) else {
            return (nil, rawContent)
        }

        let range = NSRange(rawContent.startIndex..., in: rawContent)
        var thinkingParts: [String] = []
        var cleanContent = rawContent

        // Find all thinking blocks
        let matches = regex.matches(in: rawContent, options: [], range: range)
        for match in matches.reversed() {
            if let thinkRange = Range(match.range(at: 1), in: rawContent) {
                thinkingParts.insert(String(rawContent[thinkRange]).trimmingCharacters(in: .whitespacesAndNewlines), at: 0)
            }
            if let fullRange = Range(match.range, in: cleanContent) {
                cleanContent.removeSubrange(fullRange)
            }
        }

        let thinking = thinkingParts.isEmpty ? nil : thinkingParts.joined(separator: "\n\n")
        let finalContent = cleanContent.trimmingCharacters(in: .whitespacesAndNewlines)

        return (thinking, finalContent)
    }
}

struct ToolCall: Identifiable, Codable, Equatable {
    let id: UUID
    let name: String
    let arguments: [String: JSONValue]

    init(id: UUID = UUID(), name: String, arguments: [String: JSONValue]) {
        self.id = id
        self.name = name
        self.arguments = arguments
    }
}

struct ToolResult: Identifiable, Codable, Equatable {
    let id: UUID
    let toolCallId: UUID
    let content: String
    let isError: Bool

    init(id: UUID = UUID(), toolCallId: UUID, content: String, isError: Bool = false) {
        self.id = id
        self.toolCallId = toolCallId
        self.content = content
        self.isError = isError
    }
}

enum JSONValue: Codable, Equatable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case array([JSONValue])
    case object([String: JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self = .null
        } else if let bool = try? container.decode(Bool.self) {
            self = .bool(bool)
        } else if let int = try? container.decode(Int.self) {
            self = .int(int)
        } else if let double = try? container.decode(Double.self) {
            self = .double(double)
        } else if let string = try? container.decode(String.self) {
            self = .string(string)
        } else if let array = try? container.decode([JSONValue].self) {
            self = .array(array)
        } else if let object = try? container.decode([String: JSONValue].self) {
            self = .object(object)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid JSON value")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch self {
        case .string(let value): try container.encode(value)
        case .int(let value): try container.encode(value)
        case .double(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }

    var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    var intValue: Int? {
        if case .int(let value) = self { return value }
        return nil
    }

    var boolValue: Bool? {
        if case .bool(let value) = self { return value }
        return nil
    }
}
