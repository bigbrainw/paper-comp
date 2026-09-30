import XCTest
@testable import PaperComp

final class ConsensusPaperParserTests: XCTestCase {
    func testParsesMarkdownListingFromDocs() {
        let text = """
            Found 20 papers, showing top 20.

            [1] [Caffeine and endurance](https://consensus.app/papers/details/abc/?utm_source=test) (Smith et al., 2021, 154 citations, Sports Medicine, DOI: 10.1007/s40279-021-01470-1)
              Abstract text...

            [2] [Second paper](https://consensus.app/papers/details/def) (Lee, 2019)
            """
        let papers = ConsensusPaperParser.parse(text)
        XCTAssertEqual(papers.count, 2)
        XCTAssertEqual(papers[0].title, "Caffeine and endurance")
        XCTAssertEqual(papers[0].year, "2021")
        XCTAssertEqual(papers[0].citationCount, 154)
        XCTAssertEqual(papers[0].doi, "10.1007/s40279-021-01470-1")
        XCTAssertEqual(papers[0].url?.host(), "consensus.app")
        XCTAssertEqual(papers[1].title, "Second paper")
    }

    func testParsesJSONPapers() {
        let json = """
            {"papers":[{"title":"A","url":"https://consensus.app/p/1","year":2020,"doi":"10.1/x","study_type":"RCT","takeaway":"It works."}]}
            """
        let papers = ConsensusPaperParser.parse(json)
        XCTAssertEqual(papers.first?.title, "A")
        XCTAssertEqual(papers.first?.year, "2020")
        XCTAssertEqual(papers.first?.studyType, "RCT")
        XCTAssertEqual(papers.first?.takeaway, "It works.")
    }

    func testLookupResultCopiesStudyType() {
        let result = ConsensusPaperParser.lookupResult([
            ConsensusPaper(title: "T", year: "2021", studyType: "meta-analysis",
                           takeaway: "Key", url: URL(string: "https://consensus.app/p/1")!),
        ])
        XCTAssertEqual(result.sources.first?.studyType, "meta-analysis")
        XCTAssertEqual(result.sources.first?.year, "2021")
        XCTAssertTrue(result.text.contains("Consensus results"))
    }
}
