import Foundation

/// A paper returned by Semantic Scholar or arXiv.
struct PaperHit: Equatable, Sendable {
    var paperID: String?
    var title: String
    var year: Int?
    var authors: [String]
    var abstract: String?
    var url: URL?
    var arxivID: String?
    var doi: String?
    var tldr: String? = nil
}

struct WikiSummary: Equatable, Sendable {
    var title: String
    var description: String?
    var extract: String
    var url: URL?
    var isDisambiguation: Bool
}

/// Text handed back to the on-device model, plus the links it may cite.
struct LookupResult: Equatable, Sendable {
    var text: String
    var sources: [WebSource]
    var note: String? = nil
}

/// Keyless lookup endpoints used by the on-device tools.
enum LookupEndpoints {
    static let paperFields = "title,year,authors,abstract,url,externalIds,tldr"

    static func wikipediaExtract(title: String) -> URL {
        url("https://en.wikipedia.org/w/api.php", [
            "action": "query", "prop": "extracts", "explaintext": "1", "exintro": "0",
            "titles": title, "format": "json", "utf8": "1",
        ])
    }

    static func semanticScholarPaper(id: String) -> URL {
        let encoded = id.addingPercentEncoding(withAllowedCharacters: pathSegmentAllowed) ?? id
        return url("https://api.semanticscholar.org/graph/v1/paper/\(encoded)", ["fields": paperFields])
    }

    static func arxivByID(_ id: String) -> URL {
        url("https://export.arxiv.org/api/query", ["id_list": id, "start": "0", "max_results": "1"])
    }

    static func wikipediaSearch(_ query: String) -> URL {
        url("https://en.wikipedia.org/w/api.php", [
            "action": "query", "list": "search", "srsearch": query,
            "srlimit": "3", "format": "json", "utf8": "1",
        ])
    }

    static func wikipediaSummary(title: String) -> URL {
        let slug = title.replacingOccurrences(of: " ", with: "_")
            .addingPercentEncoding(withAllowedCharacters: pathSegmentAllowed) ?? title
        return URL(string: "https://en.wikipedia.org/api/rest_v1/page/summary/\(slug)")!
    }

    static func semanticScholarSearch(_ query: String) -> URL {
        url("https://api.semanticscholar.org/graph/v1/paper/search",
            ["query": query, "fields": paperFields, "limit": "5"])
    }

    static func semanticScholarRecommendations(paperID: String) -> URL {
        let id = paperID.addingPercentEncoding(withAllowedCharacters: pathSegmentAllowed) ?? paperID
        return url("https://api.semanticscholar.org/recommendations/v1/papers/forpaper/\(id)",
                   ["fields": paperFields, "limit": "5"])
    }

    static func arxivSearch(_ query: String) -> URL {
        url("https://export.arxiv.org/api/query",
            ["search_query": "all:\(query)", "start": "0", "max_results": "5"])
    }

    static func openAlexSearch(_ query: String) -> URL {
        url("https://api.openalex.org/works", ["search": query, "per_page": "5"])
    }

    private static let pathSegmentAllowed = CharacterSet.urlPathAllowed.subtracting(CharacterSet(charactersIn: "/?#"))

    private static func url(_ base: String, _ query: KeyValuePairs<String, String>) -> URL {
        var components = URLComponents(string: base)!
        components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        // `+` is literal in URLComponents but means space to most servers.
        components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        return components.url!
    }
}

/// Pure parsers over raw response bodies. They never throw: malformed input yields empty results.
enum LookupParsers {
    /// `action=query&list=search` → article titles, best match first.
    static func wikipediaPlainExtract(_ data: Data) -> String? {
        let pages = (json(data)?["query"] as? [String: Any])?["pages"] as? [String: Any] ?? [:]
        for (_, value) in pages {
            guard let page = value as? [String: Any],
                  let extract = (page["extract"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !extract.isEmpty else { continue }
            return extract
        }
        return nil
    }

    static func wikipediaSearchTitles(_ data: Data) -> [String] {
        let search = (json(data)?["query"] as? [String: Any])?["search"] as? [[String: Any]] ?? []
        return search.compactMap { $0["title"] as? String }
    }

    /// REST `page/summary/{title}`.
    static func wikipediaSummary(_ data: Data) -> WikiSummary? {
        guard let root = json(data), let title = root["title"] as? String else { return nil }
        let extract = (root["extract"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !extract.isEmpty else { return nil }
        let page = ((root["content_urls"] as? [String: Any])?["desktop"] as? [String: Any])?["page"] as? String
        return WikiSummary(
            title: title,
            description: root["description"] as? String,
            extract: extract,
            url: page.flatMap(URL.init(string:)),
            isDisambiguation: root["type"] as? String == "disambiguation"
        )
    }

    /// Graph search (`data`) and recommendations (`recommendedPapers`) share the paper shape.
    static func semanticScholarPapers(_ data: Data) -> [PaperHit] {
        guard let root = json(data) else { return [] }
        let papers = root["data"] as? [[String: Any]] ?? root["recommendedPapers"] as? [[String: Any]] ?? []
        return papers.compactMap(parsePaper(_:))
    }

    static func semanticScholarPapers(paperObject data: Data) -> [PaperHit] {
        guard let root = json(data) else { return [] }
        if let hit = parsePaper(root) { return [hit] }
        return semanticScholarPapers(data)
    }

    private static func parsePaper(_ paper: [String: Any]) -> PaperHit? {
        guard let title = (paper["title"] as? String)?.collapsedWhitespace, !title.isEmpty else { return nil }
        let ids = paper["externalIds"] as? [String: Any] ?? [:]
        let arxiv = ids["ArXiv"] as? String
        let doi = ids["DOI"] as? String
        let url = (paper["url"] as? String).flatMap(URL.init(string:))
            ?? arxiv.flatMap { URL(string: "https://arxiv.org/abs/\($0)") }
            ?? doi.flatMap { URL(string: "https://doi.org/\($0)") }
        let tldr = (paper["tldr"] as? [String: Any])?["text"] as? String
        return PaperHit(
            paperID: paper["paperId"] as? String,
            title: title,
            year: paper["year"] as? Int,
            authors: (paper["authors"] as? [[String: Any]] ?? []).compactMap { $0["name"] as? String },
            abstract: (paper["abstract"] as? String)?.collapsedWhitespace,
            url: url,
            arxivID: arxiv,
            doi: doi,
            tldr: tldr?.collapsedWhitespace
        )
    }

    static func openAlexWorks(_ data: Data) -> [PaperHit] {
        guard let root = json(data), let results = root["results"] as? [[String: Any]] else { return [] }
        return results.compactMap { work in
            guard let title = (work["display_name"] as? String)?.collapsedWhitespace, !title.isEmpty else { return nil }
            let authors = (work["authorships"] as? [[String: Any]] ?? []).compactMap { row in
                (row["author"] as? [String: Any])?["display_name"] as? String
            }
            let doiRaw = work["doi"] as? String
            let doi = doiRaw?.replacingOccurrences(of: "https://doi.org/", with: "")
            let url = (work["id"] as? String).flatMap(URL.init(string:))
                ?? doi.flatMap { URL(string: "https://doi.org/\($0)") }
            return PaperHit(
                paperID: work["id"] as? String,
                title: title,
                year: work["publication_year"] as? Int,
                authors: authors,
                abstract: nil,
                url: url,
                arxivID: nil,
                doi: doi
            )
        }
    }

    /// arXiv export API Atom feed.
    static func arxivEntries(_ data: Data) -> [PaperHit] {
        let delegate = AtomFeedDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()
        return delegate.entries
    }

    private static func json(_ data: Data) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }
}

/// Turns parsed results into compact tool output. The on-device context window is small, so text is trimmed.
enum LookupFormat {
    static func wikipedia(_ summary: WikiSummary) -> LookupResult {
        var lines = ["Wikipedia: \(summary.title)"]
        if let description = summary.description, !description.isEmpty { lines.append("(\(description))") }
        lines.append(trimmed(summary.extract, to: 700))
        if let url = summary.url { lines.append("URL: \(url.absoluteString)") }
        let sources = summary.url.map { [WebSource(title: "\(summary.title) — Wikipedia", url: $0)] } ?? []
        return LookupResult(text: lines.joined(separator: "\n"), sources: sources)
    }

    static func papers(_ hits: [PaperHit], from service: String) -> LookupResult {
        guard !hits.isEmpty else { return LookupResult(text: "\(service): no matching papers.", sources: []) }
        var seen: Set<URL> = []
        var sources: [WebSource] = []
        let blocks = hits.prefix(5).enumerated().map { index, hit in
            var line = "\(index + 1). \(hit.title)"
            if let year = hit.year { line += " (\(year))" }
            if !hit.authors.isEmpty {
                line += " — " + hit.authors.prefix(3).joined(separator: ", ") + (hit.authors.count > 3 ? " et al." : "")
            }
            var block = [line]
            var ids: [String] = []
            if let id = hit.paperID { ids.append("paperId: \(id)") }
            if let arxiv = hit.arxivID { ids.append("arXiv: \(arxiv)") }
            if let doi = hit.doi { ids.append("DOI: \(doi)") }
            if !ids.isEmpty { block.append("   " + ids.joined(separator: "; ")) }
            if let url = hit.url {
                block.append("   URL: \(url.absoluteString)")
                if seen.insert(url).inserted { sources.append(WebSource(title: hit.title, url: url)) }
            }
            if let abstract = hit.abstract, !abstract.isEmpty { block.append("   " + trimmed(abstract, to: 220)) }
            return block.joined(separator: "\n")
        }
        return LookupResult(text: "\(service) results:\n" + blocks.joined(separator: "\n"), sources: sources)
    }

    static func trimmed(_ text: String, to limit: Int) -> String {
        let text = text.collapsedWhitespace
        guard text.count > limit else { return text }
        return String(text.prefix(limit)).trimmingCharacters(in: .whitespaces) + "…"
    }
}

extension String {
    var collapsedWhitespace: String {
        split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}

private final class AtomFeedDelegate: NSObject, XMLParserDelegate {
    private(set) var entries: [PaperHit] = []
    private var inEntry = false
    private var inAuthor = false
    private var text = ""
    private var id = "", title = "", summary = "", published = "", doi = ""
    private var authors: [String] = []

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                qualifiedName: String?, attributes: [String: String] = [:]) {
        text = ""
        switch name {
        case "entry":
            inEntry = true
            id = ""; title = ""; summary = ""; published = ""; doi = ""; authors = []
        case "author" where inEntry:
            inAuthor = true
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        text += string
    }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        guard inEntry else { return }
        let value = text.collapsedWhitespace
        switch name {
        case "id": id = value
        case "title": title = value
        case "summary": summary = value
        case "published": published = value
        case "arxiv:doi", "doi": doi = value
        case "name" where inAuthor: authors.append(value)
        case "author": inAuthor = false
        case "entry":
            inEntry = false
            if !title.isEmpty { entries.append(makeHit()) }
        default: break
        }
        text = ""
    }

    private func makeHit() -> PaperHit {
        let secureID = id.hasPrefix("http://") ? "https://" + id.dropFirst("http://".count) : id
        var arxivID: String?
        if let range = secureID.range(of: "/abs/") {
            let raw = String(secureID[range.upperBound...])
            arxivID = raw.replacingOccurrences(of: #"v\d+$"#, with: "", options: .regularExpression)
        }
        return PaperHit(
            paperID: arxivID.map { "arXiv:\($0)" },
            title: title,
            year: Int(published.prefix(4)),
            authors: authors,
            abstract: summary.isEmpty ? nil : summary,
            url: URL(string: secureID),
            arxivID: arxivID,
            doi: doi.isEmpty ? nil : doi
        )
    }
}
