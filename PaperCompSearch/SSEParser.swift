import Foundation

struct WebSource: Hashable, Sendable, Identifiable, Codable {
    let title: String
    let url: URL
    var site: String?
    var year: String?
    var studyType: String?
    var takeaway: String?
    var doi: String?

    var id: URL { url }

    init(title: String, url: URL, site: String? = nil, year: String? = nil,
         studyType: String? = nil, takeaway: String? = nil, doi: String? = nil) {
        self.title = title
        self.url = url
        self.site = site
        self.year = year
        self.studyType = studyType
        self.takeaway = takeaway
        self.doi = doi
    }

    var displaySite: String { site ?? url.host() ?? url.absoluteString }
}

enum SearchEvent: Equatable, Sendable {
    case created(responseID: String)
    case searching
    /// A named lookup in progress, e.g. "Looking up “BLEU” on Wikipedia…".
    case lookingUp(String)
    case searchFinished
    case textDelta(String)
    /// The full answer so far; replaces rather than appends.
    case textSnapshot(String)
    case source(WebSource)
    case paperPassages([PaperPassage])
    case detectedTerms([String])
    /// Starts a collapsible per-term section (`term` is the heading).
    case breakdownSectionStart(term: String)
    /// Full text of one breakdown section so far.
    case breakdownSectionSnapshot(term: String, text: String)
    case copiedPassage
    case retrievalNote(String)
    case metrics(tokensPerSecond: Double)
    case usage(OpenAIUsage)
    case completed(responseID: String?, text: String)
    case failed(String)
}

/// Turns Responses API server-sent-event lines into `SearchEvent`s.
/// Unknown event types are ignored; sources are de-duplicated by URL.
struct SSEParser: Sendable {
    private var seenURLs: Set<URL> = []
    private var dataLines: [String] = []

    init() {}

    mutating func parse(line rawLine: String) -> [SearchEvent] {
        let line = rawLine.hasSuffix("\r") ? String(rawLine.dropLast()) : rawLine
        if line.isEmpty { return flush() }
        guard line.hasPrefix("data:") else { return [] }  // event:, id:, retry:, comments

        var payload = line.dropFirst(5)
        if payload.first == " " { payload = payload.dropFirst() }
        if payload == "[DONE]" {
            dataLines.removeAll()
            return []
        }
        dataLines.append(String(payload))

        // URLSession's line sequence drops blank lines, so dispatch as soon as the JSON is complete.
        if let object = Self.json(dataLines.joined(separator: "\n")) {
            dataLines.removeAll()
            return events(for: object)
        }
        if dataLines.count > 1, let object = Self.json(String(payload)) {
            dataLines.removeAll()
            return events(for: object)
        }
        return []
    }

    mutating func finish() -> [SearchEvent] { flush() }

    private mutating func flush() -> [SearchEvent] {
        defer { dataLines.removeAll() }
        guard !dataLines.isEmpty, let object = Self.json(dataLines.joined(separator: "\n")) else { return [] }
        return events(for: object)
    }

    private mutating func events(for object: [String: Any]) -> [SearchEvent] {
        switch object["type"] as? String {
        case "response.created":
            guard let id = (object["response"] as? [String: Any])?["id"] as? String else { return [] }
            return [.created(responseID: id)]
        case "response.output_text.delta":
            guard let delta = object["delta"] as? String, !delta.isEmpty else { return [] }
            return [.textDelta(delta)]
        case "response.output_text.annotation.added":
            return newSources(from: object["annotation"].map { [$0] } ?? []).map(SearchEvent.source)
        case "response.output_item.added", "response.web_search_call.in_progress", "response.web_search_call.searching":
            return Self.isWebSearch(object) ? [.searching] : []
        case "response.output_item.done", "response.web_search_call.completed":
            return Self.isWebSearch(object) ? [.searchFinished] : []
        case "response.completed", "response.incomplete":
            let response = object["response"] as? [String: Any] ?? [:]
            let contents = Self.outputTextContents(of: response)
            let annotations: [Any] = contents.flatMap { $0["annotations"] as? [Any] ?? [] }
            let sources = newSources(from: annotations)
            let text = contents.compactMap { $0["text"] as? String }.joined(separator: "\n\n")
            var events = sources.map(SearchEvent.source)
            if let usage = Self.usage(from: response) {
                events.append(.usage(usage))
            }
            events.append(.completed(responseID: response["id"] as? String, text: text))
            return events
        case "response.failed":
            let response = object["response"] as? [String: Any]
            let message = (response?["error"] as? [String: Any])?["message"] as? String
            return [.failed(message ?? "The request failed.")]
        case "error":
            let message = object["message"] as? String
                ?? (object["error"] as? [String: Any])?["message"] as? String
            return [.failed(message ?? "Unknown error.")]
        default:
            return []
        }
    }

    private mutating func newSources(from annotations: [Any]) -> [WebSource] {
        annotations.compactMap { annotation in
            guard let outer = annotation as? [String: Any],
                  outer["type"] as? String == "url_citation"
            else { return nil }
            // Responses puts url/title on the annotation; Chat Completions nests them under "url_citation".
            let dict = outer["url"] == nil ? outer["url_citation"] as? [String: Any] ?? outer : outer
            guard let urlString = dict["url"] as? String,
                  let url = URL(string: urlString),
                  seenURLs.insert(url).inserted
            else { return nil }
            let title = (dict["title"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? url.host() ?? urlString
            return WebSource(title: title, url: url)
        }
    }

    static func usage(from response: [String: Any]) -> OpenAIUsage? {
        let usage = response["usage"] as? [String: Any]
        let input = (usage?["input_tokens"] as? Int)
            ?? (usage?["input_tokens"] as? Double).map { Int($0) }
            ?? 0
        let output = (usage?["output_tokens"] as? Int)
            ?? (usage?["output_tokens"] as? Double).map { Int($0) }
            ?? 0
        let details = usage?["output_tokens_details"] as? [String: Any]
        let reasoning = (details?["reasoning_tokens"] as? Int)
            ?? (details?["reasoning_tokens"] as? Double).map { Int($0) }
            ?? 0
        let searches = (response["output"] as? [[String: Any]] ?? [])
            .filter { $0["type"] as? String == "web_search_call" }
            .count
        if usage == nil, searches == 0 { return nil }
        return OpenAIUsage(
            inputTokens: input,
            outputTokens: output,
            webSearchCalls: searches,
            reasoningTokens: reasoning
        )
    }

    private static func isWebSearch(_ object: [String: Any]) -> Bool {
        if (object["type"] as? String)?.hasPrefix("response.web_search_call.") == true { return true }
        return (object["item"] as? [String: Any])?["type"] as? String == "web_search_call"
    }

    private static func outputTextContents(of response: [String: Any]) -> [[String: Any]] {
        let output = response["output"] as? [[String: Any]] ?? []
        return output
            .filter { $0["type"] as? String == "message" }
            .flatMap { $0["content"] as? [[String: Any]] ?? [] }
            .filter { $0["type"] as? String == "output_text" }
    }

    private static func json(_ string: String) -> [String: Any]? {
        guard let data = string.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }
}
