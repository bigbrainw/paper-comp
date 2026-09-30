import Foundation

enum ConsensusSettings {
    static let enabledKey = "useConsensus"
    static let endpoint = URL(string: "https://mcp.consensus.app/mcp")!

    static var isEnabled: Bool {
        if UserDefaults.standard.object(forKey: enabledKey) == nil { return true }
        return UserDefaults.standard.bool(forKey: enabledKey)
    }
}

struct ConsensusPaper: Equatable, Sendable {
    var title: String
    var authors: String?
    var journal: String?
    var year: String?
    var doi: String?
    var citationCount: Int?
    var studyType: String?
    var takeaway: String?
    var url: URL?
}

struct ConsensusSearchOutcome: Equatable, Sendable {
    var papers: [ConsensusPaper]
    var limitReached: Bool
    var skipped: Bool

    static let empty = ConsensusSearchOutcome(papers: [], limitReached: false, skipped: true)
}

enum ConsensusSearch {
    /// Free-account search. Skips when signed out so Semantic Scholar / OpenAlex / arXiv run instead.
    static func search(_ query: String, pageSize: Int = 3) async -> ConsensusSearchOutcome {
        let connected = await MainActor.run { ConsensusAuth.shared.isConnected }
        guard ConsensusSettings.isEnabled, connected,
              !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .empty
        }
        do {
            let token = await ConsensusAuth.shared.validAccessToken()
            return try await run(query, pageSize: pageSize, token: token)
        } catch MCPError.unauthorized {
            if let token = await ConsensusAuth.shared.refreshAccessToken() {
                do {
                    return try await run(query, pageSize: pageSize, token: token)
                } catch {
                    return outcome(from: error)
                }
            }
            return .empty
        } catch {
            return outcome(from: error)
        }
    }

    static func lookupResult(query: String) async -> LookupResult {
        let outcome = await search(query)
        var result = ConsensusPaperParser.lookupResult(outcome.papers)
        if outcome.limitReached {
            result.note = ConsensusOAuth.limitNote
        } else if !outcome.papers.isEmpty {
            result.note = "Consensus: \(outcome.papers.count) paper\(outcome.papers.count == 1 ? "" : "s")"
        }
        return result
    }

    private static func run(_ query: String, pageSize: Int, token: String?) async throws -> ConsensusSearchOutcome {
        guard let token else { return .empty }
        var client = MCPClient(endpoint: ConsensusSettings.endpoint, accessToken: token)
        let session = try await client.initialize()
        let tools = try await client.listTools(session)
        let tool = tools.first { $0.name == "search" }
        let name = tool?.name ?? "search"
        let result = try await client.callTool(
            session,
            name: name,
            arguments: ConsensusOAuth.searchArguments(
                query: query, pageSize: pageSize, argumentNames: tool?.argumentNames ?? []
            )
        )
        if ConsensusOAuth.isLimitMessage(result.text) {
            return ConsensusSearchOutcome(papers: ConsensusPaperParser.parse(result.text), limitReached: true, skipped: false)
        }
        return ConsensusSearchOutcome(papers: ConsensusPaperParser.parse(result.text), limitReached: false, skipped: false)
    }

    private static func outcome(from error: Error) -> ConsensusSearchOutcome {
        if case MCPError.limited = error {
            return ConsensusSearchOutcome(papers: [], limitReached: true, skipped: false)
        }
        if ConsensusOAuth.isLimitMessage(error.localizedDescription) {
            return ConsensusSearchOutcome(papers: [], limitReached: true, skipped: false)
        }
        return .empty
    }
}

enum ConsensusPaperParser {
    static func parse(_ text: String) -> [ConsensusPaper] {
        if let json = decodeJSONPapers(text), !json.isEmpty { return json }
        return decodeMarkdownPapers(text)
    }

    static func lookupResult(_ papers: [ConsensusPaper]) -> LookupResult {
        guard !papers.isEmpty else { return LookupResult(text: "", sources: []) }
        var sources: [WebSource] = []
        let blocks = papers.prefix(3).enumerated().map { index, paper in
            var line = "\(index + 1). \(paper.title)"
            if let year = paper.year { line += " (\(year))" }
            if let authors = paper.authors { line += " — \(authors)" }
            var extras: [String] = []
            if let journal = paper.journal { extras.append(journal) }
            if let study = paper.studyType { extras.append(study) }
            if let count = paper.citationCount { extras.append("\(count) citations") }
            if let doi = paper.doi { extras.append("DOI: \(doi)") }
            var block = [line]
            if !extras.isEmpty { block.append("   " + extras.joined(separator: "; ")) }
            if let takeaway = paper.takeaway, !takeaway.isEmpty { block.append("   " + takeaway) }
            if let url = paper.url {
                block.append("   URL: \(url.absoluteString)")
                sources.append(WebSource(
                    title: paper.title,
                    url: url,
                    site: "Consensus",
                    year: paper.year,
                    studyType: paper.studyType,
                    takeaway: paper.takeaway,
                    doi: paper.doi
                ))
            }
            return block.joined(separator: "\n")
        }
        return LookupResult(text: "Consensus results:\n" + blocks.joined(separator: "\n"), sources: sources)
    }

    private static func decodeJSONPapers(_ text: String) -> [ConsensusPaper]? {
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) else { return nil }
        let rows: [[String: Any]]
        if let papers = (object as? [String: Any])?["papers"] as? [[String: Any]] {
            rows = papers
        } else if let array = object as? [[String: Any]] {
            rows = array
        } else {
            return nil
        }
        return rows.compactMap(paper(fromJSON:))
    }

    private static func paper(fromJSON json: [String: Any]) -> ConsensusPaper? {
        guard let title = json["title"] as? String, !title.isEmpty else { return nil }
        let authors: String?
        if let list = json["authors"] as? [String] {
            authors = list.prefix(4).joined(separator: ", ")
        } else {
            authors = json["authors"] as? String
        }
        let year: String?
        if let intYear = json["year"] as? Int {
            year = String(intYear)
        } else {
            year = json["year"] as? String
        }
        let url = (json["url"] as? String).flatMap(URL.init(string:))
        return ConsensusPaper(
            title: title,
            authors: authors,
            journal: json["journal"] as? String,
            year: year,
            doi: json["doi"] as? String,
            citationCount: json["citation_count"] as? Int,
            studyType: json["study_type"] as? String ?? json["studyType"] as? String,
            takeaway: json["takeaway"] as? String ?? json["key_takeaway"] as? String,
            url: url
        )
    }

    /// Official docs shape: `[1] [Title](url) (Authors, 2021, 154 citations, Journal, DOI: …)`
    static func decodeMarkdownPapers(_ text: String) -> [ConsensusPaper] {
        let pattern = #"\[(\d+)\]\s+\[([^\]]+)\]\((https?://[^)]+)\)(?:\s+\(([^)]+)\))?"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).compactMap { match in
            let title = ns.substring(with: match.range(at: 2))
            let url = URL(string: ns.substring(with: match.range(at: 3)))
            var paper = ConsensusPaper(title: title, url: url)
            if match.range(at: 4).location != NSNotFound {
                applyMeta(ns.substring(with: match.range(at: 4)), to: &paper)
            }
            return paper
        }
    }

    private static func applyMeta(_ raw: String, to paper: inout ConsensusPaper) {
        let parts = raw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        for part in parts {
            if part.hasPrefix("DOI:") {
                paper.doi = part.replacingOccurrences(of: "DOI:", with: "").trimmingCharacters(in: .whitespaces)
            } else if let count = part.wholeMatch(of: #/(\d+)\s+citations?/#) {
                paper.citationCount = Int(count.1)
            } else if part.wholeMatch(of: #/\d{4}/#) != nil {
                paper.year = part
            } else if paper.authors == nil {
                paper.authors = part
            } else if paper.journal == nil {
                paper.journal = part
            } else if paper.studyType == nil {
                paper.studyType = part
            }
        }
    }
}
