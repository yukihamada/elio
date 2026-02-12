import Foundation

/// Local inference backend wrapping CoreMLInference
/// Token cost: 0 (free, on-device)
@MainActor
final class LocalBackend: InferenceBackend {
    private let inference: CoreMLInference

    var backendId: String { "local" }
    var displayName: String { ChatMode.local.displayName }
    var tokenCost: Int { 0 }

    var isReady: Bool {
        inference.isLoaded
    }

    var isGenerating: Bool {
        inference.isGenerating
    }

    init(inference: CoreMLInference) {
        self.inference = inference
    }

    func generate(
        messages: [Message],
        systemPrompt: String,
        settings: ModelSettings,
        onToken: @escaping (String) -> Void
    ) async throws -> String {
        guard isReady else {
            throw InferenceError.notReady
        }

        return try await inference.generateWithMessages(
            messages: messages,
            systemPrompt: systemPrompt,
            settings: settings,
            onToken: onToken
        )
    }

    func stopGeneration() {
        // Local inference stop is handled by the CoreMLInference/LlamaInference
        // Currently, stopping is done via shouldStopGeneration flag in AppState
    }
}
