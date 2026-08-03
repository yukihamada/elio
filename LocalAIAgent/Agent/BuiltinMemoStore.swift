import Foundation

// MARK: - Memo Tool (Persistent memory with BM25 vector search)
// Ported from NOU app. Provides long-term memory for the ToolRouter.

actor BuiltinMemoStore {
    static let shared = BuiltinMemoStore()

    private struct Memo: Codable {
        let content: String
        let timestamp: Date
        let tokens: [String]  // Pre-tokenized for search
    }

    private var memos: [Memo] = []
    private let maxMemos = 100
    private let storageURL: URL

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        storageURL = docs.appendingPathComponent("elio_memos.json")
        load()
    }

    // MARK: - Save

    func save(content: String) -> String {
        let tokens = tokenize(content)
        let memo = Memo(content: content, timestamp: Date(), tokens: tokens)
        memos.append(memo)
        if memos.count > maxMemos {
            memos = Array(memos.suffix(maxMemos))
        }
        persist()
        return "Saved: \(content.prefix(50))... (\(memos.count) memos total)"
    }

    // MARK: - Search (BM25-based)

    func search(query: String, topK: Int = 3) -> String {
        guard !memos.isEmpty else { return "No memos saved yet." }

        let queryTokens = tokenize(query)
        let querySet = Set(queryTokens)

        // IDF calculation
        var docFreq: [String: Int] = [:]
        for memo in memos {
            for token in Set(memo.tokens) {
                docFreq[token, default: 0] += 1
            }
        }
        let n = Double(memos.count)

        // BM25 scoring
        let k1 = 1.5
        let b = 0.75
        let avgDL = memos.map { Double($0.tokens.count) }.reduce(0, +) / n

        var scores: [(index: Int, score: Double)] = []
        for (i, memo) in memos.enumerated() {
            var score = 0.0
            let dl = Double(memo.tokens.count)
            let termFreqs = Dictionary(memo.tokens.map { ($0, 1) }, uniquingKeysWith: +)

            for qToken in querySet {
                guard let df = docFreq[qToken], df > 0 else { continue }
                let idf = log((n - Double(df) + 0.5) / (Double(df) + 0.5) + 1)
                let tf = Double(termFreqs[qToken] ?? 0)
                let tfNorm = (tf * (k1 + 1)) / (tf + k1 * (1 - b + b * dl / avgDL))
                score += idf * tfNorm
            }
            if score > 0 { scores.append((i, score)) }
        }

        let topResults = scores.sorted { $0.score > $1.score }.prefix(topK)
        if topResults.isEmpty { return "No relevant memos found for: \(query)" }

        let df = DateFormatter()
        df.dateStyle = .short; df.timeStyle = .short

        return topResults.map { item in
            let memo = memos[item.index]
            return "[\(df.string(from: memo.timestamp))] \(memo.content)"
        }.joined(separator: "\n\n")
    }

    // MARK: - List recent

    func listRecent(n: Int = 5) -> String {
        guard !memos.isEmpty else { return "No memos saved yet." }
        let df = DateFormatter()
        df.dateStyle = .short; df.timeStyle = .short
        return memos.suffix(n).map { "[\(df.string(from: $0.timestamp))] \($0.content)" }.joined(separator: "\n")
    }

    // MARK: - Tokenization (simple but effective)

    private func tokenize(_ text: String) -> [String] {
        text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 1 }
    }

    // MARK: - Persistence

    private func persist() {
        guard let data = try? JSONEncoder().encode(memos) else { return }
        try? data.write(to: storageURL, options: .atomic)
    }

    private func load() {
        guard let data = try? Data(contentsOf: storageURL),
              let saved = try? JSONDecoder().decode([Memo].self, from: data) else { return }
        memos = saved
    }
}
