import Foundation

/// In-memory response cache, one per capture's engine.
actor LookupCache {
    private var store: [URL: Data] = [:]

    func data(for url: URL) -> Data? { store[url] }
    func insert(_ data: Data, for url: URL) { store[url] = data }
}

enum LookupError: LocalizedError {
    case http(Int)

    var errorDescription: String? {
        switch self {
        case .http(let code): "Lookup failed with HTTP \(code)."
        }
    }
}

/// Free, keyless lookups for the on-device tools: Wikipedia, Semantic Scholar, arXiv.
/// Failures come back as explanatory text so the model can carry on without them.
struct KeylessLookup: Sendable {
    static let userAgent = "PaperComp/1.0 (iPad research-paper reader; on-device circle search)"

    var session: URLSession = .shared
    var cache = LookupCache()

    func wikipedia(_ query: String) async -> LookupResult {
        await wikipedia(WikiQueryContext(term: query, paperTitle: "", brief: nil, selection: query))
    }

    func wikipedia(_ context: WikiQueryContext) async -> LookupResult {
        let query = WikiRelevance.query(context)
        let keywords = WikiRelevance.matchKeywords(context)
        do {
            let titles = LookupParsers.wikipediaSearchTitles(try await data(LookupEndpoints.wikipediaSearch(query)))
            var summaries: [WikiSummary] = []
            for title in titles.prefix(3) {
                let body = try await data(LookupEndpoints.wikipediaSummary(title: title))
                if let summary = LookupParsers.wikipediaSummary(body) {
                    summaries.append(summary)
                }
            }
            if let summary = WikiRelevance.pick(summaries: summaries, keywords: keywords) {
                return LookupFormat.wikipedia(summary)
            }
            return LookupResult(text: "", sources: [], note: WikiRelevance.noGoodSource)
        } catch {
            return LookupResult(text: "Wikipedia lookup failed: \(error.localizedDescription)", sources: [])
        }
    }

    /// Semantic Scholar, then OpenAlex, then arXiv.
    func paperSearch(_ query: String) async -> LookupResult {
        if let body = try? await data(LookupEndpoints.semanticScholarSearch(query)) {
            let hits = LookupParsers.semanticScholarPapers(body)
            if !hits.isEmpty { return LookupFormat.papers(hits, from: "Semantic Scholar") }
        }
        if let body = try? await data(LookupEndpoints.openAlexSearch(query)) {
            let hits = LookupParsers.openAlexWorks(body)
            if !hits.isEmpty { return LookupFormat.papers(hits, from: "OpenAlex") }
        }
        do {
            let hits = LookupParsers.arxivEntries(try await data(LookupEndpoints.arxivSearch(query)))
            return LookupFormat.papers(hits, from: "arXiv")
        } catch {
            return LookupResult(text: "Paper search failed: \(error.localizedDescription)", sources: [])
        }
    }

    func relatedPapers(_ paperID: String) async -> LookupResult {
        do {
            let body = try await data(LookupEndpoints.semanticScholarRecommendations(paperID: paperID))
            return LookupFormat.papers(LookupParsers.semanticScholarPapers(body), from: "Semantic Scholar recommendations")
        } catch {
            return LookupResult(text: "Related-paper lookup failed: \(error.localizedDescription)", sources: [])
        }
    }

    func data(_ url: URL) async throws -> Data {
        if let cached = await cache.data(for: url) { return cached }
        var request = URLRequest(url: url, timeoutInterval: 12)
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(Self.userAgent, forHTTPHeaderField: "Api-User-Agent")
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw LookupError.http(http.statusCode)
        }
        await cache.insert(data, for: url)
        return data
    }
}
