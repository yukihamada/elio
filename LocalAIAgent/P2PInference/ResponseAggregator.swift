import Foundation

// MARK: - Aggregation Types

/// A single response with ranking metadata attached by the aggregator.
struct RankedResponse {
    let response: DistributedResponse
    let rank: Int
    let qualityScore: Double
    let isOutlier: Bool
}

/// Extended aggregated result with consensus scoring and ranked individual responses.
struct EnrichedAggregatedResult {
    let summary: String
    let responses: [RankedResponse]
    let totalPeers: Int
    let avgConfidence: Double
    let processingTimeMs: Int
    let consensusScore: Double
}

// MARK: - Response Aggregator

/// Merges, ranks, and summarizes multiple P2P responses into a single coherent result.
///
/// Scoring weights:
/// - confidence (self-reported)                 x 0.3
/// - responseLength (penalize extremes)         x 0.2
/// - processingTime (faster is better)          x 0.1
/// - consensusAlignment (Jaccard with others)   x 0.4
///
/// Outlier detection: consensusAlignment < 0.2
/// Merge strategy: top-3 responses summarized via local LLM; fallback to best single response.
@MainActor
final class ResponseAggregator {

    // MARK: - Score Weights

    private static let weightConfidence: Double = 0.3
    private static let weightLength: Double = 0.2
    private static let weightSpeed: Double = 0.1
    private static let weightConsensus: Double = 0.4

    /// Responses below this consensus alignment are flagged as outliers.
    private static let outlierThreshold: Double = 0.2

    /// Maximum number of top responses fed to LLM for merging.
    private static let mergeTopK = 3

    // MARK: - Public API

    /// Aggregate multiple peer responses into a single enriched result.
    /// - Parameters:
    ///   - responses: Raw responses from peers (uses existing `DistributedResponse`).
    ///   - llm: Optional local backend for LLM-powered merge. Pass `nil` to use best-score fallback.
    /// - Returns: Enriched aggregated result with ranked responses, consensus score, and merged summary.
    func aggregate(
        _ responses: [DistributedResponse],
        using llm: (any InferenceBackend)? = nil
    ) async -> EnrichedAggregatedResult {
        let startTime = CFAbsoluteTimeGetCurrent()

        guard !responses.isEmpty else {
            return EnrichedAggregatedResult(
                summary: "",
                responses: [],
                totalPeers: 0,
                avgConfidence: 0,
                processingTimeMs: 0,
                consensusScore: 0
            )
        }

        // 1. Score every response
        let scored: [(response: DistributedResponse, score: Double)] = responses.map { r in
            (r, scoreResponse(r, allResponses: responses))
        }

        // 2. Sort descending by quality score
        let sorted = scored.sorted { $0.score > $1.score }

        // 3. Compute per-response consensus alignment for outlier detection
        let consensusAlignments: [UUID: Double] = Dictionary(
            uniqueKeysWithValues: responses.map { r in
                (r.id, consensusAlignment(r, allResponses: responses))
            }
        )

        // 4. Build ranked list
        let ranked: [RankedResponse] = sorted.enumerated().map { index, pair in
            let alignment = consensusAlignments[pair.response.id] ?? 0
            return RankedResponse(
                response: pair.response,
                rank: index + 1,
                qualityScore: pair.score,
                isOutlier: alignment < Self.outlierThreshold
            )
        }

        // 5. Overall consensus score = average pairwise Jaccard across non-outlier responses
        let nonOutlierContents = ranked
            .filter { !$0.isOutlier }
            .map(\.response.responseText)
        let consensusScore = averagePairwiseJaccard(nonOutlierContents)

        // 6. Average confidence
        let avgConfidence = responses.map(\.confidence).reduce(0, +) / Double(responses.count)

        // 7. Merge top-K via LLM (or fallback)
        let topResponses = Array(sorted.prefix(Self.mergeTopK).map(\.response))
        let summary: String
        if let llm = llm {
            summary = await mergeWithLLM(topResponses, llm: llm)
                ?? topResponses.first?.responseText ?? ""
        } else {
            summary = topResponses.first?.responseText ?? ""
        }

        let elapsedMs = Int((CFAbsoluteTimeGetCurrent() - startTime) * 1000)

        return EnrichedAggregatedResult(
            summary: summary,
            responses: ranked,
            totalPeers: responses.count,
            avgConfidence: avgConfidence,
            processingTimeMs: elapsedMs,
            consensusScore: consensusScore
        )
    }

    // MARK: - Scoring

    /// Compute an overall quality score for a single response in context of all responses.
    func scoreResponse(
        _ response: DistributedResponse,
        allResponses: [DistributedResponse]
    ) -> Double {
        let confScore = normalizedConfidence(response.confidence)
        let lenScore = lengthScore(response.responseText)
        let spdScore = speedScore(response.processingTimeMs, allResponses: allResponses)
        let consensScore = consensusAlignment(response, allResponses: allResponses)

        return confScore * Self.weightConfidence
             + lenScore * Self.weightLength
             + spdScore * Self.weightSpeed
             + consensScore * Self.weightConsensus
    }

    // MARK: - Similarity

    /// Jaccard similarity between two strings, tokenized by whitespace and punctuation.
    func jaccardSimilarity(_ a: String, _ b: String) -> Double {
        let setA = Set(a.lowercased().split(whereSeparator: { $0.isWhitespace || $0.isPunctuation }))
        let setB = Set(b.lowercased().split(whereSeparator: { $0.isWhitespace || $0.isPunctuation }))

        guard !setA.isEmpty || !setB.isEmpty else { return 1.0 }

        let intersection = setA.intersection(setB).count
        let union = setA.union(setB).count

        guard union > 0 else { return 0 }
        return Double(intersection) / Double(union)
    }

    // MARK: - LLM Merge

    /// Summarize the top responses using a local LLM.
    /// Returns `nil` if the LLM call fails so the caller can fall back to the best single response.
    func mergeWithLLM(
        _ topResponses: [DistributedResponse],
        llm: any InferenceBackend
    ) async -> String? {
        guard llm.isReady, !topResponses.isEmpty else { return nil }

        let numbered = topResponses.enumerated().map { i, r in
            "[\(i + 1)] \(r.responseText)"
        }.joined(separator: "\n\n")

        let prompt = """
        以下の複数の回答を統合して、最も正確で包括的な回答を作成してください。\
        重複は排除し、矛盾がある場合は多数派の見解を採用してください。

        \(numbered)
        """

        let message = Message(
            id: UUID(),
            role: .user,
            content: prompt,
            timestamp: Date()
        )

        let settings = ModelSettings.default

        do {
            var merged = ""
            _ = try await llm.generate(
                messages: [message],
                systemPrompt: "You are a helpful assistant that merges multiple answers into one concise, accurate response.",
                settings: settings
            ) { token in
                merged += token
            }
            return merged.isEmpty ? nil : merged
        } catch {
            print("[ResponseAggregator] LLM merge failed: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Private Helpers

    /// Clamp and normalize confidence to [0, 1].
    private func normalizedConfidence(_ confidence: Double) -> Double {
        min(max(confidence, 0), 1)
    }

    /// Score response length with a bell-curve penalty.
    /// Sweet spot: 50-500 characters. Too short or too long gets penalized.
    private func lengthScore(_ content: String) -> Double {
        let len = content.count
        if len < 10 { return 0.1 }
        if len < 50 { return 0.5 }
        if len <= 500 { return 1.0 }
        if len <= 2000 { return 0.8 }
        return 0.5
    }

    /// Score processing time relative to the cohort. Fastest = 1.0, slowest = 0.0.
    private func speedScore(_ timeMs: Int, allResponses: [DistributedResponse]) -> Double {
        let times = allResponses.map(\.processingTimeMs)
        guard let minTime = times.min(), let maxTime = times.max(), maxTime > minTime else {
            return 1.0
        }
        return 1.0 - Double(timeMs - minTime) / Double(maxTime - minTime)
    }

    /// Average Jaccard similarity of this response against all *other* responses.
    private func consensusAlignment(
        _ response: DistributedResponse,
        allResponses: [DistributedResponse]
    ) -> Double {
        let others = allResponses.filter { $0.id != response.id }
        guard !others.isEmpty else { return 1.0 }

        let totalSim = others.reduce(0.0) { sum, other in
            sum + jaccardSimilarity(response.responseText, other.responseText)
        }
        return totalSim / Double(others.count)
    }

    /// Average pairwise Jaccard across a set of strings.
    private func averagePairwiseJaccard(_ texts: [String]) -> Double {
        guard texts.count >= 2 else { return texts.isEmpty ? 0 : 1.0 }

        var total = 0.0
        var count = 0
        for i in 0..<texts.count {
            for j in (i + 1)..<texts.count {
                total += jaccardSimilarity(texts[i], texts[j])
                count += 1
            }
        }
        return count > 0 ? total / Double(count) : 0
    }
}
