import Foundation
import SwiftUI

struct Conversation: Identifiable, Codable {
    let id: UUID
    var title: String
    var messages: [Message]
    let createdAt: Date
    var updatedAt: Date

    /// Default title for new conversations (localized at runtime)
    static var defaultTitle: String {
        String(localized: "conversations.default.title")
    }

    init(
        id: UUID = UUID(),
        title: String? = nil,
        messages: [Message] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title ?? Self.defaultTitle
        self.messages = messages
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    mutating func updateTitle() {
        if let firstUserMessage = messages.first(where: { $0.role == .user }) {
            let content = firstUserMessage.content
            title = String(content.prefix(30)) + (content.count > 30 ? "..." : "")
        }
    }
}
