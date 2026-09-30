import Foundation

struct BM25Index: Sendable {
    var chunks: [PaperChunk]
    var documentFrequencies: [String: Int]
    var averageLength: Double

    static let k1 = 1.2
    static let b = 0.75

    init(chunks: [PaperChunk]) {
        self.chunks = chunks
        let tokenized = chunks.map { BM25Index.tokenize($0.text) }
        var df: [String: Int] = [:]
        for tokens in tokenized {
            for term in Set(tokens) { df[term, default: 0] += 1 }
        }
        documentFrequencies = df
        let total = tokenized.reduce(0) { $0 + $1.count }
        averageLength = tokenized.isEmpty ? 0 : Double(total) / Double(tokenized.count)
    }

    func ranked(query: String, limit: Int = 3) -> [PaperChunk] {
        let terms = Self.tokenize(query)
        guard !terms.isEmpty, !chunks.isEmpty else { return Array(chunks.prefix(limit)) }
        let n = Double(chunks.count)
        let scored: [(PaperChunk, Double)] = chunks.map { chunk in
            let tokens = Self.tokenize(chunk.text)
            let length = Double(max(tokens.count, 1))
            var tf: [String: Int] = [:]
            for token in tokens { tf[token, default: 0] += 1 }
            var score = 0.0
            for term in terms {
                let f = Double(tf[term] ?? 0)
                guard f > 0 else { continue }
                let df = Double(documentFrequencies[term] ?? 0)
                let idf = log((n - df + 0.5) / (df + 0.5) + 1)
                let denom = f + Self.k1 * (1 - Self.b + Self.b * length / max(averageLength, 1))
                score += idf * (f * (Self.k1 + 1)) / denom
            }
            return (chunk, score)
        }
        return scored.sorted { $0.1 > $1.1 }.prefix(limit).map(\.0)
    }

    static func tokenize(_ text: String) -> [String] {
        text.lowercased()
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
            .filter { $0.count > 1 }
    }
}
