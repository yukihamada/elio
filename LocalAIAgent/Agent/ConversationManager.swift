import Foundation
import SwiftUI

@MainActor
final class ConversationManager: ObservableObject {
    @Published var conversations: [Conversation] = []
    @Published var currentConversation: Conversation?

    private let maxConversations = 100
    private let maxMessagesPerConversation = 200
    private let storageKey = "saved_conversations"

    init() {
        loadConversations()
    }

    func createNewConversation() -> Conversation {
        let conversation = Conversation()
        conversations.insert(conversation, at: 0)
        currentConversation = conversation
        saveConversations()
        return conversation
    }

    func selectConversation(_ conversation: Conversation) {
        currentConversation = conversation
    }

    func deleteConversation(_ conversation: Conversation) {
        conversations.removeAll { $0.id == conversation.id }

        if currentConversation?.id == conversation.id {
            currentConversation = conversations.first
        }

        saveConversations()
    }

    func deleteAllConversations() {
        conversations.removeAll()
        currentConversation = nil
        saveConversations()
    }

    func addMessage(_ message: Message, to conversation: inout Conversation) {
        conversation.messages.append(message)
        conversation.updatedAt = Date()

        if conversation.messages.count == 1 && message.role == .user {
            conversation.updateTitle()
        }

        if conversation.messages.count > maxMessagesPerConversation {
            let excess = conversation.messages.count - maxMessagesPerConversation
            conversation.messages.removeFirst(excess)
        }

        if let index = conversations.firstIndex(where: { $0.id == conversation.id }) {
            conversations[index] = conversation
        }

        currentConversation = conversation
        saveConversations()
    }

    func getRecentMessages(limit: Int = 20) -> [Message] {
        guard let conversation = currentConversation else { return [] }
        return Array(conversation.messages.suffix(limit))
    }

    func getContextMessages(maxTokens: Int = 4000) -> [Message] {
        guard let conversation = currentConversation else { return [] }

        var messages: [Message] = []
        var estimatedTokens = 0

        for message in conversation.messages.reversed() {
            let messageTokens = estimateTokenCount(message.content)

            if estimatedTokens + messageTokens > maxTokens {
                break
            }

            messages.insert(message, at: 0)
            estimatedTokens += messageTokens
        }

        return messages
    }

    private func estimateTokenCount(_ text: String) -> Int {
        return text.count / 3
    }

    private func saveConversations() {
        do {
            let data = try JSONEncoder().encode(conversations)
            UserDefaults.standard.set(data, forKey: storageKey)
        } catch {
            print("Failed to save conversations: \(error)")
        }
    }

    private func loadConversations() {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return }

        do {
            conversations = try JSONDecoder().decode([Conversation].self, from: data)

            if conversations.count > maxConversations {
                conversations = Array(conversations.prefix(maxConversations))
            }

            currentConversation = conversations.first
        } catch {
            print("Failed to load conversations: \(error)")
        }
    }

    func exportConversation(_ conversation: Conversation) -> String {
        var export = "# \(conversation.title)\n"
        export += "作成日: \(formatDate(conversation.createdAt))\n\n"

        for message in conversation.messages {
            let role = message.role == .user ? "ユーザー" : "アシスタント"
            export += "## \(role)\n"
            export += "\(message.content)\n\n"

            if let toolCalls = message.toolCalls {
                for toolCall in toolCalls {
                    export += "> ツール実行: \(toolCall.name)\n"
                }
            }
        }

        return export
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateStyle = .long
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

extension ConversationManager {
    func searchConversations(query: String) -> [Conversation] {
        guard !query.isEmpty else { return conversations }

        return conversations.filter { conversation in
            if conversation.title.localizedCaseInsensitiveContains(query) {
                return true
            }

            return conversation.messages.contains { message in
                message.content.localizedCaseInsensitiveContains(query)
            }
        }
    }

    func getConversationsGroupedByDate() -> [(String, [Conversation])] {
        let calendar = Calendar.current
        let now = Date()

        var groups: [String: [Conversation]] = [
            "今日": [],
            "昨日": [],
            "過去7日間": [],
            "過去30日間": [],
            "それ以前": []
        ]

        for conversation in conversations {
            let days = calendar.dateComponents([.day], from: conversation.updatedAt, to: now).day ?? 0

            if days == 0 {
                groups["今日"]?.append(conversation)
            } else if days == 1 {
                groups["昨日"]?.append(conversation)
            } else if days <= 7 {
                groups["過去7日間"]?.append(conversation)
            } else if days <= 30 {
                groups["過去30日間"]?.append(conversation)
            } else {
                groups["それ以前"]?.append(conversation)
            }
        }

        let orderedKeys = ["今日", "昨日", "過去7日間", "過去30日間", "それ以前"]
        return orderedKeys.compactMap { key in
            guard let conversations = groups[key], !conversations.isEmpty else { return nil }
            return (key, conversations)
        }
    }
}
