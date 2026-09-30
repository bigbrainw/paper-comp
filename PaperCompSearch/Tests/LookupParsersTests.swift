import XCTest
@testable import PaperComp

final class LookupParsersTests: XCTestCase {
    func testWikipediaPlainExtract() {
        let json = """
        {"query":{"pages":{"123":{"title":"Transformer","extract":"A transformer is a neural network."}}}}
        """.data(using: .utf8)!
        XCTAssertEqual(LookupParsers.wikipediaPlainExtract(json), "A transformer is a neural network.")
    }

    func testWikipediaSearchTitles() {
        let json = """
        {"query":{"search":[{"title":"Transformer (deep learning architecture)"},{"title":"Attention"}]}}
        """.data(using: .utf8)!
        XCTAssertEqual(
            LookupParsers.wikipediaSearchTitles(json),
            ["Transformer (deep learning architecture)", "Attention"]
        )
    }

    func testWikipediaSummary() {
        let json = """
        {"title":"BLEU","description":"metric","extract":"BLEU measures translation quality.","type":"standard","content_urls":{"desktop":{"page":"https://en.wikipedia.org/wiki/BLEU"}}}
        """.data(using: .utf8)!
        let summary = LookupParsers.wikipediaSummary(json)
        XCTAssertEqual(summary?.title, "BLEU")
        XCTAssertEqual(summary?.extract, "BLEU measures translation quality.")
        XCTAssertEqual(summary?.url?.absoluteString, "https://en.wikipedia.org/wiki/BLEU")
        XCTAssertFalse(summary?.isDisambiguation ?? true)
    }

    func testSemanticScholarPapers() {
        let json = """
        {"data":[{"paperId":"abc123","title":"Attention Is All You Need","year":2017,"authors":[{"name":"Vaswani"}],"abstract":"We propose transformers.","url":"https://www.semanticscholar.org/paper/abc123","externalIds":{"ArXiv":"1706.03762","DOI":"10.5555/3295222.3295349"}}]}
        """.data(using: .utf8)!
        let papers = LookupParsers.semanticScholarPapers(json)
        XCTAssertEqual(papers.count, 1)
        XCTAssertEqual(papers[0].paperID, "abc123")
        XCTAssertEqual(papers[0].arxivID, "1706.03762")
        XCTAssertEqual(papers[0].authors, ["Vaswani"])
    }

    func testArxivAtomFeed() {
        let xml = """
        <?xml version="1.0"?>
        <feed xmlns="http://www.w3.org/2005/Atom" xmlns:arxiv="http://arxiv.org/schemas/atom">
          <entry>
            <id>http://arxiv.org/abs/1706.03762v5</id>
            <title>Attention Is All You Need</title>
            <summary>We propose the Transformer.</summary>
            <published>2017-06-12T00:00:00Z</published>
            <author><name>Ashish Vaswani</name></author>
            <arxiv:doi>10.5555/3295222.3295349</arxiv:doi>
          </entry>
        </feed>
        """.data(using: .utf8)!
        let papers = LookupParsers.arxivEntries(xml)
        XCTAssertEqual(papers.count, 1)
        XCTAssertEqual(papers[0].title, "Attention Is All You Need")
        XCTAssertEqual(papers[0].arxivID, "1706.03762")
        XCTAssertEqual(papers[0].year, 2017)
    }

    func testLookupFormatPapersBuildsSources() {
        let hit = PaperHit(paperID: "p1", title: "Paper A", year: 2020, authors: ["A"], abstract: nil,
                           url: URL(string: "https://example.com/a"), arxivID: nil, doi: nil)
        let result = LookupFormat.papers([hit], from: "Semantic Scholar")
        XCTAssertEqual(result.sources.count, 1)
        XCTAssertTrue(result.text.contains("Paper A"))
    }
}
