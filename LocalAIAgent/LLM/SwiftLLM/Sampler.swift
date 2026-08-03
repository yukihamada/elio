import Foundation
import Accelerate

// MARK: - Sampling Strategies

struct SamplerConfig {
    var temperature: Float = 0.7
    var topP: Float = 0.9
    var topK: Int = 40
    var repeatPenalty: Float = 1.1
    var repeatWindow: Int = 64
}

final class Sampler {
    var config: SamplerConfig

    init(config: SamplerConfig = SamplerConfig()) {
        self.config = config
    }

    /// Sample next token from logits
    func sample(logits: inout [Float], previousTokens: [Int] = []) -> Int {
        let vocabSize = logits.count

        // 1. Apply repetition penalty
        if config.repeatPenalty > 1.0 && !previousTokens.isEmpty {
            let window = previousTokens.suffix(config.repeatWindow)
            for tokenId in window {
                if tokenId >= 0 && tokenId < vocabSize {
                    if logits[tokenId] > 0 {
                        logits[tokenId] /= config.repeatPenalty
                    } else {
                        logits[tokenId] *= config.repeatPenalty
                    }
                }
            }
        }

        // 2. Temperature = 0 → greedy
        if config.temperature < 0.01 {
            return argmax(logits)
        }

        // 3. Apply temperature
        var invTemp = 1.0 / config.temperature
        vDSP_vsmul(logits, 1, &invTemp, &logits, 1, vDSP_Length(vocabSize))

        // 4. Top-K filtering
        var candidates = topKFilter(logits: logits, k: config.topK)

        // 5. Softmax over candidates
        softmaxCandidates(&candidates)

        // 6. Top-P (nucleus) filtering
        topPFilter(&candidates, p: config.topP)

        // 7. Sample from distribution
        return sampleFromCandidates(candidates)
    }

    /// Greedy decoding
    func argmax(_ logits: [Float]) -> Int {
        var maxVal: Float = -Float.infinity
        var maxIdx: vDSP_Length = 0
        logits.withUnsafeBufferPointer { ptr in
            vDSP_maxvi(ptr.baseAddress!, 1, &maxVal, &maxIdx, vDSP_Length(logits.count))
        }
        return Int(maxIdx)
    }

    // MARK: - Private

    private struct Candidate: Comparable {
        let id: Int
        var logit: Float
        var prob: Float

        static func < (lhs: Candidate, rhs: Candidate) -> Bool {
            lhs.logit > rhs.logit  // Sort descending
        }
    }

    private func topKFilter(logits: [Float], k: Int) -> [Candidate] {
        // Create (id, logit) pairs and partial sort
        var candidates: [Candidate] = []
        candidates.reserveCapacity(k)

        // Use a min-heap approach for efficiency with large vocab
        for (i, logit) in logits.enumerated() {
            if candidates.count < k {
                candidates.append(Candidate(id: i, logit: logit, prob: 0))
                if candidates.count == k {
                    candidates.sort()
                }
            } else if logit > candidates.last!.logit {
                candidates[k - 1] = Candidate(id: i, logit: logit, prob: 0)
                // Insertion sort to maintain order
                var j = k - 1
                while j > 0 && candidates[j].logit > candidates[j-1].logit {
                    candidates.swapAt(j, j-1)
                    j -= 1
                }
            }
        }

        if candidates.count < k {
            candidates.sort()
        }

        return candidates
    }

    private func softmaxCandidates(_ candidates: inout [Candidate]) {
        guard !candidates.isEmpty else { return }

        let maxLogit = candidates[0].logit
        var sum: Float = 0
        for i in 0..<candidates.count {
            candidates[i].prob = expf(candidates[i].logit - maxLogit)
            sum += candidates[i].prob
        }
        let invSum = 1.0 / sum
        for i in 0..<candidates.count {
            candidates[i].prob *= invSum
        }
    }

    private func topPFilter(_ candidates: inout [Candidate], p: Float) {
        var cumProb: Float = 0
        var cutoff = candidates.count
        for (i, c) in candidates.enumerated() {
            cumProb += c.prob
            if cumProb >= p {
                cutoff = i + 1
                break
            }
        }
        candidates = Array(candidates.prefix(cutoff))

        // Renormalize
        let sum = candidates.reduce(Float(0)) { $0 + $1.prob }
        let invSum = 1.0 / sum
        for i in 0..<candidates.count {
            candidates[i].prob *= invSum
        }
    }

    private func sampleFromCandidates(_ candidates: [Candidate]) -> Int {
        let r = Float.random(in: 0..<1)
        var cumProb: Float = 0
        for c in candidates {
            cumProb += c.prob
            if r < cumProb {
                return c.id
            }
        }
        return candidates.last?.id ?? 0
    }
}
