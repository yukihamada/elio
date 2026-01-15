import SwiftUI
import Combine

// MARK: - Character Extension for Japanese Detection

extension Character {
    /// Check if character is Japanese (Hiragana, Katakana, or CJK)
    var isJapanese: Bool {
        guard let scalar = unicodeScalars.first else { return false }
        let value = scalar.value

        // Hiragana: U+3040-U+309F
        if value >= 0x3040 && value <= 0x309F { return true }
        // Katakana: U+30A0-U+30FF
        if value >= 0x30A0 && value <= 0x30FF { return true }
        // CJK Unified Ideographs: U+4E00-U+9FFF
        if value >= 0x4E00 && value <= 0x9FFF { return true }
        // CJK Unified Ideographs Extension A: U+3400-U+4DBF
        if value >= 0x3400 && value <= 0x4DBF { return true }
        // Katakana Phonetic Extensions: U+31F0-U+31FF
        if value >= 0x31F0 && value <= 0x31FF { return true }

        return false
    }
}

@MainActor
final class AppState: ObservableObject {
    @Published var isModelLoaded = false
    @Published var isLoading = false
    @Published var loadingProgress: Double = 0
    @Published var currentModelName: String?
    @Published var currentModelId: String?
    @Published var conversations: [Conversation] = []
    @Published var currentConversation: Conversation?
    @Published var enabledMCPServers: Set<String> = ["filesystem", "calendar", "reminders", "websearch", "weather", "notes"]
    @Published var errorMessage: String?
    @Published var isGenerating = false  // Track if currently generating response
    @Published var inferenceMode: InferenceMode = .auto
    @Published var isInitialLoading = true  // Suppress UI during initial startup
    @Published var shouldStopGeneration = false  // Flag to stop generation

    // Widget support
    @Published var pendingQuickQuestion: String?  // Question from widget deep link
    @Published var showConversationList = false   // Trigger to show conversation list

    // Screenshot mode for App Store screenshots
    static var isScreenshotMode: Bool {
        ProcessInfo.processInfo.arguments.contains("-UITest_Screenshots") ||
        ProcessInfo.processInfo.environment["FASTLANE_SNAPSHOT"] == "YES"
    }

    private var llmEngine: CoreMLInference?
    private var llamaInference: LlamaInference?
    private var mcpClient: MCPClient?
    private var orchestrator: AgentOrchestrator?
    private let modelLoaderRef = ModelLoader()
    private let settingsManager = ModelSettingsManager.shared

    // Debounce task for saving conversations
    private var saveDebounceTask: Task<Void, Never>?

    // Token context limits based on device tier
    // These values correspond to LlamaInference context sizes:
    // ultra: 8192, high: 6144, medium: 4096, low: 2048
    // Reserve ~1000 tokens for system prompt and ~500 for generation
    private var maxContextTokens: Int {
        switch DeviceTier.current {
        case .ultra:
            return 6500  // 8192 context - 1500 reserved
        case .high:
            return 4600  // 6144 context - 1500 reserved
        case .medium:
            return 2600  // 4096 context - 1500 reserved
        case .low:
            return 1000  // 2048 context - 1000 reserved (minimal)
        }
    }

    private var summaryTokenBudget: Int {
        switch DeviceTier.current {
        case .ultra:
            return 800
        case .high:
            return 600
        case .medium:
            return 400
        case .low:
            return 200
        }
    }

    // Background summarization task
    private var summarizationTask: Task<Void, Never>?

    // MARK: - Token Context Management

    /// Estimate token count for a string (conservative estimate to prevent overflow)
    /// Japanese: ~2 tokens per character (conservative), English: ~0.3 tokens per character
    private func estimateTokens(_ text: String) -> Int {
        var japaneseCount = 0
        var otherCount = 0

        for char in text {
            if char.isJapanese {
                japaneseCount += 1
            } else {
                otherCount += 1
            }
        }

        // Conservative: Japanese ~2 tokens/char, English ~0.3 tokens/char, plus overhead
        // Better to underestimate context size than overflow
        return japaneseCount * 2 + Int(Double(otherCount) * 0.3) + 20
    }

    /// Trim conversation history to fit within context window
    /// Uses LLM-generated summary for older messages when available
    private func trimHistoryToFitContext(_ messages: [Message]) -> [Message] {
        guard !messages.isEmpty else { return [] }

        // Check if we have a cached summary
        var hasSummary = false
        var summaryContent = ""
        var summarizedIndex = 0

        if let conversation = currentConversation,
           let summary = conversation.historySummary,
           let summaryIdx = conversation.summarizedUpToIndex,
           summaryIdx > 0 {
            hasSummary = true
            summaryContent = summary
            summarizedIndex = summaryIdx
        }

        // Calculate available tokens (reserve space for summary if exists)
        let availableTokens = hasSummary
            ? maxContextTokens - estimateTokens(summaryContent)
            : maxContextTokens

        var result: [Message] = []
        var estimatedTokens = 0
        var trimStartIndex: Int? = nil

        // Process from newest to oldest, keeping messages that fit
        for (index, message) in messages.enumerated().reversed() {
            // Skip already summarized messages
            if hasSummary && index < summarizedIndex {
                continue
            }

            let messageTokens = estimateTokens(message.content)
            let thinkingTokens = message.thinkingContent.map { estimateTokens($0) } ?? 0
            let totalMessageTokens = messageTokens + thinkingTokens

            if estimatedTokens + totalMessageTokens > availableTokens {
                trimStartIndex = index + 1
                break
            }

            result.insert(message, at: 0)
            estimatedTokens += totalMessageTokens
        }

        // If we had to trim messages, queue summarization
        if let trimIdx = trimStartIndex, trimIdx > summarizedIndex {
            logInfo("Context", "Queueing summarization", [
                "newMessagesToSummarize": "\(trimIdx - summarizedIndex)",
                "totalMessagesKept": "\(result.count)"
            ])
            queueSummarization(messages: messages, upToIndex: trimIdx)
        }

        // Prepend summary as system context if available
        if hasSummary && !summaryContent.isEmpty {
            let summaryMessage = Message(
                role: .system,
                content: "【これまでの会話の要約】\n\(summaryContent)"
            )
            result.insert(summaryMessage, at: 0)
            logInfo("Context", "Using cached summary", [
                "summaryTokens": "\(estimateTokens(summaryContent))",
                "recentMessages": "\(result.count - 1)"
            ])
        }

        return result
    }

    /// Queue background summarization of old messages
    private func queueSummarization(messages: [Message], upToIndex: Int) {
        summarizationTask?.cancel()

        summarizationTask = Task { [weak self] in
            guard let self = self else { return }

            // Get messages to summarize
            let messagesToSummarize = Array(messages.prefix(upToIndex))
            guard !messagesToSummarize.isEmpty else { return }

            // Build summary prompt
            let conversationText = messagesToSummarize.map { msg in
                let role = msg.role == .user ? "ユーザー" : "アシスタント"
                return "\(role): \(msg.content)"
            }.joined(separator: "\n")

            let summaryPrompt = """
            以下の会話を簡潔に要約してください。重要なポイントと結論のみを残してください。

            会話:
            \(conversationText)

            要約（200文字以内）:
            """

            do {
                // Generate summary using LLM
                if let llm = self.llmEngine, let modelId = self.currentModelId {
                    var settings = self.settingsManager.settings(for: modelId)
                    settings.maxTokens = 150  // Short summary
                    var summary = ""

                    _ = try await llm.generate(
                        prompt: summaryPrompt,
                        settings: settings
                    ) { token in
                        summary += token
                    }

                    // Update conversation with summary
                    await MainActor.run {
                        if var conversation = self.currentConversation {
                            // Merge with existing summary if any
                            if let existingSummary = conversation.historySummary {
                                conversation.historySummary = existingSummary + "\n\n" + summary.trimmingCharacters(in: .whitespacesAndNewlines)
                            } else {
                                conversation.historySummary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
                            }
                            conversation.summarizedUpToIndex = upToIndex
                            self.currentConversation = conversation

                            // Update in conversations array
                            if let idx = self.conversations.firstIndex(where: { $0.id == conversation.id }) {
                                self.conversations[idx] = conversation
                            }
                            self.saveConversations()

                            logInfo("Context", "Summary generated", [
                                "summarizedMessages": "\(upToIndex)",
                                "summaryLength": "\(summary.count)"
                            ])
                        }
                    }
                }
            } catch {
                logError("Context", "Summarization failed: \(error.localizedDescription)")
            }
        }
    }

    /// Check if the currently loaded model supports vision/image input
    var currentModelSupportsVision: Bool {
        guard let modelId = currentModelId else { return false }
        return modelLoaderRef.modelSupportsVision(modelId)
    }

    /// Get downloaded vision models
    var downloadedVisionModels: [ModelLoader.ModelInfo] {
        modelLoaderRef.getDownloadedVisionModels()
    }

    /// Get the best vision model to download for this device
    var recommendedVisionModel: ModelLoader.ModelInfo? {
        modelLoaderRef.getRecommendedVisionModel(for: modelLoaderRef.deviceTier)
    }

    /// Check if any vision model is downloaded
    var hasDownloadedVisionModel: Bool {
        !downloadedVisionModels.isEmpty
    }

    /// Switch to a downloaded vision model (returns true if successful)
    func switchToVisionModel() async -> Bool {
        guard let visionModel = downloadedVisionModels.first else {
            return false
        }
        do {
            try await loadModel(named: visionModel.id)
            return true
        } catch {
            print("Failed to switch to vision model: \(error)")
            return false
        }
    }

    // Persist last used model and settings
    @AppStorage("lastUsedModel") private var lastUsedModel: String = ""
    @AppStorage("inferenceMode") private var storedInferenceMode: String = InferenceMode.auto.rawValue

    init() {
        // Restore saved inference mode
        self.inferenceMode = InferenceMode(rawValue: storedInferenceMode) ?? .auto

        // Start with empty conversations for faster startup
        // Load asynchronously to not block the UI
        Task { @MainActor in
            await loadConversationsAsync()
            setupMCPClient()
            await loadLastUsedModelIfAvailableAsync()
        }
    }

    // MARK: - Persistence

    private func loadConversationsAsync() async {
        // Skip loading from storage in screenshot mode - use mock data instead
        if AppState.isScreenshotMode {
            conversations = ScreenshotMockData.getMockConversations()
            return
        }
        // Migrate existing data if needed (synchronous but fast check)
        SharedDataManager.migrateIfNeeded()
        // Load from shared container asynchronously
        conversations = await SharedDataManager.loadConversationsAsync()
    }

    /// Save conversations with debouncing (non-blocking)
    func saveConversations() {
        // Cancel any pending save
        saveDebounceTask?.cancel()

        // Schedule new save after 1 second delay
        saveDebounceTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second debounce
            guard !Task.isCancelled else { return }
            // Save asynchronously to avoid blocking UI
            SharedDataManager.saveConversationsAsync(conversations)
        }
    }

    /// Force immediate save (for app termination)
    func saveConversationsImmediately() {
        saveDebounceTask?.cancel()
        SharedDataManager.saveConversations(conversations)
    }

    private func loadLastUsedModelIfAvailableAsync() async {
        guard !lastUsedModel.isEmpty else {
            // No saved model, end initial loading immediately
            isInitialLoading = false
            return
        }

        // Check if model is downloaded using existing modelLoaderRef
        if modelLoaderRef.isModelDownloaded(lastUsedModel) {
            try? await loadModel(named: lastUsedModel)
        }
        isInitialLoading = false
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

            // Trim history to prevent context overflow
            let trimmedHistory = trimHistoryToFitContext(currentConversation?.messages ?? [])

            if let orchestrator = orchestrator {
                response = try await orchestrator.process(
                    message: content,
                    history: trimmedHistory,
                    enabledServers: enabledMCPServers
                )
            } else if let llm = llmEngine, let modelId = currentModelId {
                // Get per-model settings
                let settings = settingsManager.settings(for: modelId)

                // Direct LLM call with proper chat formatting including date/time context
                let systemPrompt = buildSystemPrompt()
                var generatedText = ""
                _ = try await llm.generateWithMessages(
                    messages: trimmedHistory.isEmpty ? [userMessage] : trimmedHistory,
                    systemPrompt: systemPrompt,
                    settings: settings
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

    // Cached DateFormatters for performance
    private static let japaneseDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = "yyyy年M月d日(EEEE) HH:mm"
        return f
    }()

    private static let englishDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US")
        f.dateFormat = "EEEE, MMMM d, yyyy HH:mm"
        return f
    }()

    private func buildSystemPrompt() -> String {
        // Current date/time info - use cached formatters
        let currentDateTime = isJapanese
            ? Self.japaneseDateFormatter.string(from: Date())
            : Self.englishDateFormatter.string(from: Date())

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
            # ElioChat について
            あなたは「ElioChat」（エリオチャット）です。プライバシーを最優先するローカルAIアシスタントとして、ユーザーのデバイス上で完全に動作します。
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
            # About ElioChat
            You are ElioChat, a privacy-first local AI assistant that runs entirely on the user's device.
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

    func sendMessageWithStreaming(_ content: String, imageData: Data? = nil, onToken: @escaping (String) -> Void) async -> String {
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

        // Create message with optional image
        let messageContent = content.isEmpty ? String(localized: "chat.image.sent") : content
        let userMessage = Message(role: .user, content: messageContent, imageData: imageData)
        currentConversation?.messages.append(userMessage)
        currentConversation?.updatedAt = Date()

        // Update title based on first message
        if currentConversation?.messages.count == 1 {
            currentConversation?.title = String(content.prefix(30)) + (content.count > 30 ? "..." : "")
        }

        do {
            var fullResponse = ""

            // Trim history to prevent context overflow
            let trimmedHistory = trimHistoryToFitContext(currentConversation?.messages ?? [])

            // Use orchestrator for tool support (calendar, reminders, etc.)
            if let orchestrator = orchestrator {
                fullResponse = try await orchestrator.processWithStreaming(
                    message: content,
                    history: trimmedHistory,
                    enabledServers: enabledMCPServers,
                    onToken: { token in
                        onToken(token)
                    },
                    onToolCall: { toolInfo in
                        // Tool call notification (could show in UI)
                        logInfo("Tool", "Tool call: \(toolInfo)")
                    }
                )
            } else if let llm = llmEngine, let modelId = currentModelId {
                // Fallback to direct LLM without tools
                let settings = settingsManager.settings(for: modelId)
                let systemPrompt = buildSystemPrompt()
                _ = try await llm.generateWithMessages(
                    messages: trimmedHistory.isEmpty ? [userMessage] : trimmedHistory,
                    systemPrompt: systemPrompt,
                    settings: settings
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
            logError("LLM", "Generation error: \(error.localizedDescription)")
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

    /// Streaming version that doesn't add user message (for immediate UI feedback)
    func sendMessageWithStreamingNoUserMessage(_ content: String, imageData: Data? = nil, onToken: @escaping (String) -> Void) async -> String {
        guard isModelLoaded else {
            let msg = String(localized: "chat.model.not.loaded.description")
            onToken(msg)
            return msg
        }

        // Set generating flag immediately
        isGenerating = true
        defer { isGenerating = false }

        // Update conversation title if this is the first message
        currentConversation?.updatedAt = Date()
        if currentConversation?.messages.count == 1 {
            currentConversation?.title = String(content.prefix(30)) + (content.count > 30 ? "..." : "")
        }

        do {
            var fullResponse = ""

            // Trim history to prevent context overflow
            let trimmedHistory = trimHistoryToFitContext(currentConversation?.messages ?? [])

            // Use orchestrator for tool support (calendar, reminders, etc.)
            if let orchestrator = orchestrator {
                fullResponse = try await orchestrator.processWithStreaming(
                    message: content,
                    history: trimmedHistory,
                    enabledServers: enabledMCPServers,
                    onToken: { token in
                        onToken(token)
                    },
                    onToolCall: { toolInfo in
                        logInfo("Tool", "Tool call: \(toolInfo)")
                    }
                )
            } else if let llm = llmEngine, let modelId = currentModelId {
                // Fallback to direct LLM without tools
                let settings = settingsManager.settings(for: modelId)
                let systemPrompt = buildSystemPrompt()
                _ = try await llm.generateWithMessages(
                    messages: trimmedHistory,
                    systemPrompt: systemPrompt,
                    settings: settings
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
            logError("LLM", "Generation error: \(error.localizedDescription)")
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

    func clearAllConversations() {
        conversations.removeAll()
        currentConversation = nil
        saveConversations()
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
