import Foundation

/// Fraction of 6-word n-grams in the answer that also appear in the passage/context.
enum CopyGuard {
    static let n = 6
    static let retryThreshold = 0.30
    static let retryLine = "Your previous answer copied the passage. Explain in your own words."

    static func ratio(answer: String, against sources: [String]) -> Double {
        let answerGrams = ngrams(answer)
        guard !answerGrams.isEmpty else { return 0 }
        let sourceGrams = Set(sources.flatMap { ngrams($0) })
        let hits = answerGrams.filter { sourceGrams.contains($0) }.count
        return Double(hits) / Double(answerGrams.count)
    }

    static func copies(_ answer: String, against sources: [String]) -> Bool {
        ratio(answer: answer, against: sources) > retryThreshold
    }

    static func ngrams(_ text: String, n: Int = n) -> [String] {
        let words = words(in: text)
        guard words.count >= n else { return [] }
        return (0...(words.count - n)).map { words[$0..<($0 + n)].joined(separator: " ") }
    }

    static func words(in text: String) -> [String] {
        text.lowercased()
            .split { !$0.isLetter && !$0.isNumber && $0 != "/" && $0 != "-" }
            .map(String.init)
            .filter { !$0.isEmpty }
    }
}
