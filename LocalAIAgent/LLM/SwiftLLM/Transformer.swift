import Foundation
import Accelerate

// MARK: - Transformer Model
// Pure Swift Qwen3/Llama-style transformer with GQA, RoPE, SwiGLU

final class TransformerModel {
    let config: Config
    let weights: Weights

    struct Config {
        let nLayers: Int
        let nHeads: Int
        let nKVHeads: Int
        let embDim: Int
        let headDim: Int
        let ffnDim: Int
        let vocabSize: Int
        let rmsNormEps: Float
        let ropeFreqBase: Float
        let maxSeqLen: Int

        var nGQAGroups: Int { nHeads / nKVHeads }
    }

    struct Weights {
        let tokenEmbedding: [Float]      // [vocabSize, embDim]
        let outputNorm: [Float]          // [embDim]
        let outputWeight: [Float]?       // [vocabSize, embDim] (may share with tokenEmbedding)
        let layers: [LayerWeights]
    }

    struct LayerWeights {
        let attnNorm: [Float]       // [embDim]
        let ffnNorm: [Float]        // [embDim]
        let wq: [Float]             // [nHeads*headDim, embDim]
        let wk: [Float]             // [nKVHeads*headDim, embDim]
        let wv: [Float]             // [nKVHeads*headDim, embDim]
        let wo: [Float]             // [embDim, nHeads*headDim]
        let wGate: [Float]          // [ffnDim, embDim]
        let wUp: [Float]            // [ffnDim, embDim]
        let wDown: [Float]          // [embDim, ffnDim]
        // Optional QK norm for Qwen3
        let qNorm: [Float]?         // [headDim]
        let kNorm: [Float]?         // [headDim]
    }

    // KV Cache
    private var keyCache: [[Float]]    // [layer][seq_pos * nKVHeads * headDim]
    private var valueCache: [[Float]]  // [layer][seq_pos * nKVHeads * headDim]
    private var cacheLength: Int = 0

    init(config: Config, weights: Weights) {
        self.config = config
        self.weights = weights
        self.keyCache = Array(repeating: [], count: config.nLayers)
        self.valueCache = Array(repeating: [], count: config.nLayers)
    }

    func clearCache() {
        for i in 0..<config.nLayers {
            keyCache[i] = []
            valueCache[i] = []
        }
        cacheLength = 0
    }

    // MARK: - Forward pass (single token)

    /// Run transformer forward pass for a single token, return logits
    func forward(tokenId: Int, position: Int) -> [Float] {
        let c = config

        // Token embedding lookup
        var hidden = [Float](repeating: 0, count: c.embDim)
        let embOffset = tokenId * c.embDim
        hidden.withUnsafeMutableBufferPointer { dst in
            weights.tokenEmbedding.withUnsafeBufferPointer { src in
                memcpy(dst.baseAddress!, src.baseAddress! + embOffset, c.embDim * MemoryLayout<Float>.size)
            }
        }

        // Scratch buffers (reused across layers)
        var normed = [Float](repeating: 0, count: c.embDim)
        var q = [Float](repeating: 0, count: c.nHeads * c.headDim)
        var k = [Float](repeating: 0, count: c.nKVHeads * c.headDim)
        var v = [Float](repeating: 0, count: c.nKVHeads * c.headDim)
        var attnOut = [Float](repeating: 0, count: c.nHeads * c.headDim)
        var gate = [Float](repeating: 0, count: c.ffnDim)
        var up = [Float](repeating: 0, count: c.ffnDim)
        var ffnOut = [Float](repeating: 0, count: c.embDim)
        var siluBuf = [Float](repeating: 0, count: c.ffnDim)

        // Process each layer
        for layer in 0..<c.nLayers {
            let w = weights.layers[layer]

            // 1. Attention norm
            hidden.withUnsafeBufferPointer { hPtr in
                w.attnNorm.withUnsafeBufferPointer { wPtr in
                    normed.withUnsafeMutableBufferPointer { nPtr in
                        VecOps.rmsNorm(hPtr.baseAddress!, wPtr.baseAddress!,
                                       nPtr.baseAddress!, count: c.embDim, eps: c.rmsNormEps)
                    }
                }
            }

            // 2. QKV projections
            normed.withUnsafeBufferPointer { nPtr in
                w.wq.withUnsafeBufferPointer { wqPtr in
                    q.withUnsafeMutableBufferPointer { qPtr in
                        VecOps.matvec(wqPtr.baseAddress!, nPtr.baseAddress!,
                                      qPtr.baseAddress!, rows: c.nHeads * c.headDim, cols: c.embDim)
                    }
                }
                w.wk.withUnsafeBufferPointer { wkPtr in
                    k.withUnsafeMutableBufferPointer { kPtr in
                        VecOps.matvec(wkPtr.baseAddress!, nPtr.baseAddress!,
                                      kPtr.baseAddress!, rows: c.nKVHeads * c.headDim, cols: c.embDim)
                    }
                }
                w.wv.withUnsafeBufferPointer { wvPtr in
                    v.withUnsafeMutableBufferPointer { vPtr in
                        VecOps.matvec(wvPtr.baseAddress!, nPtr.baseAddress!,
                                      vPtr.baseAddress!, rows: c.nKVHeads * c.headDim, cols: c.embDim)
                    }
                }
            }

            // 3. QK Norm (Qwen3)
            if let qNorm = w.qNorm, let kNorm = w.kNorm {
                for h in 0..<c.nHeads {
                    let off = h * c.headDim
                    q.withUnsafeMutableBufferPointer { qPtr in
                        qNorm.withUnsafeBufferPointer { nPtr in
                            var tmp = [Float](repeating: 0, count: c.headDim)
                            tmp.withUnsafeMutableBufferPointer { tPtr in
                                VecOps.rmsNorm(qPtr.baseAddress! + off, nPtr.baseAddress!,
                                               tPtr.baseAddress!, count: c.headDim, eps: c.rmsNormEps)
                            }
                            memcpy(qPtr.baseAddress! + off, &tmp, c.headDim * MemoryLayout<Float>.size)
                        }
                    }
                }
                for h in 0..<c.nKVHeads {
                    let off = h * c.headDim
                    k.withUnsafeMutableBufferPointer { kPtr in
                        kNorm.withUnsafeBufferPointer { nPtr in
                            var tmp = [Float](repeating: 0, count: c.headDim)
                            tmp.withUnsafeMutableBufferPointer { tPtr in
                                VecOps.rmsNorm(kPtr.baseAddress! + off, nPtr.baseAddress!,
                                               tPtr.baseAddress!, count: c.headDim, eps: c.rmsNormEps)
                            }
                            memcpy(kPtr.baseAddress! + off, &tmp, c.headDim * MemoryLayout<Float>.size)
                        }
                    }
                }
            }

            // 4. RoPE on Q and K
            q.withUnsafeMutableBufferPointer { qPtr in
                VecOps.applyRoPE(qPtr.baseAddress!, headDim: c.headDim,
                                 position: position, ropeFreqBase: c.ropeFreqBase, nHeads: c.nHeads)
            }
            k.withUnsafeMutableBufferPointer { kPtr in
                VecOps.applyRoPE(kPtr.baseAddress!, headDim: c.headDim,
                                 position: position, ropeFreqBase: c.ropeFreqBase, nHeads: c.nKVHeads)
            }

            // 5. Update KV cache
            keyCache[layer].append(contentsOf: k)
            valueCache[layer].append(contentsOf: v)

            // 6. Grouped-Query Attention
            let seqLen = position + 1
            let scale = 1.0 / sqrtf(Float(c.headDim))

            attnOut.withUnsafeMutableBufferPointer { aoPtr in
                memset(aoPtr.baseAddress!, 0, c.nHeads * c.headDim * MemoryLayout<Float>.size)
            }

            // Attention scores buffer
            var scores = [Float](repeating: 0, count: seqLen)

            for h in 0..<c.nHeads {
                let kvHead = h / c.nGQAGroups
                let qOffset = h * c.headDim

                // Compute attention scores for all positions
                scores.withUnsafeMutableBufferPointer { sPtr in
                    for pos in 0..<seqLen {
                        let kOffset = pos * c.nKVHeads * c.headDim + kvHead * c.headDim
                        q.withUnsafeBufferPointer { qPtr in
                            keyCache[layer].withUnsafeBufferPointer { kcPtr in
                                sPtr[pos] = VecOps.dot(qPtr.baseAddress! + qOffset,
                                                       kcPtr.baseAddress! + kOffset,
                                                       count: c.headDim) * scale
                            }
                        }
                    }

                    // Softmax over scores
                    VecOps.softmax(sPtr.baseAddress!, count: seqLen)

                    // Weighted sum of values
                    attnOut.withUnsafeMutableBufferPointer { aoPtr in
                        for pos in 0..<seqLen {
                            let vOffset = pos * c.nKVHeads * c.headDim + kvHead * c.headDim
                            valueCache[layer].withUnsafeBufferPointer { vcPtr in
                                // attnOut[h] += score[pos] * V[pos]
                                var s = sPtr[pos]
                                vDSP_vsma(vcPtr.baseAddress! + vOffset, 1, &s,
                                          aoPtr.baseAddress! + qOffset, 1,
                                          aoPtr.baseAddress! + qOffset, 1,
                                          vDSP_Length(c.headDim))
                            }
                        }
                    }
                }
            }

            // 7. Output projection
            var attnProjected = [Float](repeating: 0, count: c.embDim)
            attnOut.withUnsafeBufferPointer { aoPtr in
                w.wo.withUnsafeBufferPointer { woPtr in
                    attnProjected.withUnsafeMutableBufferPointer { pPtr in
                        VecOps.matvec(woPtr.baseAddress!, aoPtr.baseAddress!,
                                      pPtr.baseAddress!, rows: c.embDim, cols: c.nHeads * c.headDim)
                    }
                }
            }

            // 8. Residual connection
            hidden.withUnsafeMutableBufferPointer { hPtr in
                attnProjected.withUnsafeBufferPointer { aPtr in
                    VecOps.add(hPtr.baseAddress!, aPtr.baseAddress!, hPtr.baseAddress!, count: c.embDim)
                }
            }

            // 9. FFN Norm
            hidden.withUnsafeBufferPointer { hPtr in
                w.ffnNorm.withUnsafeBufferPointer { wPtr in
                    normed.withUnsafeMutableBufferPointer { nPtr in
                        VecOps.rmsNorm(hPtr.baseAddress!, wPtr.baseAddress!,
                                       nPtr.baseAddress!, count: c.embDim, eps: c.rmsNormEps)
                    }
                }
            }

            // 10. SwiGLU FFN: down(silu(gate(x)) * up(x))
            normed.withUnsafeBufferPointer { nPtr in
                w.wGate.withUnsafeBufferPointer { gPtr in
                    gate.withUnsafeMutableBufferPointer { gOut in
                        VecOps.matvec(gPtr.baseAddress!, nPtr.baseAddress!,
                                      gOut.baseAddress!, rows: c.ffnDim, cols: c.embDim)
                    }
                }
                w.wUp.withUnsafeBufferPointer { uPtr in
                    up.withUnsafeMutableBufferPointer { uOut in
                        VecOps.matvec(uPtr.baseAddress!, nPtr.baseAddress!,
                                      uOut.baseAddress!, rows: c.ffnDim, cols: c.embDim)
                    }
                }
            }

            // SiLU(gate) * up
            gate.withUnsafeBufferPointer { gPtr in
                siluBuf.withUnsafeMutableBufferPointer { sPtr in
                    VecOps.silu(gPtr.baseAddress!, sPtr.baseAddress!, count: c.ffnDim)
                }
            }
            siluBuf.withUnsafeMutableBufferPointer { sPtr in
                up.withUnsafeBufferPointer { uPtr in
                    VecOps.mul(sPtr.baseAddress!, uPtr.baseAddress!, sPtr.baseAddress!, count: c.ffnDim)
                }
            }

            // Down projection
            siluBuf.withUnsafeBufferPointer { sPtr in
                w.wDown.withUnsafeBufferPointer { dPtr in
                    ffnOut.withUnsafeMutableBufferPointer { fPtr in
                        VecOps.matvec(dPtr.baseAddress!, sPtr.baseAddress!,
                                      fPtr.baseAddress!, rows: c.embDim, cols: c.ffnDim)
                    }
                }
            }

            // 11. Residual connection
            hidden.withUnsafeMutableBufferPointer { hPtr in
                ffnOut.withUnsafeBufferPointer { fPtr in
                    VecOps.add(hPtr.baseAddress!, fPtr.baseAddress!, hPtr.baseAddress!, count: c.embDim)
                }
            }
        }

        // Final norm
        hidden.withUnsafeBufferPointer { hPtr in
            weights.outputNorm.withUnsafeBufferPointer { wPtr in
                normed.withUnsafeMutableBufferPointer { nPtr in
                    VecOps.rmsNorm(hPtr.baseAddress!, wPtr.baseAddress!,
                                   nPtr.baseAddress!, count: c.embDim, eps: c.rmsNormEps)
                }
            }
        }

        // Output projection (logits)
        let outWeight = weights.outputWeight ?? weights.tokenEmbedding
        var logits = [Float](repeating: 0, count: c.vocabSize)
        normed.withUnsafeBufferPointer { nPtr in
            outWeight.withUnsafeBufferPointer { wPtr in
                logits.withUnsafeMutableBufferPointer { lPtr in
                    VecOps.matvec(wPtr.baseAddress!, nPtr.baseAddress!,
                                  lPtr.baseAddress!, rows: c.vocabSize, cols: c.embDim)
                }
            }
        }

        cacheLength = position + 1
        return logits
    }
}
