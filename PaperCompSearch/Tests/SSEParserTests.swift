import XCTest
@testable import PaperComp

final class SSEParserTests: XCTestCase {
    static let fixture = #"""
    event: response.created
    data: {"type":"response.created","sequence_number":0,"response":{"id":"resp_123","status":"in_progress","output":[]}}

    event: response.in_progress
    data: {"type":"response.in_progress","response":{"id":"resp_123"}}

    event: response.output_item.added
    data: {"type":"response.output_item.added","output_index":0,"item":{"id":"ws_1","type":"web_search_call","status":"in_progress"}}

    event: response.web_search_call.searching
    data: {"type":"response.web_search_call.searching","output_index":0,"item_id":"ws_1"}

    event: response.web_search_call.completed
    data: {"type":"response.web_search_call.completed","output_index":0,"item_id":"ws_1","sequence_number":4}

    event: response.output_item.done
    data: {"type":"response.output_item.done","output_index":0,"item":{"id":"ws_1","type":"web_search_call","status":"completed"}}

    event: response.output_item.added
    data: {"type":"response.output_item.added","output_index":1,"item":{"id":"msg_1","type":"message","role":"assistant","content":[]}}

    event: response.output_text.delta
    data: {"type":"response.output_text.delta","item_id":"msg_1","output_index":1,"content_index":0,"delta":"Attention is "}

    event: response.output_text.delta
    data: {"type":"response.output_text.delta","item_id":"msg_1","output_index":1,"content_index":0,"delta":"all you need."}

    event: response.output_text.annotation.added
    data: {"type":"response.output_text.annotation.added","annotation_index":0,"annotation":{"type":"url_citation","start_index":0,"end_index":12,"url":"https://arxiv.org/abs/1706.03762","title":"Attention Is All You Need"}}

    event: response.some_future_event
    data: {"type":"response.some_future_event","foo":1}

    event: response.completed
    data: {"type":"response.completed","response":{"id":"resp_123","status":"completed","usage":{"input_tokens":1200,"output_tokens":80},"output":[{"type":"web_search_call","id":"ws_1","status":"completed"},{"type":"message","id":"msg_1","content":[{"type":"output_text","text":"Attention is all you need.","annotations":[{"type":"url_citation","start_index":0,"end_index":12,"url":"https://arxiv.org/abs/1706.03762","title":"Attention Is All You Need"},{"type":"url_citation","start_index":13,"end_index":25,"url":"https://en.wikipedia.org/wiki/Transformer_(deep_learning_architecture)","title":""}]}]}]}}

    event: error
    data: {"type":"error","code":"server_error","message":"Something broke","param":null}

    data: [DONE]

    """#

    func parseAll(_ text: String, dropBlankLines: Bool = false) -> [SearchEvent] {
        var parser = SSEParser()
        var lines = text.components(separatedBy: "\n")
        if dropBlankLines { lines.removeAll(where: \.isEmpty) }
        return lines.flatMap { parser.parse(line: $0) } + parser.finish()
    }

    func testFixtureProducesExpectedEvents() {
        let arxiv = WebSource(title: "Attention Is All You Need", url: URL(string: "https://arxiv.org/abs/1706.03762")!)
        let wiki = WebSource(title: "en.wikipedia.org",
                             url: URL(string: "https://en.wikipedia.org/wiki/Transformer_(deep_learning_architecture)")!)
        let expected: [SearchEvent] = [
            .created(responseID: "resp_123"),
            .searching,
            .searching,
            .searchFinished,
            .searchFinished,
            .textDelta("Attention is "),
            .textDelta("all you need."),
            .source(arxiv),
            .source(wiki),
            .usage(OpenAIUsage(inputTokens: 1200, outputTokens: 80, webSearchCalls: 1)),
            .completed(responseID: "resp_123", text: "Attention is all you need."),
            .failed("Something broke"),
        ]
        XCTAssertEqual(parseAll(Self.fixture), expected)
        // URLSession.AsyncBytes.lines drops blank lines; the result must not change.
        XCTAssertEqual(parseAll(Self.fixture, dropBlankLines: true), expected)
    }

    func testTextAndCitationsAccumulate() {
        let events = parseAll(Self.fixture)
        let text = events.reduce(into: "") { if case .textDelta(let d) = $1 { $0 += d } }
        let urls = events.compactMap { if case .source(let s) = $0 { s.url.absoluteString } else { nil } }
        XCTAssertEqual(text, "Attention is all you need.")
        XCTAssertEqual(urls, ["https://arxiv.org/abs/1706.03762",
                              "https://en.wikipedia.org/wiki/Transformer_(deep_learning_architecture)"])
    }

    func testResponseFailedAndGarbage() {
        let stream = """
        data: not json
        data: {"type":"response.failed","response":{"id":"r","error":{"code":"x","message":"Model not found"}}}
        : keep-alive comment
        """
        XCTAssertEqual(parseAll(stream), [.failed("Model not found")])
    }

    func testUsageKeepsOutputTokensAndRecordsReasoningDetails() {
        let stream = """
        data: {"type":"response.completed","response":{"id":"r","usage":{"input_tokens":10,"output_tokens":80,"output_tokens_details":{"reasoning_tokens":50}},"output":[]}}
        """
        let events = parseAll(stream)
        let usage = events.compactMap { if case .usage(let u) = $0 { u } else { nil } }.first
        XCTAssertEqual(usage, OpenAIUsage(inputTokens: 10, outputTokens: 80, webSearchCalls: 0, reasoningTokens: 50))
        XCTAssertEqual(
            OpenAISpend.cost(usage!),
            OpenAISpend.cost(inputTokens: 10, outputTokens: 80, webSearchCalls: 0),
            accuracy: 0.000_001
        )
    }

    func testNestedCitationShapeAndDuplicates() {
        let stream = """
        data: {"type":"response.output_text.annotation.added","annotation":{"type":"url_citation","url_citation":{"url":"https://example.com/a","title":"A"}}}
        data: {"type":"response.output_text.annotation.added","annotation":{"type":"url_citation","url":"https://example.com/a","title":"A again"}}
        data: {"type":"response.output_text.annotation.added","annotation":{"type":"file_citation","file_id":"f"}}
        """
        XCTAssertEqual(parseAll(stream), [.source(WebSource(title: "A", url: URL(string: "https://example.com/a")!))])
    }
}
