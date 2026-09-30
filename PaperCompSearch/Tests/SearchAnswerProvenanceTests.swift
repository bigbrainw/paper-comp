import XCTest
@testable import PaperComp

final class SearchAnswerProvenanceTests: XCTestCase {
    func testRoundTripAndLegacyArray() {
        let url = URL(string: "https://example.com/p")!
        let provenance = SearchAnswerProvenance(
            sources: [WebSource(title: "Paper", url: url, year: "2020")],
            passages: [PaperPassage(pageIndex: 3, text: "1/f noise")]
        )
        let decoded = SearchAnswerProvenance.decode(from: provenance.encodeJSON())
        XCTAssertEqual(decoded.sources.first?.title, "Paper")
        XCTAssertEqual(decoded.passages.first?.pageIndex, 3)

        let legacy = SearchAnswerProvenance.decode(from: #"[{"title":"Old","url":"https://example.com/old"}]"#)
        XCTAssertEqual(legacy.sources.first?.title, "Old")
        XCTAssertTrue(legacy.passages.isEmpty)
    }

    func testEmptyLegacyShowsNoSources() {
        let empty = SearchAnswerProvenance.decode(from: "[]")
        XCTAssertTrue(empty.isEmpty)
    }
}
