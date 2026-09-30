import Foundation

/// Per-term breakdown for the Explain chip. Small models stay on one concept at a time.
enum BreakdownMode {
    static let maxTerms = 3
    static let maxTokensPerTerm = 220
    static let fitTogetherMaxTokens = 160
    static let fitTogetherHeading = "How they fit together"

    static let metaPhrases = [
        "these terms",
        "this passage",
        "the passage",
        "the text describes",
    ]

    static let system = """
        You are a patient tutor helping a student read a research paper. \
        Teach the one term you are given. Do not restate the passage. \
        Never copy more than 6 consecutive words from the passage. \
        Use plain text; write math in Unicode (1/f, μV). Cite sources as [S1], [S2].
        """

    static let fewShot = """
        Example for the term "VDD":
        What it is: VDD is the positive supply voltage that powers the transistors in a chip.
        Analogy: It's the wall outlet the circuit plugs into so the parts can work.
        Why it's here: In this figure VDD is the rail that feeds the amplifiers so they can swing.
        """

    static let fitTogetherSystem = """
        You are a patient tutor. In 2–3 sentences, say how the explained terms work together \
        in THIS circuit or paper. Do not redefine each term. Do not say 'these terms' as a summary.
        """

    static func isMeta(_ text: String) -> Bool {
        let lower = text.lowercased()
        return metaPhrases.contains { lower.contains($0) }
    }

    static func isIncomplete(_ text: String) -> Bool {
        let lower = text.lowercased()
        let hasWhat = lower.contains("what it is")
        let hasAnalogy = lower.contains("analogy")
        let hasWhy = lower.contains("why it's here") || lower.contains("why it is here")
        return !(hasWhat && hasAnalogy && hasWhy)
    }

    static func shouldRegenerate(_ text: String) -> Bool {
        isMeta(text) || isIncomplete(text)
    }

    static func shouldRun(_ question: String) -> Bool {
        let q = question.lowercased()
        if q.hasPrefix("define") { return false }
        if q.contains("first-year") || q.contains("undergraduate") { return false }
        if q.contains("break down only:") { return true }
        if q.contains("breaking down") { return true }
        if q.contains("explain") { return true }
        return false
    }

    static func singleTerm(from question: String) -> String? {
        let marker = "break down only:"
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let range = trimmed.range(of: marker, options: .caseInsensitive) else { return nil }
        let term = trimmed[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
        return term.isEmpty ? nil : term
    }

    static func header(terms: [String]) -> String {
        TeachChipPrompt.explain(terms: terms)
    }

    static func sentences(in text: String, mentioning term: String) -> String {
        let chunks = text
            .replacingOccurrences(of: "\n", with: ". ")
            .split(whereSeparator: { ".!?".contains($0) })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let hits = chunks.filter { $0.localizedCaseInsensitiveContains(term) }
        let picked = hits.isEmpty ? chunks.prefix(2).joined(separator: ". ") : hits.joined(separator: ". ")
        return LookupFormat.trimmed(picked.isEmpty ? text : picked, to: 400)
    }

    static func user(
        term: String,
        sentences: String,
        wiki: String?,
        passage: String?,
        brief: String?,
        includesImage: Bool,
        retryMeta: Bool
    ) -> String {
        var parts: [String] = [fewShot]
        if let wiki, !wiki.isEmpty {
            parts.append("Sources:\n[S1] Wikipedia\n\(LookupFormat.trimmed(wiki, to: 500))")
        }
        if let brief, !brief.isEmpty {
            parts.append("Paper brief:\n\(LookupFormat.trimmed(brief, to: 400))")
        }
        if includesImage {
            parts.append("A crop of the selected region is attached as an image.")
        }
        if let passage, !passage.isEmpty {
            parts.append("From this paper:\n\(LookupFormat.trimmed(passage, to: 400))")
        }
        parts.append("The term appears here (do not repeat it):\n\"\"\"\n\(sentences)\n\"\"\"")
        parts.append("""
            Break down the term '\(term)' for a student reading this paper. Write exactly these three parts:
            What it is: 1–2 plain sentences, as if explaining to a first-year student. No jargon without defining it.
            Analogy: one everyday analogy.
            Why it's here: 1–2 sentences on what it does in THIS circuit/paper, pointing at the figure if relevant.
            Do not describe the passage or the terms as a group. Do not say 'these terms'.
            """)
        if retryMeta {
            parts.append("Explain the concept itself.")
        }
        return parts.joined(separator: "\n\n")
    }

    static func fitTogetherUser(terms: [String], sections: [String]) -> String {
        let blocks = zip(terms, sections).map { term, text in
            "### \(term)\n\(text)"
        }
        return """
            Terms: \(terms.joined(separator: " · "))

            \(blocks.joined(separator: "\n\n"))

            Write '\(fitTogetherHeading)' in 2–3 sentences on how they work together in this circuit or paper.
            """
    }

    static func assemble(terms: [String], sections: [String], fitTogether: String) -> String {
        var parts: [String] = []
        for (term, text) in zip(terms, sections) where !text.isEmpty {
            parts.append("### \(term)\n\(text)")
        }
        if !fitTogether.isEmpty {
            parts.append("### \(fitTogetherHeading)\n\(fitTogether)")
        }
        return parts.joined(separator: "\n\n")
    }
}
