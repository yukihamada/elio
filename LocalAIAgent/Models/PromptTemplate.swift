import Foundation

/// A saved prompt template for quick reuse
struct PromptTemplate: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var content: String
    var icon: String
    let createdAt: Date
    var usedAt: Date?
    var useCount: Int

    init(
        id: UUID = UUID(),
        name: String,
        content: String,
        icon: String = "text.bubble",
        createdAt: Date = Date(),
        usedAt: Date? = nil,
        useCount: Int = 0
    ) {
        self.id = id
        self.name = name
        self.content = content
        self.icon = icon
        self.createdAt = createdAt
        self.usedAt = usedAt
        self.useCount = useCount
    }

    /// Default templates for new users
    static var defaults: [PromptTemplate] {
        [
            PromptTemplate(
                name: String(localized: "template.translate.name"),
                content: String(localized: "template.translate.content"),
                icon: "globe"
            ),
            PromptTemplate(
                name: String(localized: "template.summarize.name"),
                content: String(localized: "template.summarize.content"),
                icon: "doc.text"
            ),
            PromptTemplate(
                name: String(localized: "template.explain.name"),
                content: String(localized: "template.explain.content"),
                icon: "questionmark.circle"
            ),
            PromptTemplate(
                name: String(localized: "template.code.name"),
                content: String(localized: "template.code.content"),
                icon: "chevron.left.forwardslash.chevron.right"
            )
        ]
    }
}
