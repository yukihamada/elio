import Foundation

// Translation feature requires iOS 18.0+ and a UI-based approach using .translationPresentation()
// This server is disabled for now as the Translation framework doesn't support programmatic translation
// in a simple MCP server context. To enable translation, consider:
// 1. Using a SwiftUI view modifier approach
// 2. Implementing a custom translation UI
// 3. Using a third-party translation API

#if false
import Translation

/// MCP Server for Translation - Translate text using Apple Translation API (iOS 18.0+, no API key required)
/// Note: Currently disabled - Translation framework requires UI-based implementation
@available(iOS 18.0, *)
final class TranslationServer: MCPServer {
    let id = "translation"
    let name = "翻訳"
    let serverDescription = "テキストを翻訳します（Apple Translation使用）"
    let icon = "globe"

    func listTools() -> [MCPTool] {
        []
    }

    func listPrompts() -> [MCPPrompt] {
        []
    }

    func getPrompt(name: String, arguments: [String: String]) -> MCPPromptResult? {
        nil
    }

    func callTool(name: String, arguments: [String: JSONValue]) async throws -> MCPResult {
        throw MCPClientError.toolNotFound(name)
    }
}
#endif
