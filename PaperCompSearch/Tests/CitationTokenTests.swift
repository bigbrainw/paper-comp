import XCTest
@testable import PaperComp

final class CitationTokenTests: XCTestCase {
    func testTokenizesPaperSourceAndAuthorYear() {
        let runs = CitationParser.tokenize("See [22] and [S1] versus (Smith 2020).")
        XCTAssertEqual(runs, [
            .text("See "),
            .citation(.paper(marker: "22"), display: "[22]"),
            .text(" and "),
            .citation(.source(index: 1), display: "[S1]"),
            .text(" versus "),
            .citation(.authorYear(author: "Smith", year: "2020"), display: "(Smith 2020)"),
            .text("."),
        ])
    }

    func testResolvesPaperMarker() {
        let refs = [PaperReference(marker: "22", raw: "[22] Smith. A Title. 2020.", title: "A Title",
                                   authors: "Smith", year: "2020", arxivID: nil, doi: nil)]
        XCTAssertEqual(CitationParser.resolve(.paper(marker: "22"), in: refs)?.title, "A Title")
        XCTAssertEqual(CitationParser.resolve(.authorYear(author: "Smith", year: "2020"), in: refs)?.marker, "22")
        XCTAssertNil(CitationParser.resolve(.paper(marker: "9"), in: refs))
    }
}
