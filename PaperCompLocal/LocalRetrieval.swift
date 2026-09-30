import Foundation

enum SearchRetrievalIntent: Equatable, Sendable {
    case defineExplain
    case citedPaper
    case relatedWork
    case freeQuestion
    case readLink

    static func from(question: String) -> SearchRetrievalIntent {
        let q = question.lowercased()
        if q.contains("read this link") { return .readLink }
        if q.contains("cited paper") || q.contains("identify the paper cited") { return .citedPaper }
        if q.contains("related work") || q.contains("is there evidence") { return .relatedWork }
        if q.contains("define") || q.contains("explain") || q.contains("simpler")
            || q.contains("breaking down") || q.contains("break down") {
            return .defineExplain
        }
        return .freeQuestion
    }
}

enum CitationQueryExtractor {
    /// Best-effort query for Semantic Scholar from circled citation text.
    static func query(from circledText: String) -> String {
        let text = circledText.collapsedWhitespace
        if text.isEmpty { return text }
        if let quoted = firstQuotedSubstring(in: text) { return quoted }
        let withoutParens = text.replacing(#/\(\d{4}[a-z]?\)/#, with: "")
        let trimmed = withoutParens.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count >= 12 { return String(trimmed.prefix(200)) }
        return text
    }

    static func keyPhrase(from circledText: String, fallback: String) -> String {
        let trimmed = circledText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            let line = trimmed.split(separator: "\n", omittingEmptySubsequences: true).first.map(String.init) ?? trimmed
            return String(line.prefix(120))
        }
        return String(fallback.prefix(120))
    }

    private static func firstQuotedSubstring(in text: String) -> String? {
        let patterns = [#/"([^"]{8,})"/#, #/"([^']{8,})'/#]
        for pattern in patterns {
            if let match = text.firstMatch(of: pattern) {
                return String(match.1)
            }
        }
        return nil
    }
}

enum LocalRetrieval {
    /// Wikipedia + paper passages for the detected hard terms only.
    static func fetchTerms(
        _ terms: [String],
        paper: PaperIndexRecord?,
        paperTitle: String = "",
        selection: String = "",
        lookup: KeylessLookup
    ) async -> (snippets: [LocalPromptBuilder.SourceSnippet], sources: [WebSource], passages: [PaperChunk], note: String?) {
        var results: [LookupResult] = []
        var labels: [String] = []
        let title = paperTitleForQuery(paper, fallback: paperTitle)
        for term in terms.prefix(3) {
            let wiki = await lookup.wikipedia(WikiQueryContext(
                term: term,
                paperTitle: title,
                brief: paper?.brief,
                selection: selection
            ))
            results.append(wiki)
            labels.append(term)
        }
        let base = await expanded(snippets(from: results, labels: labels), lookup: lookup, query: terms.joined(separator: " "))
        let query = terms.joined(separator: " ")
        let passages = paper.map { PaperIndexQuery.passages(in: $0, selection: query, question: "") } ?? []
        return (base.0, base.1, passages, wikiNote(results))
    }

    static func fetch(
        intent: SearchRetrievalIntent,
        query: String,
        paper: PaperIndexRecord? = nil,
        paperTitle: String = "",
        selection: String = "",
        lookup: KeylessLookup
    ) async -> (snippets: [LocalPromptBuilder.SourceSnippet], sources: [WebSource], note: String?) {
        let wikiContext = WikiQueryContext(
            term: query,
            paperTitle: paperTitleForQuery(paper, fallback: paperTitle),
            brief: paper?.brief,
            selection: selection.isEmpty ? query : selection
        )
        switch intent {
        case .readLink:
            if let url = LinkDetector.urlOrDOI(in: query) {
                let source = WebSource(title: url.host() ?? "Link", url: url)
                let body = await LinkContentFetcher.fetch(source: source, lookup: lookup, query: query)
                return ([.init(index: 1, title: source.title, body: body.isEmpty ? "Could not read that link." : body)], [source], nil)
            }
            return ([], [], nil)
        case .defineExplain:
            let wiki = await lookup.wikipedia(wikiContext)
            return pack(note: wiki.note, await expanded(snippets(from: [wiki], labels: ["Wikipedia"]), lookup: lookup, query: query))
        case .citedPaper:
            let consensus = await ConsensusSearch.lookupResult(query: query)
            if !consensus.sources.isEmpty {
                return pack(note: consensus.note, await expanded(snippets(from: [consensus], labels: ["Consensus"]), lookup: lookup, query: query))
            }
            let papers = await lookup.paperSearch(query)
            return pack(note: consensus.note, await expanded(snippets(from: [papers], labels: ["Papers"]), lookup: lookup, query: query))
        case .relatedWork:
            let consensus = await ConsensusSearch.lookupResult(query: query)
            let search = await lookup.paperSearch(query)
            var combined = merge(consensus, search)
            if let first = firstPaperID(in: combined.text) {
                let related = await lookup.relatedPapers(first)
                combined = merge(combined, related)
            }
            return pack(note: consensus.note, await expanded(snippets(from: [combined], labels: ["Related work"]), lookup: lookup, query: query))
        case .freeQuestion:
            async let wiki = lookup.wikipedia(wikiContext)
            async let papers = lookup.paperSearch(query)
            let results = await [wiki, papers]
            return pack(note: wikiNote(results), await expanded(snippets(from: results, labels: ["Wikipedia", "Papers"]), lookup: lookup, query: query))
        }
    }

    private static func paperTitleForQuery(_ paper: PaperIndexRecord?, fallback: String) -> String {
        if let title = paper?.title, !title.isEmpty { return title }
        return fallback
    }

    private static func wikiNote(_ results: [LookupResult]) -> String? {
        let failedWiki = results.contains { $0.note == WikiRelevance.noGoodSource }
        let hasKeepable = results.contains { !$0.sources.isEmpty || (!$0.text.isEmpty && $0.note != WikiRelevance.noGoodSource) }
        if failedWiki && !hasKeepable { return WikiRelevance.noGoodSource }
        return results.compactMap(\.note).first { $0 != WikiRelevance.noGoodSource }
    }

    private static func pack(
        note: String?,
        _ work: ([LocalPromptBuilder.SourceSnippet], [WebSource])
    ) -> (snippets: [LocalPromptBuilder.SourceSnippet], sources: [WebSource], note: String?) {
        (work.0, work.1, note)
    }

    private static func expanded(
        _ base: ([LocalPromptBuilder.SourceSnippet], [WebSource]),
        lookup: KeylessLookup,
        query: String
    ) async -> ([LocalPromptBuilder.SourceSnippet], [WebSource]) {
        let fetched = await LinkContentFetcher.expand(sources: base.1, lookup: lookup, query: query)
        if fetched.isEmpty { return base }
        return (fetched, base.1)
    }

    private static func snippets(from results: [LookupResult], labels: [String]) -> ([LocalPromptBuilder.SourceSnippet], [WebSource]) {
        var snippets: [LocalPromptBuilder.SourceSnippet] = []
        var sources: [WebSource] = []
        var index = 1
        for (offset, result) in results.enumerated() {
            guard !result.text.isEmpty else { continue }
            let label = offset < labels.count ? labels[offset] : "Source"
            snippets.append(.init(index: index, title: label, body: result.text))
            for source in result.sources where !sources.contains(where: { $0.url == source.url }) {
                sources.append(source)
            }
            index += 1
            if index > 3 { break }
        }
        return (snippets, sources)
    }

    private static func merge(_ first: LookupResult, _ second: LookupResult) -> LookupResult {
        var sources = first.sources
        for source in second.sources where !sources.contains(where: { samePaper($0, source) }) {
            sources.append(source)
        }
        let text = [first.text, second.text].filter { !$0.isEmpty }.joined(separator: "\n\n")
        return LookupResult(text: text, sources: sources, note: first.note ?? second.note)
    }

    private static func samePaper(_ a: WebSource, _ b: WebSource) -> Bool {
        if let doiA = a.doi, let doiB = b.doi, !doiA.isEmpty { return doiA.caseInsensitiveCompare(doiB) == .orderedSame }
        return a.url == b.url
    }

    private static func firstPaperID(in text: String) -> String? {
        if let match = text.firstMatch(of: #/paperId:\s*([^\s;]+)/#) { return String(match.1) }
        if let match = text.firstMatch(of: #/arXiv:\s*([^\s;]+)/#) { return "arXiv:\(match.1)" }
        return nil
    }
}
