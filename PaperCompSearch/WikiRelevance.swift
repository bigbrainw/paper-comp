import Foundation

struct WikiQueryContext: Sendable, Equatable {
    var term: String
    var paperTitle: String
    var brief: String?
    var selection: String
}

/// Wikipedia query building and relevance for on-device term lookup.
/// Bare acronym search hits unrelated articles (MQA → Master Quality Authenticated).
enum WikiRelevance {
    static let noGoodSource = "No good source found"
    static let topicKeywordLimit = 6

    /// `<term> <paper topic keywords>` for the search API (not a direct title lookup).
    static func query(_ context: WikiQueryContext) -> String {
        let topics = topicKeywords(title: context.paperTitle, brief: context.brief)
        let term = context.term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !topics.isEmpty else { return term }
        return "\(term) \(topics.joined(separator: " "))"
    }

    /// Distinctive words from the paper title and brief, e.g. "signal integrity EEG electrode".
    static func topicKeywords(title: String, brief: String?, limit: Int = topicKeywordLimit) -> [String] {
        let tokens = contentTokens(from: [title, brief ?? ""])
        let acronyms = tokens.filter(isAcronym)
        let long = tokens.filter { $0.count >= 6 && !isAcronym($0) }
        let rest = tokens.filter { $0.count < 6 && !isAcronym($0) }
        var seen = Set<String>()
        var result: [String] = []
        for token in acronyms + long + rest {
            let key = stem(token)
            guard seen.insert(key).inserted else { continue }
            result.append(token)
            if result.count == limit { break }
        }
        return result
    }

    /// Stems from the paper title, brief, and selection — excluding the looked-up term.
    /// Matching only the acronym would keep junk like "Master Quality Authenticated (MQA)".
    static func matchKeywords(_ context: WikiQueryContext) -> Set<String> {
        var keys = Set(stems(from: [context.paperTitle, context.brief ?? "", context.selection]))
        keys.remove(stem(context.term))
        for word in tokenize(context.term) {
            keys.remove(stem(word))
        }
        return keys
    }

    static func isRelevant(_ summary: WikiSummary, keywords: Set<String>) -> Bool {
        isRelevant(title: summary.title, extract: summary.extract, description: summary.description, keywords: keywords)
    }

    static func isRelevant(title: String, extract: String, description: String? = nil, keywords: Set<String>) -> Bool {
        if keywords.isEmpty { return true }
        let article = Set(stems(from: [title, description ?? "", extract]))
        return !article.isDisjoint(with: keywords)
    }

    static func pick(summaries: [WikiSummary], keywords: Set<String>) -> WikiSummary? {
        summaries.first { !$0.isDisambiguation && isRelevant($0, keywords: keywords) }
    }

    // MARK: - Tokenize / stem

    static func stems(from texts: [String]) -> [String] {
        contentTokens(from: texts).map(stem)
    }

    /// Light plural stem only: -ies → -y, -es after s/x/z/ch/sh, otherwise trailing -s.
    /// Both `matchKeywords` and article tokens go through this, so "electrodes" matches "electrode".
    static func stem(_ word: String) -> String {
        let w = word.lowercased()
        if w.hasSuffix("ies"), w.count > 4 {
            return String(w.dropLast(3)) + "y"
        }
        if w.hasSuffix("es"), w.count > 4, hasPluralESStem(w) {
            return String(w.dropLast(2))
        }
        if w.hasSuffix("s"), w.count > 3, !w.hasSuffix("ss") {
            return String(w.dropLast())
        }
        return w
    }

    /// boxes, classes, watches, dishes — not electrodes (that is just -s).
    private static func hasPluralESStem(_ word: String) -> Bool {
        let stem = word.dropLast(2)
        return stem.hasSuffix("s") || stem.hasSuffix("x") || stem.hasSuffix("z")
            || stem.hasSuffix("ch") || stem.hasSuffix("sh")
    }

    private static func contentTokens(from texts: [String]) -> [String] {
        var seen = Set<String>()
        var ordered: [String] = []
        for text in texts {
            for token in tokenize(text) {
                let key = stem(token)
                guard key.count >= 2, !stopwords.contains(key) else { continue }
                if seen.insert(key).inserted { ordered.append(token) }
            }
        }
        return ordered
    }

    static func tokenize(_ text: String) -> [String] {
        text.split { !$0.isLetter && !$0.isNumber }.map(String.init)
    }

    private static func isAcronym(_ token: String) -> Bool {
        let letters = token.filter(\.isLetter)
        return letters.count >= 2 && letters.count <= 6 && letters.allSatisfy(\.isUppercase)
    }

    private static let stopwords: Set<String> = [
        "a", "an", "the", "of", "and", "for", "in", "on", "to", "with", "from", "by",
        "or", "as", "at", "is", "are", "was", "were", "be", "been", "being",
        "this", "that", "these", "those", "it", "its", "we", "our", "they", "their",
        "using", "use", "used", "via", "into", "than", "then", "also", "such",
        "which", "when", "where", "what", "how", "not", "no", "new", "based",
        "paper", "study", "studies", "method", "methods", "approach", "result", "results",
        "between", "over", "under", "after", "before", "during", "without", "within",
        "among", "about", "more", "most", "other", "some", "any", "all", "each", "both",
        "can", "may", "will", "would", "should", "could", "vs", "et", "al",
        "fig", "figure", "table", "section", "high", "low", "first", "second",
        "toward", "towards", "through", "across", "per", "vs",
    ]
}
