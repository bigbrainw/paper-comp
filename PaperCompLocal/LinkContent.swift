import Foundation

enum LinkDetector {
    static func urlOrDOI(in text: String) -> URL? {
        if let match = text.firstMatch(of: #/https?:\/\/[^\s<>"']+/#) {
            let raw = String(match.0).trimmingCharacters(in: CharacterSet(charactersIn: ".,);"))
            return URL(string: raw)
        }
        if let match = text.firstMatch(of: #/\b10\.\d{4,9}\/[^\s,]+/#) {
            let doi = String(match.0).trimmingCharacters(in: CharacterSet(charactersIn: ".,);"))
            return URL(string: "https://doi.org/\(doi)")
        }
        return nil
    }
}

enum LinkContentFetcher {
    static func expand(
        sources: [WebSource],
        lookup: KeylessLookup,
        query: String
    ) async -> [LocalPromptBuilder.SourceSnippet] {
        var snippets: [LocalPromptBuilder.SourceSnippet] = []
        for (offset, source) in sources.prefix(2).enumerated() {
            let body = await fetch(source: source, lookup: lookup, query: query)
            guard !body.isEmpty else { continue }
            snippets.append(.init(index: offset + 1, title: source.title, body: body))
        }
        return snippets
    }

    static func fetch(source: WebSource, lookup: KeylessLookup, query: String) async -> String {
        let host = source.url.host()?.lowercased() ?? ""
        if host.contains("wikipedia.org") {
            return await wikipediaExtract(url: source.url, lookup: lookup, query: query)
        }
        if host.contains("arxiv.org") {
            return await arxivAbstract(url: source.url, lookup: lookup)
        }
        if host.contains("semanticscholar.org") {
            return await semanticScholarFull(url: source.url, lookup: lookup)
        }
        return await htmlMainText(url: source.url, lookup: lookup)
    }

    static func wikipediaExtract(url: URL, lookup: KeylessLookup, query: String) async -> String {
        let title = url.path.split(separator: "/").last.map { $0.replacingOccurrences(of: "_", with: " ") }
            ?? url.lastPathComponent
        guard let data = try? await lookup.data(LookupEndpoints.wikipediaExtract(title: title.removingPercentEncoding ?? title)),
              let extract = LookupParsers.wikipediaPlainExtract(data) else { return "" }
        if let range = extract.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]), !query.isEmpty {
            let start = extract.index(range.lowerBound, offsetBy: -80, limitedBy: extract.startIndex) ?? extract.startIndex
            return LookupFormat.trimmed(String(extract[start...]), to: 2_500)
        }
        return LookupFormat.trimmed(extract, to: 2_500)
    }

    static func arxivAbstract(url: URL, lookup: KeylessLookup) async -> String {
        let id = url.path.split(separator: "/").last.map(String.init) ?? ""
        let stripped = id.replacingOccurrences(of: #"v\d+$"#, with: "", options: .regularExpression)
        guard !stripped.isEmpty,
              let data = try? await lookup.data(LookupEndpoints.arxivByID(stripped)) else { return "" }
        let hits = LookupParsers.arxivEntries(data)
        guard let hit = hits.first else { return "" }
        var lines = [hit.title]
        if !hit.authors.isEmpty { lines.append(hit.authors.prefix(8).joined(separator: ", ")) }
        if let abstract = hit.abstract { lines.append(abstract) }
        return LookupFormat.trimmed(lines.joined(separator: "\n"), to: 2_500)
    }

    static func semanticScholarFull(url: URL, lookup: KeylessLookup) async -> String {
        if let paperID = url.path.split(separator: "/").last.map(String.init),
           let data = try? await lookup.data(LookupEndpoints.semanticScholarPaper(id: paperID)) {
            let hits = LookupParsers.semanticScholarPapers(paperObject: data)
            if let hit = hits.first {
                var parts = [hit.title]
                if let tldr = hit.tldr, !tldr.isEmpty { parts.append("TLDR: \(tldr)") }
                if let abstract = hit.abstract { parts.append(abstract) }
                return LookupFormat.trimmed(parts.joined(separator: "\n"), to: 2_500)
            }
        }
        return await htmlMainText(url: url, lookup: lookup)
    }

    static func htmlMainText(url: URL, lookup: KeylessLookup) async -> String {
        guard let data = try? await lookup.data(url),
              let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1)
        else { return "" }
        return HTMLMainText.extract(html, cap: 3_000)
    }
}
