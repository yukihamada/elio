import SwiftUI
import MarkdownView

// MARK: - Chat Bubble Markdown Configuration

extension MarkdownView {
    /// Configure MarkdownView for chat bubble display
    func chatBubbleStyle(isUser: Bool) -> some View {
        self
            .font(.system(size: 13, design: .monospaced), for: .codeBlock)
    }
}

// MARK: - Markdown Content View

/// A wrapper view for displaying markdown content in chat bubbles
struct MarkdownContentView: View {
    let content: String
    let isUser: Bool

    var body: some View {
        MarkdownView(text: content)
            .chatBubbleStyle(isUser: isUser)
            .textSelection(.enabled)
    }
}

#Preview {
    ScrollView {
        VStack(alignment: .leading, spacing: 16) {
            MarkdownContentView(
                content: """
                # Header

                This is **bold** and *italic* text.

                ## Code Example

                ```swift
                func hello() {
                    print("Hello, World!")
                }
                ```

                ### List
                - Item 1
                - Item 2
                - Item 3

                > This is a quote
                """,
                isUser: false
            )
            .padding()
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .padding()
    }
}
