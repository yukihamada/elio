import SwiftUI

/// View for managing prompt templates
struct PromptTemplatesView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var templateManager = PromptTemplateManager.shared
    @State private var showingAddTemplate = false
    @State private var editingTemplate: PromptTemplate?

    let onSelectTemplate: (PromptTemplate) -> Void

    var body: some View {
        NavigationStack {
            Group {
                if templateManager.templates.isEmpty {
                    emptyState
                } else {
                    templateList
                }
            }
            .navigationTitle(String(localized: "templates.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(String(localized: "common.done")) { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: { showingAddTemplate = true }) {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAddTemplate) {
                TemplateEditView(
                    template: nil,
                    onSave: { template in
                        templateManager.addTemplate(template)
                    }
                )
            }
            .sheet(item: $editingTemplate) { template in
                TemplateEditView(
                    template: template,
                    onSave: { updated in
                        templateManager.updateTemplate(updated)
                    }
                )
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "text.badge.plus")
                .font(.system(size: 50))
                .foregroundStyle(.secondary)

            Text(String(localized: "templates.empty"))
                .font(.headline)
                .foregroundStyle(.secondary)

            Button(action: { showingAddTemplate = true }) {
                Label(String(localized: "templates.add"), systemImage: "plus.circle.fill")
                    .font(.system(size: 16, weight: .semibold))
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var templateList: some View {
        List {
            ForEach(templateManager.templates) { template in
                Button(action: {
                    templateManager.recordUsage(of: template)
                    onSelectTemplate(template)
                    dismiss()
                }) {
                    HStack(spacing: 12) {
                        Image(systemName: template.icon)
                            .font(.system(size: 20))
                            .foregroundStyle(.blue)
                            .frame(width: 32)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(template.name)
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(.primary)

                            Text(template.content)
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 4)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        templateManager.deleteTemplate(template)
                    } label: {
                        Label(String(localized: "common.delete"), systemImage: "trash")
                    }

                    Button {
                        editingTemplate = template
                    } label: {
                        Label(String(localized: "common.edit"), systemImage: "pencil")
                    }
                    .tint(.orange)
                }
            }
        }
        .listStyle(.plain)
    }
}

/// View for editing or creating a template
struct TemplateEditView: View {
    @Environment(\.dismiss) private var dismiss
    let template: PromptTemplate?
    let onSave: (PromptTemplate) -> Void

    @State private var name: String = ""
    @State private var content: String = ""
    @State private var selectedIcon: String = "text.bubble"

    private let iconOptions = [
        "text.bubble",
        "globe",
        "doc.text",
        "questionmark.circle",
        "chevron.left.forwardslash.chevron.right",
        "pencil",
        "lightbulb",
        "brain",
        "sparkles",
        "wand.and.stars",
        "book",
        "translate"
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text(String(localized: "template.name.header"))) {
                    TextField(String(localized: "template.name.placeholder"), text: $name)
                }

                Section(header: Text(String(localized: "template.content.header"))) {
                    TextEditor(text: $content)
                        .frame(minHeight: 100)
                }

                Section(header: Text(String(localized: "template.icon.header"))) {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 12) {
                        ForEach(iconOptions, id: \.self) { icon in
                            Button(action: { selectedIcon = icon }) {
                                Image(systemName: icon)
                                    .font(.system(size: 20))
                                    .foregroundStyle(selectedIcon == icon ? .white : .blue)
                                    .frame(width: 40, height: 40)
                                    .background(
                                        selectedIcon == icon ? Color.blue : Color.blue.opacity(0.1)
                                    )
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
            .navigationTitle(template == nil ? String(localized: "template.add.title") : String(localized: "template.edit.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(String(localized: "common.cancel")) { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(String(localized: "common.save")) {
                        saveTemplate()
                    }
                    .fontWeight(.semibold)
                    .disabled(name.isEmpty || content.isEmpty)
                }
            }
            .onAppear {
                if let template = template {
                    name = template.name
                    content = template.content
                    selectedIcon = template.icon
                }
            }
        }
    }

    private func saveTemplate() {
        let newTemplate = PromptTemplate(
            id: template?.id ?? UUID(),
            name: name,
            content: content,
            icon: selectedIcon,
            createdAt: template?.createdAt ?? Date(),
            usedAt: template?.usedAt,
            useCount: template?.useCount ?? 0
        )
        onSave(newTemplate)
        dismiss()
    }
}

/// Compact template selector for quick access in chat
struct TemplateQuickSelect: View {
    @StateObject private var templateManager = PromptTemplateManager.shared
    let onSelectTemplate: (PromptTemplate) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(templateManager.templates.prefix(5)) { template in
                    Button(action: {
                        templateManager.recordUsage(of: template)
                        onSelectTemplate(template)
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: template.icon)
                                .font(.system(size: 12))
                            Text(template.name)
                                .font(.system(size: 13))
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(Capsule())
                    }
                    .foregroundStyle(.primary)
                }
            }
            .padding(.horizontal, 16)
        }
    }
}

#Preview {
    PromptTemplatesView(onSelectTemplate: { _ in })
}
