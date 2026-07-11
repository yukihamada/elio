import Foundation

// MARK: - BPE Tokenizer
// Pure Swift BPE tokenizer compatible with GGUF tokenizer metadata (GPT-2/Qwen style)

final class BPETokenizer {
    let vocab: [String]             // token_id -> string
    let vocabToId: [String: Int]    // string -> token_id
    let merges: [(String, String)]  // BPE merge pairs in priority order
    let mergeRanks: [String: Int]   // "a b" -> rank (lower = higher priority)
    let eosTokenId: Int
    let bosTokenId: Int?
    let addBosToken: Bool

    // Special tokens
    private let byteTokens: [UInt8: Int]  // byte value -> token_id for byte-level fallback

    init(gguf: GGUFFile) {
        // Extract vocab
        var tokens: [String] = []
        if case .array(let arr) = gguf.metadata["tokenizer.ggml.tokens"] ?? .uint32(0) {
            tokens = arr.compactMap { $0.asString }
        }
        self.vocab = tokens

        // Build reverse lookup
        var v2i: [String: Int] = [:]
        v2i.reserveCapacity(tokens.count)
        for (i, t) in tokens.enumerated() {
            v2i[t] = i
        }
        self.vocabToId = v2i

        // Extract merges
        var mergePairs: [(String, String)] = []
        var ranks: [String: Int] = [:]
        if case .array(let arr) = gguf.metadata["tokenizer.ggml.merges"] ?? .uint32(0) {
            for (i, val) in arr.enumerated() {
                if let s = val.asString {
                    let parts = s.split(separator: " ", maxSplits: 1)
                    if parts.count == 2 {
                        let pair = (String(parts[0]), String(parts[1]))
                        mergePairs.append(pair)
                        ranks[s] = i
                    }
                }
            }
        }
        self.merges = mergePairs
        self.mergeRanks = ranks

        // EOS/BOS
        self.eosTokenId = gguf.metadata["tokenizer.ggml.eos_token_id"]?.asInt ?? 151645
        self.bosTokenId = gguf.metadata["tokenizer.ggml.bos_token_id"]?.asInt
        self.addBosToken = gguf.metadata["tokenizer.ggml.add_bos_token"]?.asBool ?? false

        // Build byte token map for GPT-2 style byte-level BPE
        var bt: [UInt8: Int] = [:]
        for (i, t) in tokens.enumerated() {
            if t.count == 6 && t.hasPrefix("<0x") && t.hasSuffix(">") {
                let hex = String(t.dropFirst(3).dropLast(1))
                if let byte = UInt8(hex, radix: 16) {
                    bt[byte] = i
                }
            }
        }
        self.byteTokens = bt
    }

    // MARK: - Encoding

    func encode(_ text: String) -> [Int] {
        guard !text.isEmpty else { return [] }

        var tokens: [Int] = []
        if addBosToken, let bos = bosTokenId {
            tokens.append(bos)
        }

        // GPT-2 style: pre-tokenize with regex, then BPE each piece
        let pieces = preTokenize(text)
        for piece in pieces {
            let pieceTokens = bpeEncode(piece)
            tokens.append(contentsOf: pieceTokens)
        }

        return tokens
    }

    // MARK: - Decoding

    func decode(_ tokenIds: [Int]) -> String {
        var result = ""
        for id in tokenIds {
            guard id >= 0 && id < vocab.count else { continue }
            let token = vocab[id]
            result += decodeToken(token)
        }
        return result
    }

    func decodeToken(_ token: String) -> String {
        // Handle byte tokens
        if token.hasPrefix("<0x") && token.hasSuffix(">") {
            let hex = String(token.dropFirst(3).dropLast(1))
            if let byte = UInt8(hex, radix: 16) {
                return String(UnicodeScalar(byte))
            }
        }
        // GPT-2 byte encoding: Ġ -> space, Ċ -> newline, etc.
        return gpt2ByteDecode(token)
    }

    func decode(tokenId: Int) -> String {
        guard tokenId >= 0 && tokenId < vocab.count else { return "" }
        return decodeToken(vocab[tokenId])
    }

    // MARK: - Pre-tokenization (GPT-2 regex pattern)

    private func preTokenize(_ text: String) -> [String] {
        // Simplified GPT-2 pre-tokenization: split on whitespace boundaries
        // The actual GPT-2 pattern: 's|'t|'re|'ve|'m|'ll|'d| ?\p{L}+| ?\p{N}+| ?[^\s\p{L}\p{N}]+|\s+
        // We use a simplified version that handles most cases
        var pieces: [String] = []
        var current = ""

        let chars = Array(text)
        var i = 0
        while i < chars.count {
            let ch = chars[i]

            if ch == " " || ch == "\t" || ch == "\n" || ch == "\r" {
                if !current.isEmpty {
                    pieces.append(current)
                    current = ""
                }
                // Include whitespace as prefix of next token (GPT-2 style)
                current = String(ch)
                i += 1
                // Consume following non-whitespace
                while i < chars.count && chars[i] != " " && chars[i] != "\t" && chars[i] != "\n" && chars[i] != "\r" {
                    current.append(chars[i])
                    i += 1
                }
                if !current.isEmpty {
                    pieces.append(current)
                    current = ""
                }
            } else {
                current.append(ch)
                i += 1
            }
        }
        if !current.isEmpty {
            pieces.append(current)
        }

        return pieces
    }

    // MARK: - BPE core

    private func bpeEncode(_ piece: String) -> [Int] {
        // Convert to GPT-2 byte-encoded representation
        let encoded = gpt2ByteEncode(piece)

        // Split into individual characters (as strings)
        var symbols = encoded.map { String($0) }

        if symbols.count <= 1 {
            // Single character - look up directly
            if let id = vocabToId[encoded] {
                return [id]
            }
            // Fallback to byte tokens
            return piece.utf8.compactMap { byteTokens[$0] }
        }

        // Iteratively apply BPE merges
        while symbols.count > 1 {
            // Find the pair with the lowest merge rank
            var bestRank = Int.max
            var bestIdx = -1

            for i in 0..<symbols.count - 1 {
                let pair = "\(symbols[i]) \(symbols[i+1])"
                if let rank = mergeRanks[pair], rank < bestRank {
                    bestRank = rank
                    bestIdx = i
                }
            }

            if bestIdx < 0 { break } // No more merges possible

            // Apply the merge
            let merged = symbols[bestIdx] + symbols[bestIdx + 1]
            symbols[bestIdx] = merged
            symbols.remove(at: bestIdx + 1)
        }

        // Convert symbols to token IDs
        var ids: [Int] = []
        for sym in symbols {
            if let id = vocabToId[sym] {
                ids.append(id)
            } else {
                // Fallback: encode as individual bytes
                for byte in sym.utf8 {
                    let byteToken = String(format: "<0x%02X>", byte)
                    if let id = vocabToId[byteToken] {
                        ids.append(id)
                    }
                }
            }
        }
        return ids
    }

    // MARK: - GPT-2 Byte Encoding

    /// GPT-2 maps bytes to unicode characters to avoid whitespace/control issues
    private static let byteEncoder: [UInt8: Character] = {
        var be: [UInt8: Character] = [:]
        var n = 0
        // Printable ASCII range (except space which maps to Ġ)
        for b in UInt8(33)...UInt8(126) { be[b] = Character(UnicodeScalar(b)); n += 1 }
        for b in UInt8(161)...UInt8(172) { be[b] = Character(UnicodeScalar(b)); n += 1 }
        for b in UInt8(174)...UInt8(255) { be[b] = Character(UnicodeScalar(b)); n += 1 }
        // Map remaining bytes to Unicode range starting at 256
        var offset = 256
        for b in UInt8(0)...UInt8(255) {
            if be[b] == nil {
                be[b] = Character(UnicodeScalar(offset)!)
                offset += 1
            }
        }
        return be
    }()

    private static let byteDecoder: [Character: UInt8] = {
        var bd: [Character: UInt8] = [:]
        for (k, v) in byteEncoder {
            bd[v] = k
        }
        return bd
    }()

    private func gpt2ByteEncode(_ text: String) -> String {
        String(text.utf8.map { Self.byteEncoder[$0] ?? Character(UnicodeScalar($0)) })
    }

    private func gpt2ByteDecode(_ token: String) -> String {
        let bytes = token.map { Self.byteDecoder[$0] ?? UInt8($0.asciiValue ?? 0) }
        return String(bytes: bytes, encoding: .utf8) ?? token
    }
}
