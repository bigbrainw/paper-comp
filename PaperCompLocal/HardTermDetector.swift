import Foundation

/// Step A of the teach pipeline: pick 1–3 terms a student would not know.
enum HardTermDetector {
    static let userPrompt = """
        List the 1–3 technical terms or ideas in this passage that a student would most likely not understand. \
        Output one per line, no explanation.
        """

    static let system = "Output 1–3 technical terms, one per line, nothing else."

    private static let common: Set<String> = [
        "the", "a", "an", "is", "are", "was", "were", "be", "been", "being",
        "to", "of", "in", "for", "on", "with", "as", "by", "at", "from",
        "that", "this", "these", "those", "it", "its", "or", "and", "but",
        "not", "no", "if", "then", "than", "so", "such", "can", "may",
        "will", "would", "should", "could", "typically", "mitigated",
        "using", "used", "use", "into", "over", "under", "about",
        "paper", "section", "figure", "shown", "show", "see", "called",
        "known", "also", "more", "most", "other", "some", "any",
        "here", "there", "when", "where", "what", "which", "who",
    ]

    static func parse(_ output: String) -> [String] {
        output
            .split(whereSeparator: \.isNewline)
            .map { cleanLine(String($0)) }
            .filter { !$0.isEmpty && !isCommon($0) && !isPlaceholder($0) }
            .prefix(3)
            .map { String($0) }
    }

    /// Parsed terms that really appear in `passage` and aren't leaked reasoning; falls back to the passage.
    static func terms(from output: String, passage: String) -> [String] {
        let lines = ThinkingStrip.strip(output)
            .split(whereSeparator: \.isNewline)
            .map { cleanLine(String($0)) }
            .filter { !$0.isEmpty && !isCommon($0) && !isPlaceholder($0) }
        let kept = lines.filter { !isReasoning($0) && occurs($0, in: passage) }
        return kept.isEmpty ? fallback(from: passage) : Array(kept.prefix(3))
    }

    private static let reasoningOpeners = [
        "okay", "ok,", "first,", "first i ", "let me", "let's", "the user", "i need", "i will", "i'll", "so,", "hmm", "wait,",
    ]

    /// Sentence-like lines ("Okay, let's see. The user wants…", "First, I need to") are not terms.
    static func isReasoning(_ line: String) -> Bool {
        let lower = line.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if lower.contains("<") || lower.hasSuffix(":") || lower.hasSuffix(".") { return true }
        if lower.split(separator: " ").count > 6 { return true }
        return reasoningOpeners.contains { lower.hasPrefix($0) }
    }

    private static func normalized(_ text: String) -> String {
        text.lowercased()
            .replacingOccurrences(of: #"[^\p{L}\p{N}/]+"#, with: " ", options: .regularExpression)
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    static func occurs(_ term: String, in passage: String) -> Bool {
        let needle = normalized(term)
        // Whole-word match so "IA" doesn't hit "via".
        return !needle.isEmpty && " \(normalized(passage)) ".contains(" \(needle) ")
    }

    static func isPlaceholder(_ term: String) -> Bool {
        let lower = term.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return lower.contains("hard concepts here")
            || lower.contains("key terms in this passage")
            || lower == "hard concepts"
            || lower == "key terms"
    }

    static func isCommon(_ term: String) -> Bool {
        let words = term.split { !$0.isLetter && !$0.isNumber && $0 != "/" && $0 != "-" }.map(String.init)
        if words.isEmpty { return true }
        return words.allSatisfy { word in
            let lower = word.lowercased()
            // Two-letter acronyms ("IA") are terms; other short words are filler.
            let isAcronym = word.count == 2 && word.allSatisfy(\.isUppercase)
            return common.contains(lower) || lower.count <= 2 && lower != "1/f" && !isAcronym
        }
    }

    /// When the model returns nothing useful, keep technical-looking phrases from the passage.
    static func fallback(from selection: String) -> [String] {
        var terms: [String] = []
        if let flicker = selection.firstMatch(of: #/1\/f(?:\s+noise)?/#) {
            terms.append(String(flicker.0))
        }
        for phrase in selection.split(whereSeparator: { ",;.".contains($0) }) {
            let cleaned = cleanLine(String(phrase))
            guard !cleaned.isEmpty, !isCommon(cleaned) else { continue }
            let words = cleaned.split(separator: " ")
            if words.count >= 2, words.count <= 6, !terms.contains(cleaned) {
                terms.append(cleaned)
            }
        }
        if terms.isEmpty {
            terms = parse(selection.replacingOccurrences(of: ". ", with: "\n"))
        }
        return Array(terms.filter { !isPlaceholder($0) }.prefix(3))
    }

    private static func cleanLine(_ line: String) -> String {
        var text = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if let numbered = text.firstMatch(of: #/^\d+[.)\:]\s+/#) {
            text = String(text[numbered.range.upperBound...])
        } else if text.hasPrefix("- ") || text.hasPrefix("* ") || text.hasPrefix("• ") {
            text = String(text.dropFirst(2))
        }
        text = text.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("\"") && text.hasSuffix("\"") && text.count > 2 {
            text = String(text.dropFirst().dropLast())
        }
        return text
    }
}
