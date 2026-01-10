import Foundation

final class Tokenizer {
    private var vocab: [String: Int] = [:]
    private var reverseVocab: [Int: String] = [:]
    private var merges: [(String, String)] = []
    private let specialTokens: [String: Int]

    private init(vocab: [String: Int], merges: [(String, String)], specialTokens: [String: Int]) {
        self.vocab = vocab
        self.reverseVocab = Dictionary(uniqueKeysWithValues: vocab.map { ($1, $0) })
        self.merges = merges
        self.specialTokens = specialTokens
    }

    static func load(for modelName: String) async throws -> Tokenizer {
        switch modelName {
        case "Llama-3.2-3B":
            return createLlama3Tokenizer()
        case "Phi-3-mini-4k":
            return createPhi3Tokenizer()
        case "Mistral-7B":
            return createMistralTokenizer()
        default:
            return createDefaultTokenizer()
        }
    }

    private static func createLlama3Tokenizer() -> Tokenizer {
        var vocab: [String: Int] = [:]
        let specialTokens: [String: Int] = [
            "<|begin_of_text|>": 128000,
            "<|end_of_text|>": 128001,
            "<|start_header_id|>": 128006,
            "<|end_header_id|>": 128007,
            "<|eot_id|>": 128009
        ]

        for i in 0..<256 {
            vocab[String(UnicodeScalar(i)!)] = i
        }

        for (token, id) in specialTokens {
            vocab[token] = id
        }

        return Tokenizer(vocab: vocab, merges: [], specialTokens: specialTokens)
    }

    private static func createPhi3Tokenizer() -> Tokenizer {
        var vocab: [String: Int] = [:]
        let specialTokens: [String: Int] = [
            "<|system|>": 32001,
            "<|user|>": 32002,
            "<|assistant|>": 32003,
            "<|end|>": 32000,
            "<unk>": 0,
            "<s>": 1,
            "</s>": 2
        ]

        for i in 0..<256 {
            vocab[String(UnicodeScalar(i)!)] = i
        }

        for (token, id) in specialTokens {
            vocab[token] = id
        }

        return Tokenizer(vocab: vocab, merges: [], specialTokens: specialTokens)
    }

    private static func createMistralTokenizer() -> Tokenizer {
        var vocab: [String: Int] = [:]
        let specialTokens: [String: Int] = [
            "<unk>": 0,
            "<s>": 1,
            "</s>": 2,
            "[INST]": 3,
            "[/INST]": 4
        ]

        for i in 0..<256 {
            vocab[String(UnicodeScalar(i)!)] = i
        }

        for (token, id) in specialTokens {
            vocab[token] = id
        }

        return Tokenizer(vocab: vocab, merges: [], specialTokens: specialTokens)
    }

    private static func createDefaultTokenizer() -> Tokenizer {
        var vocab: [String: Int] = [:]

        for i in 0..<256 {
            vocab[String(UnicodeScalar(i)!)] = i
        }

        return Tokenizer(vocab: vocab, merges: [], specialTokens: [:])
    }

    func encode(_ text: String) -> [Int] {
        var tokens: [Int] = []
        var currentPos = text.startIndex

        while currentPos < text.endIndex {
            var matched = false

            for (specialToken, tokenId) in specialTokens.sorted(by: { $0.key.count > $1.key.count }) {
                if text[currentPos...].hasPrefix(specialToken) {
                    tokens.append(tokenId)
                    currentPos = text.index(currentPos, offsetBy: specialToken.count)
                    matched = true
                    break
                }
            }

            if !matched {
                let char = String(text[currentPos])
                if let tokenId = vocab[char] {
                    tokens.append(tokenId)
                } else {
                    for byte in char.utf8 {
                        tokens.append(Int(byte))
                    }
                }
                currentPos = text.index(after: currentPos)
            }
        }

        return tokens
    }

    func decode(_ tokens: [Int]) -> String {
        var result = ""
        var bytes: [UInt8] = []

        for tokenId in tokens {
            if specialTokens.first(where: { $0.value == tokenId }) != nil {
                if !bytes.isEmpty {
                    if let str = String(bytes: bytes, encoding: .utf8) {
                        result += str
                    }
                    bytes = []
                }
                continue
            }

            if let token = reverseVocab[tokenId] {
                if token.count == 1, let scalar = token.unicodeScalars.first, scalar.value < 256 {
                    bytes.append(UInt8(scalar.value))
                } else {
                    if !bytes.isEmpty {
                        if let str = String(bytes: bytes, encoding: .utf8) {
                            result += str
                        }
                        bytes = []
                    }
                    result += token
                }
            } else if tokenId < 256 {
                bytes.append(UInt8(tokenId))
            }
        }

        if !bytes.isEmpty {
            if let str = String(bytes: bytes, encoding: .utf8) {
                result += str
            }
        }

        return result
    }

    func countTokens(_ text: String) -> Int {
        return encode(text).count
    }
}

extension Tokenizer {
    static func loadFromFile(at url: URL) async throws -> Tokenizer {
        let data = try Data(contentsOf: url)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        guard let vocabDict = json?["vocab"] as? [String: Int] else {
            throw TokenizerError.invalidFormat
        }

        var merges: [(String, String)] = []
        if let mergesArray = json?["merges"] as? [String] {
            for merge in mergesArray {
                let parts = merge.split(separator: " ")
                if parts.count == 2 {
                    merges.append((String(parts[0]), String(parts[1])))
                }
            }
        }

        let specialTokens = json?["special_tokens"] as? [String: Int] ?? [:]

        return Tokenizer(vocab: vocabDict, merges: merges, specialTokens: specialTokens)
    }
}

enum TokenizerError: Error {
    case invalidFormat
    case fileNotFound
}
