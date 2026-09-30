import Foundation

/// Prompt for on-device summarization over pre-fetched sources (no tool calling).
enum LocalPromptBuilder {
    enum Kind: Equatable, Sendable {
        case lookup
        case teach
    }

    static let system = """
        You are a research assistant helping someone read a paper. \
        Answer the user's question directly, with the answer in the first sentence. \
        Explain the concept itself, using the sources and the paper. \
        Never describe or summarize 'the surrounding text' or 'the circled text'. \
        If the selection is a term, define it and say why it matters in this paper. \
        Use plain text, and write math in Unicode rather than LaTeX. \
        Cite fetched web or paper sources as [S1], [S2] matching the numbered Sources. \
        Cite this paper's own references as [22] or (Author Year). Never use [1] for a web source.
        """

    static let teachingSystem = """
        You are a patient tutor helping a student read a research paper. \
        The student selected a passage and doesn't understand part of it. \
        Teach the concept; don't restate the passage. Rules: \
        (1) Never copy more than 6 consecutive words from the passage. \
        (2) Start with a one-sentence plain-language answer. \
        (3) Then explain the underlying idea from first principles, using a simple analogy if helpful. \
        (4) Then say in 1–2 sentences what it means in this paper. \
        (5) Use plain text; write math in Unicode (1/f, μV). \
        (6) Cite sources as [S1], [S2].
        Output format:
        **In short:** …
        **The idea:** …
        **In this paper:** …
        """

    /// Under 150 tokens. Small models copy format better than rules.
    static let oneShotExample = """
        Example
        Selected passage (do not repeat it): "The LNA's input-referred noise sets the noise floor."
        Hard terms: input-referred noise
        **In short:** Input-referred noise is the equivalent noise as if it all sat at the input.
        **The idea:** Imagine a quiet microphone and a hissy amp; we quote the hiss as sound at the mic so designs compare fairly.
        **In this paper:** It tells you how small a signal this front-end can still see.
        """

    struct SourceSnippet: Equatable, Sendable {
        let index: Int
        let title: String
        let body: String
    }

    static func build(
        paperTitle: String,
        circledText: String,
        surroundingText: String,
        question: String,
        snippets: [SourceSnippet],
        includesImage: Bool = false,
        paperBrief: String? = nil,
        passages: [PaperChunk] = [],
        references: [PaperReference] = [],
        kind: Kind = .lookup,
        terms: [String] = [],
        retryCopied: Bool = false
    ) -> (system: String, user: String) {
        let selected = LookupFormat.trimmed(circledText, to: 600)
        let context = LocalPrompt.trimmedContext(surroundingText, around: selected)
        var userParts: [String] = []
        userParts.append("Paper: \(paperTitle.isEmpty ? "Unknown title" : paperTitle)")
        if kind == .teach {
            userParts.append(oneShotExample)
        }
        if !snippets.isEmpty {
            let blocks = snippets.prefix(3).map { snippet in
                let body = LookupFormat.trimmed(snippet.body, to: 600)
                return "[S\(snippet.index)] \(snippet.title)\n\(body)"
            }
            userParts.append("Sources:\n" + blocks.joined(separator: "\n\n"))
        }
        if let paperBrief, !paperBrief.isEmpty {
            userParts.append("Paper brief:\n\(LookupFormat.trimmed(paperBrief, to: 700))")
        }
        if includesImage {
            userParts.append("A crop of the selected region is attached as an image.")
        }
        if !passages.isEmpty {
            let blocks = passages.prefix(3).map { chunk in
                "p.\(chunk.pageIndex + 1) \(LookupFormat.trimmed(chunk.text, to: 500))"
            }
            userParts.append("From this paper:\n" + blocks.joined(separator: "\n\n"))
        }
        if !references.isEmpty {
            let blocks = references.prefix(4).map { ref in
                let title = ref.title.map { " — \($0)" } ?? ""
                return "[\(ref.marker)] \(ref.raw.prefix(280))\(title)"
            }
            userParts.append("Cited references:\n" + blocks.joined(separator: "\n"))
        }
        userParts.append(selected.isEmpty
            ? "Selected passage (do not repeat it): a figure or image with no readable text."
            : "Selected passage (do not repeat it):\n\"\"\"\n\(selected)\n\"\"\"")
        if !context.isEmpty {
            userParts.append("Paper context:\n\"\"\"\n\(context)\n\"\"\"")
        }
        if !terms.isEmpty {
            userParts.append("Hard terms: \(terms.joined(separator: " · "))")
        }
        userParts.append("Question: \(question)")
        if retryCopied {
            userParts.append(CopyGuard.retryLine)
        }
        return (kind == .teach ? teachingSystem : system, userParts.joined(separator: "\n\n"))
    }
}

enum TeachChipPrompt {
    static func explain(terms: [String]) -> String {
        let cleaned = usable(terms)
        if cleaned.isEmpty {
            return "Breaking down the hard concepts in this figure"
        }
        return "Breaking down: \(cleaned.joined(separator: " · "))"
    }

    static func termOnly(_ term: String) -> String {
        "Break down only: \(term)"
    }

    static func define(terms: [String]) -> String {
        let cleaned = usable(terms)
        if cleaned.isEmpty {
            return "Define the terms in this passage in plain language."
        }
        return "Define \(cleaned.joined(separator: ", ")) in plain language."
    }

    static func simpler() -> String {
        "Explain this passage to a first-year undergraduate, with an analogy."
    }

    /// Drops empty strings and leaked detector placeholders so they never reach the UI.
    static func displayed(_ question: String) -> String {
        let lower = question.lowercased()
        if lower.contains("the hard concepts here")
            || lower.contains("explain the concepts in this passage") {
            return explain(terms: [])
        }
        if lower.contains("the key terms in this passage") {
            return define(terms: [])
        }
        return question
    }

    private static func usable(_ terms: [String]) -> [String] {
        terms
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !HardTermDetector.isPlaceholder($0) }
    }
}

/// Shared context trimming (also used in tests).
enum LocalPrompt {
    static func trimmedContext(_ context: String, around snippet: String, limit: Int = 800) -> String {
        let context = context.collapsedWhitespace
        guard context.count > limit else { return context }
        var center = context.count / 2
        let probe = String(snippet.collapsedWhitespace.prefix(60))
        if !probe.isEmpty, let range = context.range(of: probe) {
            center = context.distance(from: context.startIndex, to: range.lowerBound) + min(snippet.count, limit) / 2
        }
        let start = max(0, min(center - limit / 2, context.count - limit))
        let lower = context.index(context.startIndex, offsetBy: start)
        let upper = context.index(lower, offsetBy: limit)
        return (start > 0 ? "…" : "") + context[lower..<upper] + (upper < context.endIndex ? "…" : "")
    }
}
