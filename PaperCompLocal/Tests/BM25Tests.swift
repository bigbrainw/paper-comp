import XCTest
@testable import PaperComp

final class BM25Tests: XCTestCase {
    func testRanksMatchingPassageFirst() {
        let chunks = [
            PaperChunk(pageIndex: 0, text: "The cat sat on the mat and drank milk."),
            PaperChunk(pageIndex: 1, text: "Self-attention maps queries to keys and values in a transformer."),
            PaperChunk(pageIndex: 2, text: "We bake bread with flour and water."),
        ]
        let ranked = BM25Index(chunks: chunks).ranked(query: "self-attention transformer queries", limit: 3)
        XCTAssertEqual(ranked.first?.pageIndex, 1)
        XCTAssertTrue(ranked.first?.text.contains("Self-attention") == true)
    }

    func testEmptyQueryReturnsPrefix() {
        let chunks = [PaperChunk(pageIndex: 0, text: "alpha"), PaperChunk(pageIndex: 1, text: "beta")]
        XCTAssertEqual(BM25Index(chunks: chunks).ranked(query: "", limit: 1).count, 1)
    }
}

final class PaperTextTests: XCTestCase {
    func testCleansHyphenationAndChunks() {
        let page = "transfor-\nmation of the input. Next sentence stays here and grows into a longer passage."
        let cleaned = PaperText.clean(page)
        XCTAssertTrue(cleaned.contains("transformation"))
        XCTAssertFalse(cleaned.contains("transfor-"))
        let chunks = PaperChunker.chunk(pages: [page])
        XCTAssertFalse(chunks.isEmpty)
        XCTAssertEqual(chunks[0].pageIndex, 0)
    }

    func testDetectsAbstractAndIntroduction() {
        let pages = ["""
            Attention Is All You Need
            Abstract
            We propose the Transformer.
            1 Introduction
            Recurrent models have been the default.
            2 Background
            Other work exists.
            """]
        let structure = PaperStructureDetector.detect(titleHint: "Attention Is All You Need", pages: pages)
        XCTAssertTrue(structure.abstract.contains("Transformer"))
        XCTAssertTrue(structure.introduction.contains("Recurrent"))
    }
}
