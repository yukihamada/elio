import Foundation
import SwiftUI

/// Manager for saving and loading prompt templates
@MainActor
class PromptTemplateManager: ObservableObject {
    static let shared = PromptTemplateManager()

    @Published var templates: [PromptTemplate] = []

    private let userDefaultsKey = "savedPromptTemplates"
    private let hasInitializedKey = "promptTemplatesInitialized"

    init() {
        loadTemplates()
    }

    /// Load templates from UserDefaults
    private func loadTemplates() {
        // Check if this is first launch
        let hasInitialized = UserDefaults.standard.bool(forKey: hasInitializedKey)

        if let data = UserDefaults.standard.data(forKey: userDefaultsKey),
           let decoded = try? JSONDecoder().decode([PromptTemplate].self, from: data) {
            templates = decoded
        } else if !hasInitialized {
            // First launch - add default templates
            templates = PromptTemplate.defaults
            saveTemplates()
            UserDefaults.standard.set(true, forKey: hasInitializedKey)
        }
    }

    /// Save templates to UserDefaults
    private func saveTemplates() {
        if let encoded = try? JSONEncoder().encode(templates) {
            UserDefaults.standard.set(encoded, forKey: userDefaultsKey)
        }
    }

    /// Add a new template
    func addTemplate(_ template: PromptTemplate) {
        templates.insert(template, at: 0)
        saveTemplates()
    }

    /// Update an existing template
    func updateTemplate(_ template: PromptTemplate) {
        if let index = templates.firstIndex(where: { $0.id == template.id }) {
            templates[index] = template
            saveTemplates()
        }
    }

    /// Delete a template
    func deleteTemplate(_ template: PromptTemplate) {
        templates.removeAll { $0.id == template.id }
        saveTemplates()
    }

    /// Delete templates at offsets
    func deleteTemplates(at offsets: IndexSet) {
        templates.remove(atOffsets: offsets)
        saveTemplates()
    }

    /// Record template usage
    func recordUsage(of template: PromptTemplate) {
        if let index = templates.firstIndex(where: { $0.id == template.id }) {
            templates[index].usedAt = Date()
            templates[index].useCount += 1
            saveTemplates()
        }
    }

    /// Get recently used templates (up to 3)
    var recentTemplates: [PromptTemplate] {
        templates
            .filter { $0.usedAt != nil }
            .sorted { ($0.usedAt ?? .distantPast) > ($1.usedAt ?? .distantPast) }
            .prefix(3)
            .map { $0 }
    }

    /// Get frequently used templates (up to 3)
    var frequentTemplates: [PromptTemplate] {
        templates
            .filter { $0.useCount > 0 }
            .sorted { $0.useCount > $1.useCount }
            .prefix(3)
            .map { $0 }
    }

    /// Reset to default templates
    func resetToDefaults() {
        templates = PromptTemplate.defaults
        saveTemplates()
    }
}
