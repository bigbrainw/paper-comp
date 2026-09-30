import XCTest
@testable import PaperComp

final class HTMLMainTextTests: XCTestCase {
    func testStripsChromeAndKeepsMainText() {
        let html = """
        <html><head><style>body{color:red}</style></head>
        <body>
        <header>Site nav</header>
        <nav><a href="/">Home</a></nav>
        <article><h1>Transformer</h1><p>Attention is all you need.</p><script>evil()</script></article>
        <footer>Copyright</footer>
        </body></html>
        """
        let text = HTMLMainText.extract(html, cap: 3_000)
        XCTAssertTrue(text.contains("Transformer"))
        XCTAssertTrue(text.contains("Attention is all you need"))
        XCTAssertFalse(text.contains("evil"))
        XCTAssertFalse(text.contains("Copyright"))
        XCTAssertFalse(text.contains("Home"))
        XCTAssertFalse(text.contains("<p>"))
    }

    func testCapsLength() {
        let html = "<p>" + String(repeating: "word ", count: 2_000) + "</p>"
        let text = HTMLMainText.extract(html, cap: 200)
        XCTAssertLessThanOrEqual(text.count, 220)
        XCTAssertTrue(text.hasSuffix("…"))
    }
}

final class PromptBudgetTests: XCTestCase {
    func testDropsLowestRankedFirst() {
        let parts = [
            PromptBudget.Part(rank: 1, text: String(repeating: "alpha ", count: 400)),
            PromptBudget.Part(rank: 2, text: String(repeating: "beta ", count: 400)),
            PromptBudget.Part(rank: 9, text: String(repeating: "gamma ", count: 400)),
        ]
        let trimmed = PromptBudget.trim(parts, limit: 500)
        XCTAssertTrue(trimmed.contains(where: { $0.rank == 1 }))
        XCTAssertFalse(trimmed.contains(where: { $0.rank == 9 }))
    }

    func testPromptLimit4096WithoutImage() {
        XCTAssertEqual(PromptBudget.promptLimit(nCtx: 4096, maxGenTokens: 400), 4096 - 400 - 64)
        XCTAssertEqual(PromptBudget.promptLimit(nCtx: 4096, maxGenTokens: 220), 4096 - 220 - 64)
        XCTAssertEqual(PromptBudget.decodeCap(nCtx: 4096, maxGenTokens: 400), 4096 - 400)
    }

    func testPromptLimit4096WithImage() {
        let image = VisionEvalBudget.imageMaxTokens
        XCTAssertEqual(
            PromptBudget.promptLimit(nCtx: 4096, maxGenTokens: 400, imageTokens: image),
            4096 - 400 - image - 64
        )
        XCTAssertEqual(
            PromptBudget.promptLimit(nCtx: 4096, maxGenTokens: 220, imageTokens: image),
            4096 - 220 - image - 64
        )
    }

    func testOver4096FixtureGetsTrimmedToFit() {
        let nCtx = 4096
        let maxGen = 400
        let limit = PromptBudget.promptLimit(nCtx: nCtx, maxGenTokens: maxGen)
        let parts = [
            PromptBudget.Part(rank: 1, text: String(repeating: "keep ", count: 800)),
            PromptBudget.Part(rank: 2, text: String(repeating: "passage ", count: 4_000)),
            PromptBudget.Part(rank: 9, text: String(repeating: "source ", count: 8_000)),
        ]
        let raw = parts.reduce(0) { $0 + PromptBudget.estimateTokens($1.text) }
        XCTAssertGreaterThan(raw, nCtx)
        let trimmed = PromptBudget.trim(parts, limit: limit)
        let total = trimmed.reduce(0) { $0 + PromptBudget.estimateTokens($1.text) }
        XCTAssertLessThanOrEqual(total, limit)
        XCTAssertLessThanOrEqual(total, PromptBudget.decodeCap(nCtx: nCtx, maxGenTokens: maxGen))
        XCTAssertTrue(trimmed.contains(where: { $0.rank == 1 }))
        XCTAssertFalse(trimmed.contains(where: { $0.rank == 9 }))
    }

    func testPromptDecodeErrorIncludesCounts() {
        let error = LlamaRunnerError.promptDecodeFailed(rc: 1, promptTokens: 3800, nCtx: 4096)
        XCTAssertEqual(error.errorDescription, "Prompt decode failed (rc=1 promptTokens=3800 nCtx=4096).")
        XCTAssertTrue(LlamaRunnerError.isPromptDecodeFailure(error))
    }

    func testLinkDetectorFindsURLAndDOI() {
        XCTAssertEqual(
            LinkDetector.urlOrDOI(in: "see https://arxiv.org/abs/1706.03762 for details")?.absoluteString,
            "https://arxiv.org/abs/1706.03762"
        )
        XCTAssertEqual(
            LinkDetector.urlOrDOI(in: "doi 10.5555/3295222.3295349")?.absoluteString,
            "https://doi.org/10.5555/3295222.3295349"
        )
        XCTAssertNil(LinkDetector.urlOrDOI(in: "no link here"))
    }
}
