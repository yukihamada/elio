import Foundation

/// Server-side verifier for speculative decoding
/// Verifies draft tokens from a requester using a target model (typically 7B)
@MainActor
final class SpeculativeVerifier {

    private let targetModel: LlamaInference  // Large target model (7B+)

    init(targetModel: LlamaInference) {
        self.targetModel = targetModel
    }

    /// Verify draft tokens against target model predictions
    /// Returns list of accepted tokens and optional fallback token
    func verify(
        context: String,
        draftTokens: [String],
        settings: ModelSettings
    ) async throws -> SpeculativeVerificationResult {
        var acceptedTokens: [String] = []
        var currentContext = context

        print("[SpeculativeVerifier] Verifying \(draftTokens.count) draft tokens")

        for (index, draftToken) in draftTokens.enumerated() {
            // Generate next token with target model
            var targetToken = ""

            _ = try await targetModel.generate(
                prompt: currentContext,
                maxTokens: 1,
                temperature: settings.temperature,
                topP: settings.topP,
                topK: Int32(settings.topK),
                repeatPenalty: settings.repeatPenalty,
                stopSequences: ["</s>", "<|im_end|>"],
                onToken: { token in
                    targetToken = token
                }
            )

            // Compare draft vs target token
            if draftToken == targetToken {
                // Accept draft token
                acceptedTokens.append(draftToken)
                currentContext += draftToken
                print("[SpeculativeVerifier] Token \(index) accepted: '\(draftToken)'")
            } else {
                // Reject draft token, use target token instead
                print("[SpeculativeVerifier] Token \(index) rejected. Draft: '\(draftToken)', Target: '\(targetToken)'")

                // If this is the first token, provide the target token as fallback
                if index == 0 {
                    return SpeculativeVerificationResult(
                        acceptedTokens: [targetToken],
                        rejectedIndex: index,
                        fallbackToken: targetToken
                    )
                } else {
                    // Return accepted tokens so far (target token is NOT added)
                    return SpeculativeVerificationResult(
                        acceptedTokens: acceptedTokens,
                        rejectedIndex: index,
                        fallbackToken: nil
                    )
                }
            }

            // Check for EOS
            if draftToken == "</s>" || draftToken == "<|im_end|>" {
                break
            }
        }

        // All draft tokens accepted
        print("[SpeculativeVerifier] All \(acceptedTokens.count) tokens accepted")
        return SpeculativeVerificationResult(
            acceptedTokens: acceptedTokens,
            rejectedIndex: nil,
            fallbackToken: nil
        )
    }
}

// MARK: - Verification with Probability Comparison (Future Enhancement)

extension SpeculativeVerifier {

    /// Verify tokens using probability distribution comparison
    /// This is a more sophisticated verification method that compares token probabilities
    /// rather than exact token matches. Not implemented yet (requires llama.cpp extension).
    func verifyWithProbabilities(
        context: String,
        draftTokens: [String],
        draftProbabilities: [Float],
        settings: ModelSettings,
        threshold: Float = 0.8
    ) async throws -> SpeculativeVerificationResult {
        // Probability-based verification requires llama.cpp token probability API
        // which is not yet exposed in LlamaInference. Falls back to exact token matching.
        return try await verify(
            context: context,
            draftTokens: draftTokens,
            settings: settings
        )
    }
}
