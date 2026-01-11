import Foundation
import UIKit
import PDFKit

/// Exports conversations to various formats
actor ConversationExporter {
    static let shared = ConversationExporter()

    enum ExportFormat {
        case markdown
        case pdf
        case plainText
        case logs
    }

    struct ExportResult {
        let url: URL
        let format: ExportFormat
        let filename: String
    }

    /// Export a conversation to the specified format
    func export(_ conversation: Conversation, format: ExportFormat) async throws -> ExportResult {
        switch format {
        case .markdown:
            return try await exportToMarkdown(conversation)
        case .pdf:
            return try await exportToPDF(conversation)
        case .plainText:
            return try await exportToPlainText(conversation)
        case .logs:
            // Logs don't use conversation - use exportSessionLogs() directly
            return try await exportSessionLogs()
        }
    }

    // MARK: - Markdown Export

    private func exportToMarkdown(_ conversation: Conversation) async throws -> ExportResult {
        var markdown = "# \(conversation.title)\n\n"
        markdown += "_\(String(localized: "export.created")): \(formatDate(conversation.createdAt))_\n\n"
        markdown += "---\n\n"

        for message in conversation.messages {
            let roleLabel = message.role == .user
                ? String(localized: "conversations.user")
                : String(localized: "conversations.assistant")

            markdown += "### \(roleLabel)\n\n"

            if message.imageData != nil {
                markdown += "_[\(String(localized: "export.image.attached"))]_\n\n"
            }

            markdown += "\(message.content)\n\n"

            if let thinking = message.thinkingContent, !thinking.isEmpty {
                markdown += "<details>\n<summary>\(String(localized: "onboarding.feature.thinking"))</summary>\n\n"
                markdown += "\(thinking)\n\n"
                markdown += "</details>\n\n"
            }

            markdown += "---\n\n"
        }

        markdown += "_\(String(localized: "export.generated.by")) Elio_\n"

        let filename = sanitizeFilename(conversation.title) + ".md"
        let url = try saveToFile(content: markdown, filename: filename)

        return ExportResult(url: url, format: .markdown, filename: filename)
    }

    // MARK: - PDF Export

    private func exportToPDF(_ conversation: Conversation) async throws -> ExportResult {
        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792) // US Letter size
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)

        let data = renderer.pdfData { context in
            var yPosition: CGFloat = 50
            let leftMargin: CGFloat = 50
            let rightMargin: CGFloat = 50
            let contentWidth = pageRect.width - leftMargin - rightMargin

            func startNewPage() {
                context.beginPage()
                yPosition = 50
            }

            func checkPageBreak(height: CGFloat) {
                if yPosition + height > pageRect.height - 50 {
                    startNewPage()
                }
            }

            // Title page
            startNewPage()

            let titleFont = UIFont.systemFont(ofSize: 24, weight: .bold)
            let titleRect = CGRect(x: leftMargin, y: yPosition, width: contentWidth, height: 40)
            conversation.title.draw(in: titleRect, withAttributes: [
                .font: titleFont,
                .foregroundColor: UIColor.label
            ])
            yPosition += 50

            let dateFont = UIFont.systemFont(ofSize: 12, weight: .regular)
            let dateText = "\(String(localized: "export.created")): \(formatDate(conversation.createdAt))"
            dateText.draw(at: CGPoint(x: leftMargin, y: yPosition), withAttributes: [
                .font: dateFont,
                .foregroundColor: UIColor.secondaryLabel
            ])
            yPosition += 40

            // Messages
            for message in conversation.messages {
                let roleLabel = message.role == .user
                    ? String(localized: "conversations.user")
                    : String(localized: "conversations.assistant")

                // Role header
                checkPageBreak(height: 60)
                let roleFont = UIFont.systemFont(ofSize: 14, weight: .semibold)
                let roleColor = message.role == .user ? UIColor.systemBlue : UIColor.systemGreen
                roleLabel.draw(at: CGPoint(x: leftMargin, y: yPosition), withAttributes: [
                    .font: roleFont,
                    .foregroundColor: roleColor
                ])
                yPosition += 25

                // Content
                let contentFont = UIFont.systemFont(ofSize: 12, weight: .regular)
                let paragraphStyle = NSMutableParagraphStyle()
                paragraphStyle.lineSpacing = 4

                let contentAttributes: [NSAttributedString.Key: Any] = [
                    .font: contentFont,
                    .foregroundColor: UIColor.label,
                    .paragraphStyle: paragraphStyle
                ]

                // Split content by lines for proper page breaks
                let lines = message.content.components(separatedBy: "\n")
                for line in lines {
                    let lineSize = line.boundingRect(
                        with: CGSize(width: contentWidth, height: .greatestFiniteMagnitude),
                        options: [.usesLineFragmentOrigin, .usesFontLeading],
                        attributes: contentAttributes,
                        context: nil
                    )

                    checkPageBreak(height: lineSize.height + 10)

                    line.draw(in: CGRect(x: leftMargin, y: yPosition, width: contentWidth, height: lineSize.height + 10),
                              withAttributes: contentAttributes)
                    yPosition += lineSize.height + 5
                }

                yPosition += 20

                // Separator
                checkPageBreak(height: 20)
                let separatorPath = UIBezierPath()
                separatorPath.move(to: CGPoint(x: leftMargin, y: yPosition))
                separatorPath.addLine(to: CGPoint(x: pageRect.width - rightMargin, y: yPosition))
                UIColor.separator.setStroke()
                separatorPath.stroke()
                yPosition += 20
            }

            // Footer
            checkPageBreak(height: 30)
            let footerText = "\(String(localized: "export.generated.by")) Elio"
            let footerFont = UIFont.italicSystemFont(ofSize: 10)
            footerText.draw(at: CGPoint(x: leftMargin, y: yPosition), withAttributes: [
                .font: footerFont,
                .foregroundColor: UIColor.tertiaryLabel
            ])
        }

        let filename = sanitizeFilename(conversation.title) + ".pdf"
        let url = try saveToFile(data: data, filename: filename)

        return ExportResult(url: url, format: .pdf, filename: filename)
    }

    // MARK: - Plain Text Export

    private func exportToPlainText(_ conversation: Conversation) async throws -> ExportResult {
        var text = "\(conversation.title)\n"
        text += String(repeating: "=", count: conversation.title.count) + "\n\n"
        text += "\(String(localized: "export.created")): \(formatDate(conversation.createdAt))\n\n"
        text += String(repeating: "-", count: 40) + "\n\n"

        for message in conversation.messages {
            let roleLabel = message.role == .user
                ? String(localized: "conversations.user")
                : String(localized: "conversations.assistant")

            text += "[\(roleLabel)]\n"
            text += "\(message.content)\n\n"

            if let thinking = message.thinkingContent, !thinking.isEmpty {
                text += "(\(String(localized: "onboarding.feature.thinking")))\n"
                text += "\(thinking)\n\n"
            }

            text += String(repeating: "-", count: 40) + "\n\n"
        }

        text += "\(String(localized: "export.generated.by")) Elio\n"

        let filename = sanitizeFilename(conversation.title) + ".txt"
        let url = try saveToFile(content: text, filename: filename)

        return ExportResult(url: url, format: .plainText, filename: filename)
    }

    // MARK: - Session Logs Export

    /// Export session logs to a text file
    func exportSessionLogs() async throws -> ExportResult {
        let logText = SessionLogger.shared.exportAsText()

        var content = "Elio Session Logs\n"
        content += String(repeating: "=", count: 20) + "\n\n"
        content += "Exported: \(formatDate(Date()))\n"
        content += "Log entries: \(SessionLogger.shared.count)\n\n"
        content += String(repeating: "-", count: 40) + "\n\n"

        if logText.isEmpty {
            content += "(No log entries recorded)\n"
        } else {
            content += logText
        }

        content += "\n\n" + String(repeating: "-", count: 40) + "\n"
        content += "End of log export\n"

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd_HHmmss"
        let timestamp = dateFormatter.string(from: Date())
        let filename = "elio_logs_\(timestamp).txt"

        let url = try saveToFile(content: content, filename: filename)
        return ExportResult(url: url, format: .logs, filename: filename)
    }

    // MARK: - Helpers

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func sanitizeFilename(_ name: String) -> String {
        let invalidChars = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        return name.components(separatedBy: invalidChars).joined(separator: "_")
    }

    private func saveToFile(content: String, filename: String) throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent(filename)
        try content.write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
    }

    private func saveToFile(data: Data, filename: String) throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent(filename)
        try data.write(to: fileURL)
        return fileURL
    }
}
