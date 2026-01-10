import SwiftUI
import Combine

@MainActor
final class AppState: ObservableObject {
    @Published var isModelLoaded = false
    @Published var isLoading = false
    @Published var loadingProgress: Double = 0
    @Published var currentModelName: String?
    @Published var currentModelId: String?
    @Published var conversations: [Conversation] = []
    @Published var currentConversation: Conversation?
    @Published var enabledMCPServers: Set<String> = ["filesystem", "calendar", "reminders", "websearch"]
    @Published var errorMessage: String?
    @Published var isGenerating = false  // Track if currently generating response
    @Published var inferenceMode: InferenceMode = .auto

    private var llmEngine: CoreMLInference?
    private var llamaInference: LlamaInference?
    private var mcpClient: MCPClient?
    private var orchestrator: AgentOrchestrator?
    private let modelLoaderRef = ModelLoader()

    /// Check if the currently loaded model supports vision/image input
    var currentModelSupportsVision: Bool {
        guard let modelId = currentModelId else { return false }
        return modelLoaderRef.modelSupportsVision(modelId)
    }

    // Persist last used model and settings
    @AppStorage("lastUsedModel") private var lastUsedModel: String = ""
    @AppStorage("inferenceMode") private var storedInferenceMode: String = InferenceMode.auto.rawValue

    init() {
        // Restore saved inference mode
        self.inferenceMode = InferenceMode(rawValue: storedInferenceMode) ?? .auto
        setupMCPClient()
        // Load saved conversations
        loadConversations()
        // Auto-load last used model on startup
        loadLastUsedModelIfAvailable()
    }

    // MARK: - Persistence

    private var conversationsURL: URL {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documentsPath.appendingPathComponent("conversations.json")
    }

    private func loadConversations() {
        do {
            let data = try Data(contentsOf: conversationsURL)
            conversations = try JSONDecoder().decode([Conversation].self, from: data)
        } catch {
            // No saved conversations or error loading - start fresh
            conversations = []
        }
    }

    func saveConversations() {
        do {
            let data = try JSONEncoder().encode(conversations)
            try data.write(to: conversationsURL)
        } catch {
            print("Failed to save conversations: \(error)")
        }
    }

    private func loadLastUsedModelIfAvailable() {
        guard !lastUsedModel.isEmpty else { return }

        // Check if model is downloaded
        let modelLoader = ModelLoader()
        if modelLoader.isModelDownloaded(lastUsedModel) {
            Task {
                try? await loadModel(named: lastUsedModel)
            }
        }
    }

    private func setupMCPClient() {
        mcpClient = MCPClient()
        mcpClient?.registerBuiltInServers()
    }

    func loadModel(named modelName: String) async throws {
        // Unload any existing model first to free GPU memory
        if isModelLoaded {
            unloadModel()
            // Give the system a moment to reclaim memory
            try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
        }

        isLoading = true
        loadingProgress = 0
        errorMessage = nil

        defer { isLoading = false }

        do {
            let modelLoader = ModelLoader()

            // Track progress
            loadingProgress = 0.1

            llmEngine = try await modelLoader.loadModel(named: modelName)
            currentModelName = modelLoader.getModelInfo(modelName)?.name ?? modelName
            currentModelId = modelName
            isModelLoaded = true
            loadingProgress = 1.0

            // Save as last used model for next startup
            lastUsedModel = modelName

            if let llm = llmEngine, let mcp = mcpClient {
                orchestrator = AgentOrchestrator(llm: llm, mcpClient: mcp)
            }
        } catch {
            errorMessage = error.localizedDescription
            throw error
        }
    }

    func sendMessage(_ content: String) async -> String {
        guard isModelLoaded else {
            return String(localized: "chat.model.not.loaded.description")
        }

        if currentConversation == nil {
            currentConversation = Conversation()
            conversations.insert(currentConversation!, at: 0)
        }

        let userMessage = Message(role: .user, content: content)
        currentConversation?.messages.append(userMessage)
        currentConversation?.updatedAt = Date()

        // Update title based on first message
        if currentConversation?.messages.count == 1 {
            currentConversation?.title = String(content.prefix(30)) + (content.count > 30 ? "..." : "")
        }

        do {
            let response: String

            if let orchestrator = orchestrator {
                response = try await orchestrator.process(
                    message: content,
                    history: currentConversation?.messages ?? [],
                    enabledServers: enabledMCPServers
                )
            } else if let llm = llmEngine {
                // Direct LLM call with proper chat formatting including date/time context
                let systemPrompt = buildSystemPrompt()
                var generatedText = ""
                _ = try await llm.generateWithMessages(
                    messages: currentConversation?.messages ?? [userMessage],
                    systemPrompt: systemPrompt,
                    maxTokens: 512
                ) { token in
                    generatedText += token
                }
                response = generatedText
            } else {
                response = String(localized: "error.engine.not.initialized", defaultValue: "Engine not initialized")
            }

            // Parse thinking content from response
            let parsed = Message.parseThinkingContent(response)
            let assistantMessage = Message(
                role: .assistant,
                content: parsed.content.isEmpty ? response : parsed.content,
                thinkingContent: parsed.thinking
            )
            currentConversation?.messages.append(assistantMessage)
            currentConversation?.updatedAt = Date()

            return response
        } catch {
            let errorResponse = "エラーが発生しました: \(error.localizedDescription)"
            let assistantMessage = Message(role: .assistant, content: errorResponse)
            currentConversation?.messages.append(assistantMessage)
            return errorResponse
        }
    }

    private var isJapanese: Bool {
        Locale.current.language.languageCode?.identifier == "ja"
    }

    private func buildSystemPrompt() -> String {
        // Current date/time info
        let dateFormatter = DateFormatter()
        let currentDateTime: String

        if isJapanese {
            dateFormatter.locale = Locale(identifier: "ja_JP")
            dateFormatter.dateFormat = "yyyy年M月d日(EEEE) HH:mm"
            currentDateTime = dateFormatter.string(from: Date())
        } else {
            dateFormatter.locale = Locale(identifier: "en_US")
            dateFormatter.dateFormat = "EEEE, MMMM d, yyyy HH:mm"
            currentDateTime = dateFormatter.string(from: Date())
        }

        // Build context with date and past conversation titles
        var contextParts: [String] = []
        let recentConversations = conversations.prefix(5)

        if isJapanese {
            contextParts.append("現在: \(currentDateTime)")
            if !recentConversations.isEmpty {
                let titles = recentConversations.map { "・\($0.title)" }.joined(separator: "\n")
                contextParts.append("最近の会話:\n\(titles)")
            }
            let context = contextParts.joined(separator: "\n\n")

            return """
            # Elio について
            あなたは「Elio」（エリオ）です。プライバシーを最優先するローカルAIアシスタントとして、ユーザーのデバイス上で完全に動作します。
            - すべての処理はデバイス内で完結し、データは外部に送信されません
            - ユーザーのプライバシーと信頼を守ることが最も重要な使命です

            # ハルシネーション（誤情報）の防止
            正確性を最優先してください：
            - 確実に知っている情報のみを回答してください
            - 不確かな場合は「確かではありませんが」「私の知識では」と前置きしてください
            - 分からないことは正直に「分かりません」と伝えてください

            【現在の情報】
            \(context)
            """
        } else {
            contextParts.append("Current: \(currentDateTime)")
            if !recentConversations.isEmpty {
                let titles = recentConversations.map { "• \($0.title)" }.joined(separator: "\n")
                contextParts.append("Recent conversations:\n\(titles)")
            }
            let context = contextParts.joined(separator: "\n\n")

            return """
            # About Elio
            You are Elio, a privacy-first local AI assistant that runs entirely on the user's device.
            - All processing happens locally; no data is sent externally
            - Protecting user privacy and trust is your most important mission

            # Preventing Hallucinations
            Prioritize accuracy above all:
            - Only provide information you are certain about
            - If uncertain, preface with "I'm not entirely sure, but..." or "Based on my knowledge..."
            - Honestly say "I don't know" when you don't have reliable information

            [Current Information]
            \(context)
            """
        }
    }

    func sendMessageWithStreaming(_ content: String, onToken: @escaping (String) -> Void) async -> String {
        guard isModelLoaded else {
            let msg = String(localized: "chat.model.not.loaded.description")
            onToken(msg)
            return msg
        }

        // Set generating flag immediately
        isGenerating = true
        defer { isGenerating = false }

        if currentConversation == nil {
            currentConversation = Conversation()
            conversations.insert(currentConversation!, at: 0)
        }

        let userMessage = Message(role: .user, content: content)
        currentConversation?.messages.append(userMessage)
        currentConversation?.updatedAt = Date()

        // Update title based on first message
        if currentConversation?.messages.count == 1 {
            currentConversation?.title = String(content.prefix(30)) + (content.count > 30 ? "..." : "")
        }

        do {
            var fullResponse = ""

            if let llm = llmEngine {
                // Use proper chat formatting with system prompt including date/time
                let systemPrompt = buildSystemPrompt()
                _ = try await llm.generateWithMessages(
                    messages: currentConversation?.messages ?? [userMessage],
                    systemPrompt: systemPrompt,
                    maxTokens: 1024
                ) { token in
                    fullResponse += token
                    onToken(token)
                }
            }

            // Parse thinking content from response
            let parsed = Message.parseThinkingContent(fullResponse)
            let assistantMessage = Message(
                role: .assistant,
                content: parsed.content.isEmpty ? fullResponse : parsed.content,
                thinkingContent: parsed.thinking
            )
            currentConversation?.messages.append(assistantMessage)
            currentConversation?.updatedAt = Date()

            // Update conversation in array and save
            if let current = currentConversation,
               let index = conversations.firstIndex(where: { $0.id == current.id }) {
                conversations[index] = current
            }
            saveConversations()

            return fullResponse
        } catch {
            let errorResponse = "エラーが発生しました: \(error.localizedDescription)"
            onToken(errorResponse)
            let assistantMessage = Message(role: .assistant, content: errorResponse)
            currentConversation?.messages.append(assistantMessage)

            // Save even on error
            if let current = currentConversation,
               let index = conversations.firstIndex(where: { $0.id == current.id }) {
                conversations[index] = current
            }
            saveConversations()

            return errorResponse
        }
    }

    func newConversation() {
        // Save current conversation before starting new one
        if let current = currentConversation,
           let index = conversations.firstIndex(where: { $0.id == current.id }) {
            conversations[index] = current
            saveConversations()
        }
        currentConversation = nil
    }

    func deleteConversation(_ conversation: Conversation) {
        if let index = conversations.firstIndex(where: { $0.id == conversation.id }) {
            conversations.remove(at: index)
            if currentConversation?.id == conversation.id {
                currentConversation = nil
            }
            saveConversations()
        }
    }

    func toggleMCPServer(_ serverId: String) {
        if enabledMCPServers.contains(serverId) {
            enabledMCPServers.remove(serverId)
        } else {
            enabledMCPServers.insert(serverId)
        }
    }

    func unloadModel() {
        // Explicitly unload the CoreMLInference (which contains LlamaInference)
        llmEngine?.unload()
        llmEngine = nil
        // Also unload any standalone llamaInference if present
        llamaInference?.unload()
        llamaInference = nil
        orchestrator = nil
        isModelLoaded = false
        currentModelName = nil
        currentModelId = nil
        loadingProgress = 0
    }

    func setInferenceMode(_ mode: InferenceMode) {
        inferenceMode = mode
        storedInferenceMode = mode.rawValue
        // Update the engine if loaded
        llmEngine?.setInferenceMode(mode)
    }
}
