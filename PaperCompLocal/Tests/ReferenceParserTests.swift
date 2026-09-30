import XCTest
@testable import PaperComp

final class ReferenceParserTests: XCTestCase {
    func testNumberedReferences() {
        let pages = [numberedFixture]
        let refs = ReferenceParser.parse(pages: pages)
        XCTAssertGreaterThanOrEqual(refs.count, 3)
        XCTAssertEqual(refs[0].marker, "1")
        XCTAssertEqual(refs[1].marker, "2")
        XCTAssertEqual(refs[2].marker, "3")
        XCTAssertEqual(refs[0].title, "Attention Is All You Need")
        XCTAssertEqual(refs[0].year, "2017")
        XCTAssertEqual(refs[1].arxivID, "1409.0473")
        XCTAssertEqual(refs[2].doi, "10.1145/1390156.1390177")
        let cited = ReferenceParser.matching(selection: "as shown in [2]", in: refs)
        XCTAssertEqual(cited.first?.marker, "2")
    }

    func testAuthorYearReferences() {
        let refs = ReferenceParser.parse(pages: [authorYearFixture])
        XCTAssertGreaterThanOrEqual(refs.count, 2)
        XCTAssertTrue(refs.contains(where: { $0.year == "2017" && ($0.title?.contains("Attention") == true) }))
        XCTAssertTrue(refs.contains(where: { $0.year == "2020" }))
        let cited = ReferenceParser.matching(selection: "see (Vaswani 2017)", in: refs)
        XCTAssertFalse(cited.isEmpty)
    }

    func testIEEEReferences() throws {
        let refs = ReferenceParser.parse(pages: [ieeeFixture])
        XCTAssertGreaterThanOrEqual(refs.count, 2)
        let first = try XCTUnwrap(refs.first)
        XCTAssertEqual(first.marker, "1")
        XCTAssertTrue(first.raw.contains("BERT"))
        XCTAssertEqual(refs.dropFirst().first?.year, "2017")
    }

    private let numberedFixture = """
        5. Conclusion
        We conclude here.

        References
        [1] Vaswani, A. Attention Is All You Need. NeurIPS, 2017.
        [2] Bahdanau, D. Neural machine translation. arXiv: 1409.0473, 2015.
        [3] Bengio, Y. Curriculum learning. ICML, 2009. doi: 10.1145/1390156.1390177
        """

    private let authorYearFixture = """
        Bibliography
        Vaswani, A., et al. (2017). Attention Is All You Need. NeurIPS.
        Brown, T. (2020). Language models are few-shot learners. NeurIPS.
        """

    private let ieeeFixture = """
        References
        1. J. Devlin, “BERT: Pre-training of Deep Bidirectional Transformers,” NAACL, 2019.
        2. A. Vaswani, “Attention Is All You Need,” NeurIPS, pp. 5998–6008, 2017.
        """
}
