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
    @Published var enabledMCPServers: Set<String> = ["filesystem", "calendar", "reminders", "websearch", "weather", "notes", "emergency_kb", "news"]
    @Published var isEmergencyMode = false
    @Published var errorMessage: String?
    @Published var isGenerating = false  // Track if currently generating response
    @Published var inferenceMode: InferenceMode = .auto
    @Published var isInitialLoading = true  // Suppress UI during initial startup
    @Published var shouldStopGeneration = false  // Flag to stop generation

    // Widget support
    @Published var pendingQuickQuestion: String?  // Question from widget deep link
    @Published var showConversationList = false   // Trigger to show conversation list

    // MARK: - Mac Catalyst
    #if targetEnvironment(macCatalyst)
    @AppStorage("macAutoStartP2PServer") var macAutoStartServer = true

    func macStartupSetup() async {
        guard macAutoStartServer else { return }
        // Auto-start P2P server on Mac after model is loaded
        if isModelLoaded {
            do {
                try await PrivateServerManager.shared.start()
            } catch {
                errorMessage = "P2P server auto-start failed: \(error.localizedDescription)"
            }
        }
    }
    #endif

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

    // Token context limits - calculated from model's actual context length
    // Reserve tokens for: system prompt (~2000), generation output (maxTokens), and safety buffer (~500)
    private var maxContextTokens: Int {
        guard let modelId = currentModelId else {
            // Fallback to conservative limit
            return 2500
        }

        // Get model's actual context length
        let modelInfo = modelLoaderRef.getModelInfo(modelId)
        let contextLength = modelInfo?.config.maxContextLength ?? 8192

        // Get user's maxTokens setting for output
        let settings = settingsManager.settings(for: modelId)
        let outputTokens = settings.maxTokens

        // Reserve: 2000 for system prompt, outputTokens for generation, 500 safety buffer
        let reservedTokens = 2000 + outputTokens + 500
        let availableTokens = contextLength - reservedTokens

        // Ensure reasonable minimum
        return max(availableTokens, 1000)
    }

    private var summaryTokenBudget: Int {
        // Use ~15% of available context for summary
        return max(min(maxContextTokens / 6, 800), 150)
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

            // Build summary prompt - include existing summary if any for re-summarization
            var conversationText = ""

            // Include existing summary context if we're extending it
            if let existingSummary = await MainActor.run(body: { self.currentConversation?.historySummary }),
               let previousIndex = await MainActor.run(body: { self.currentConversation?.summarizedUpToIndex }),
               previousIndex > 0 {
                conversationText += "【前回までの要約】\n\(existingSummary)\n\n【追加の会話】\n"

                // Only summarize new messages since last summary
                let newMessages = messagesToSummarize.suffix(from: previousIndex)
                conversationText += newMessages.map { msg in
                    let role = msg.role == .user ? "ユーザー" : "アシスタント"
                    return "\(role): \(msg.content)"
                }.joined(separator: "\n")
            } else {
                conversationText = messagesToSummarize.map { msg in
                    let role = msg.role == .user ? "ユーザー" : "アシスタント"
                    return "\(role): \(msg.content)"
                }.joined(separator: "\n")
            }

            // Detect language from conversation
            let isJapanese = conversationText.contains(where: { $0.isJapanese })

            let summaryPrompt: String
            if isJapanese {
                summaryPrompt = """
                以下の会話の要約を作成してください。

                ルール:
                - 重要な情報、決定事項、ユーザーの好みを残す
                - 具体的な数値や固有名詞は省略しない
                - 箇条書きで簡潔にまとめる
                - 300文字以内

                会話:
                \(conversationText)

                要約:
                """
            } else {
                summaryPrompt = """
                Summarize the following conversation.

                Rules:
                - Keep important information, decisions, and user preferences
                - Don't omit specific numbers or proper nouns
                - Use bullet points for clarity
                - Maximum 150 words

                Conversation:
                \(conversationText)

                Summary:
                """
            }

            do {
                // Generate summary using LLM
                if let llm = self.llmEngine, let modelId = self.currentModelId {
                    var settings = self.settingsManager.settings(for: modelId)
                    settings.maxTokens = 200  // Enough for good summary
                    settings.temperature = 0.3  // More deterministic for summaries
                    var summary = ""

                    _ = try await llm.generate(
                        prompt: summaryPrompt,
                        settings: settings,
                        stopSequences: ["<|im_end|>", "<|eot_id|>", "\n\n\n"]
                    ) { token in
                        summary += token
                    }

                    // Clean up summary
                    let cleanedSummary = summary
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .replacingOccurrences(of: "<think>", with: "")
                        .replacingOccurrences(of: "</think>", with: "")

                    // Update conversation with summary
                    await MainActor.run {
                        if var conversation = self.currentConversation {
                            // Replace the summary entirely (we included the old one in the prompt)
                            conversation.historySummary = cleanedSummary
                            conversation.summarizedUpToIndex = upToIndex
                            self.currentConversation = conversation

                            // Update in conversations array
                            if let idx = self.conversations.firstIndex(where: { $0.id == conversation.id }) {
                                self.conversations[idx] = conversation
                            }
                            self.saveConversations()

                            logInfo("Context", "Summary generated", [
                                "summarizedMessages": "\(upToIndex)",
                                "summaryLength": "\(cleanedSummary.count)"
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

        // Setup MCP client synchronously (fast operation)
        setupMCPClient()

        // Setup memory warning handler to prevent crashes
        setupMemoryWarningHandler()

        // Immediately make UI interactive
        Task { @MainActor in
            // Load conversations and model in parallel for faster startup
            async let conversationsTask: () = loadConversationsAsync()
            async let modelTask: () = loadLastUsedModelIfAvailableAsync()
            async let apiKeyTask: () = initializeChatWebAPIKey()

            // Wait for all to complete
            _ = await (conversationsTask, modelTask, apiKeyTask)
        }
    }

    // MARK: - Memory Management

    /// Setup memory warning handler to prevent out-of-memory crashes
    private func setupMemoryWarningHandler() {
        #if !targetEnvironment(macCatalyst)
        NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleMemoryWarning()
        }
        #endif
    }

    /// Handle memory warning by unloading model and freeing resources
    private func handleMemoryWarning() {
        logWarning("AppState", "⚠️ Memory warning received - unloading model to prevent crash")

        // Unload model to free memory
        unloadModel()

        // Show user-friendly message
        errorMessage = "メモリ不足のため、モデルをアンロードしました。再度モデルを読み込んでください。"

        // Force garbage collection (iOS will do this automatically, but we can help)
        autoreleasepool {
            // Release any temporary objects
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

    private func initializeChatWebAPIKey() async {
        do {
            try await ChatWebAPIKeyManager.shared.initialize()

            // Set device API key in ChatWebBackend
            if let apiKey = ChatWebAPIKeyManager.shared.apiKey {
                ChatModeManager.shared.setChatWebBackend(deviceAPIKey: apiKey)
            }
        } catch {
            print("[AppState] Failed to initialize ChatWeb API key: \(error)")
            // エラーでもアプリ起動はブロックしない（session-based authにフォールバック）
        }
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
        // End initial loading immediately to show UI faster
        isInitialLoading = false

        guard !lastUsedModel.isEmpty else {
            return
        }

        // Check if model is downloaded using existing modelLoaderRef
        if modelLoaderRef.isModelDownloaded(lastUsedModel) {
            try? await loadModel(named: lastUsedModel)
        }
    }

    private func setupMCPClient() {
        mcpClient = MCPClient()
        mcpClient?.registerBuiltInServers()
    }

    /// Check if any model is downloaded, if not, initiate ODR download for ElioChat
    func ensureInitialModelAvailable() async {
        let modelLoader = ModelLoader.shared

        // Check if any model is already downloaded
        let hasAnyModel = modelLoader.availableModels.contains { model in
            modelLoader.isModelDownloaded(model.id)
        }

        if hasAnyModel {
            return // User already has a model
        }

        // No models available - initiate ODR download for ElioChat
        let eliochatModelId = "eliochat-1.7b-jp-v2"
        guard let eliochatModel = modelLoader.availableModels.first(where: { $0.id == eliochatModelId }) else {
            return
        }

        // Start ODR download in background
        Task {
            do {
                try await modelLoader.downloadModel(eliochatModel)
                logInfo("AppState", "ElioChat model downloaded via ODR", [:])
            } catch {
                logError("AppState", "Failed to download ElioChat via ODR: \(error.localizedDescription)", [:])
            }
        }
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

            // Configure P2P backend before setting isModelLoaded (onChange triggers macStartupSetup)
            if let llm = llmEngine {
                ChatModeManager.shared.configureLocalBackend(llm)
            }
            isModelLoaded = true
            loadingProgress = 1.0

            // Save as last used model for next startup
            lastUsedModel = modelName

            if let llm = llmEngine, let mcp = mcpClient {
                orchestrator = AgentOrchestrator(llm: llm, mcpClient: mcp, modelId: modelName)
            }
        } catch {
            errorMessage = error.localizedDescription
            throw error
        }
    }

    func sendMessage(_ content: String) async -> String {
        // Check if current mode is available
        let currentMode = ChatModeManager.shared.currentMode
        let isCloudMode = [.chatweb, .fast, .genius, .publicP2P, .p2pMesh].contains(currentMode)

        // For cloud modes, skip local model check
        if !isCloudMode {
            guard isModelLoaded else {
                return String(localized: "chat.model.not.loaded.description")
            }
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

            // Use ChatModeManager's backend system for all modes
            if let backend = ChatModeManager.shared.currentBackend {
                let settings = currentModelId.map { settingsManager.settings(for: $0) } ?? ModelSettings.default
                let systemPrompt = buildSystemPrompt()

                var generatedText = ""
                _ = try await backend.generate(
                    messages: trimmedHistory.isEmpty ? [userMessage] : trimmedHistory,
                    systemPrompt: systemPrompt,
                    settings: settings
                ) { token in
                    generatedText += token
                }
                response = generatedText
            } else if let orchestrator = orchestrator {
                // Fallback to orchestrator for MCP modes
                response = try await orchestrator.process(
                    message: content,
                    history: trimmedHistory,
                    enabledServers: enabledMCPServers
                )
            } else if let llm = llmEngine, let modelId = currentModelId {
                // Legacy fallback for direct LLM access
                let settings = settingsManager.settings(for: modelId)
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
            // Don't show error for cancellation
            if error is CancellationError || shouldStopGeneration {
                return ""
            }
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
        // Get current language code
        let languageCode = Locale.current.language.languageCode?.identifier ?? "en"

        // Current date/time info - use cached formatters
        let currentDateTime = isJapanese
            ? Self.japaneseDateFormatter.string(from: Date())
            : Self.englishDateFormatter.string(from: Date())

        // Build recent conversation titles
        let recentConversations = conversations.prefix(5).map { $0.title }

        // Use localized system prompt
        return SystemPromptLocalizations.getPrompt(
            for: languageCode,
            currentDateTime: currentDateTime,
            recentConversations: Array(recentConversations),
            isEmergencyMode: isEmergencyMode
        )
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
            // Don't show error for cancellation
            if error is CancellationError || shouldStopGeneration {
                return ""
            }
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
        let chatMode = ChatModeManager.shared.currentMode
        let useCloudBackend = chatMode != .local && chatMode != .p2pMesh && chatMode != .speculative

        // For cloud modes, use ChatModeManager directly (no local model required)
        if useCloudBackend {
            return await sendViaCloudBackend(content: content, onToken: onToken)
        }

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
            // Don't show error for cancellation
            if error is CancellationError || shouldStopGeneration {
                return ""
            }
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

    /// Route generation through ChatModeManager for cloud backends (chatweb, fast, genius, P2P)
    private func sendViaCloudBackend(content: String, onToken: @escaping (String) -> Void) async -> String {
        isGenerating = true
        defer { isGenerating = false }

        currentConversation?.updatedAt = Date()
        if currentConversation?.messages.count == 1 {
            currentConversation?.title = String(content.prefix(30)) + (content.count > 30 ? "..." : "")
        }

        do {
            let trimmedHistory = trimHistoryToFitContext(currentConversation?.messages ?? [])
            let systemPrompt = buildSystemPrompt()
            let settings: ModelSettings
            if let modelId = currentModelId {
                settings = settingsManager.settings(for: modelId)
            } else {
                settings = .default
            }

            let fullResponse = try await ChatModeManager.shared.generate(
                messages: trimmedHistory,
                systemPrompt: systemPrompt,
                settings: settings,
                onToken: onToken
            )

            let parsed = Message.parseThinkingContent(fullResponse)
            let assistantMessage = Message(
                role: .assistant,
                content: parsed.content.isEmpty ? fullResponse : parsed.content,
                thinkingContent: parsed.thinking
            )
            currentConversation?.messages.append(assistantMessage)
            currentConversation?.updatedAt = Date()

            if let current = currentConversation,
               let index = conversations.firstIndex(where: { $0.id == current.id }) {
                conversations[index] = current
            }
            saveConversations()

            return fullResponse
        } catch {
            if error is CancellationError || shouldStopGeneration {
                return ""
            }
            let errorResponse = "エラーが発生しました: \(error.localizedDescription)"
            logError("Cloud", "Generation error: \(error.localizedDescription)")
            onToken(errorResponse)
            let assistantMessage = Message(role: .assistant, content: errorResponse)
            currentConversation?.messages.append(assistantMessage)

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

    func toggleEmergencyMode() {
        isEmergencyMode.toggle()
    }

    func unloadModel() {
        // Explicitly unload the CoreMLInference (which contains LlamaInference)
        llmEngine?.unload()
        llmEngine = nil
        // Also unload any standalone llamaInference if present
        llamaInference?.unload()
        llamaInference = nil
        orchestrator = nil
        ChatModeManager.shared.clearLocalBackend()
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
