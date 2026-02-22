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
    var networkMetadata: NetworkMetadata?  // P2P mesh network metadata
    var providerInfo: ProviderInfo?  // API provider & model metadata

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
        feedbackRating: FeedbackRating? = nil,
        networkMetadata: NetworkMetadata? = nil,
        providerInfo: ProviderInfo? = nil
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
        self.networkMetadata = networkMetadata
        self.providerInfo = providerInfo
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
    /// Supports both <think> and <thinking> tag formats
    static func parseThinkingContent(_ rawContent: String) -> (thinking: String?, content: String) {
        var thinkingParts: [String] = []
        var cleanContent = rawContent

        // Process <think>...</think> tags
        let thinkPattern = #"<think>([\s\S]*?)</think>"#
        if let thinkRegex = try? NSRegularExpression(pattern: thinkPattern, options: []) {
            let range = NSRange(cleanContent.startIndex..., in: cleanContent)
            let matches = thinkRegex.matches(in: cleanContent, options: [], range: range)

            // Extract thinking content from all matches
            for match in matches {
                if let thinkRange = Range(match.range(at: 1), in: cleanContent) {
                    thinkingParts.append(String(cleanContent[thinkRange]).trimmingCharacters(in: .whitespacesAndNewlines))
                }
            }

            // Remove all <think>...</think> blocks using replacement
            cleanContent = thinkRegex.stringByReplacingMatches(
                in: cleanContent,
                options: [],
                range: NSRange(cleanContent.startIndex..., in: cleanContent),
                withTemplate: ""
            )
        }

        // Also process <thinking>...</thinking> tags
        let thinkingPattern = #"<thinking>([\s\S]*?)</thinking>"#
        if let thinkingRegex = try? NSRegularExpression(pattern: thinkingPattern, options: []) {
            let range = NSRange(cleanContent.startIndex..., in: cleanContent)
            let matches = thinkingRegex.matches(in: cleanContent, options: [], range: range)

            for match in matches {
                if let thinkRange = Range(match.range(at: 1), in: cleanContent) {
                    thinkingParts.append(String(cleanContent[thinkRange]).trimmingCharacters(in: .whitespacesAndNewlines))
                }
            }

            cleanContent = thinkingRegex.stringByReplacingMatches(
                in: cleanContent,
                options: [],
                range: NSRange(cleanContent.startIndex..., in: cleanContent),
                withTemplate: ""
            )
        }

        // Handle incomplete <think> tags (no closing tag)
        if cleanContent.contains("<think>") && !cleanContent.contains("</think>") {
            if let startRange = cleanContent.range(of: "<think>") {
                let remainingThinking = String(cleanContent[startRange.upperBound...])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !remainingThinking.isEmpty {
                    thinkingParts.append(remainingThinking)
                }
                cleanContent = String(cleanContent[..<startRange.lowerBound])
            }
        }

        // Handle incomplete <thinking> tags
        if cleanContent.contains("<thinking>") && !cleanContent.contains("</thinking>") {
            if let startRange = cleanContent.range(of: "<thinking>") {
                let remainingThinking = String(cleanContent[startRange.upperBound...])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !remainingThinking.isEmpty {
                    thinkingParts.append(remainingThinking)
                }
                cleanContent = String(cleanContent[..<startRange.lowerBound])
            }
        }

        // Handle case where <think> was in the prompt (only </think> in response)
        // Everything before </think> is thinking content
        if !cleanContent.contains("<think>") && cleanContent.contains("</think>") {
            if let endRange = cleanContent.range(of: "</think>") {
                let thinkingContent = String(cleanContent[..<endRange.lowerBound])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !thinkingContent.isEmpty {
                    thinkingParts.append(thinkingContent)
                }
                cleanContent = String(cleanContent[endRange.upperBound...])
            }
        }

        // Same for </thinking>
        if !cleanContent.contains("<thinking>") && cleanContent.contains("</thinking>") {
            if let endRange = cleanContent.range(of: "</thinking>") {
                let thinkingContent = String(cleanContent[..<endRange.lowerBound])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !thinkingContent.isEmpty {
                    thinkingParts.append(thinkingContent)
                }
                cleanContent = String(cleanContent[endRange.upperBound...])
            }
        }

        // Clean up any remaining raw tags that might have slipped through
        cleanContent = cleanContent
            .replacingOccurrences(of: "<think>", with: "")
            .replacingOccurrences(of: "</think>", with: "")
            .replacingOccurrences(of: "<thinking>", with: "")
            .replacingOccurrences(of: "</thinking>", with: "")

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

// MARK: - P2P Mesh Network Metadata

/// Network metadata for P2P mesh messages
struct NetworkMetadata: Codable, Equatable {
    let sourceDeviceId: String         // Origin device ID
    let networkType: NetworkType       // Type of network used
    let hopCount: Int                  // Number of relay hops
    let processingDeviceName: String?  // Device that performed inference
    let routePath: [String]            // Path of device IDs
    let latencyMs: Int?                // Round-trip latency in milliseconds

    init(
        sourceDeviceId: String,
        networkType: NetworkType,
        hopCount: Int = 0,
        processingDeviceName: String? = nil,
        routePath: [String] = [],
        latencyMs: Int? = nil
    ) {
        self.sourceDeviceId = sourceDeviceId
        self.networkType = networkType
        self.hopCount = hopCount
        self.processingDeviceName = processingDeviceName
        self.routePath = routePath
        self.latencyMs = latencyMs
    }
}

/// Type of network connection used for inference
enum NetworkType: String, Codable {
    case local       // Local LLM on device
    case chatweb     // ChatWeb API (cloud)
    case p2pDirect   // Direct P2P connection
    case p2pMesh     // P2P mesh relay
    case publicP2P   // Public P2P network
}

// MARK: - API Provider Metadata

/// Metadata about the AI provider used for a message
struct ProviderInfo: Codable, Equatable {
    let provider: String        // "openai", "anthropic", "google", "groq", etc.
    let model: String           // "gpt-4o", "claude-sonnet-4-5", etc.
    let usedOwnKey: Bool        // User's API key vs Elio tokens
    let tokenCost: Int          // Elio token cost
    let estimatedAPICost: Double?  // Estimated USD cost (input + output)

    init(
        provider: String,
        model: String,
        usedOwnKey: Bool,
        tokenCost: Int,
        estimatedAPICost: Double? = nil
    ) {
        self.provider = provider
        self.model = model
        self.usedOwnKey = usedOwnKey
        self.tokenCost = tokenCost
        self.estimatedAPICost = estimatedAPICost
    }
}
