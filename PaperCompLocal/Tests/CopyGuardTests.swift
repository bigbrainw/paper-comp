import XCTest
@testable import PaperComp

final class CopyGuardTests: XCTestCase {
    let passage = "1/f noise is typically mitigated by dynamic circuit techniques such as chopping and auto-zeroing"

    func testCopiedAnswerIsAboveThirtyPercent() {
        let copied = "1/f noise is typically mitigated by dynamic circuit techniques such as chopping and auto-zeroing in CMOS."
        let ratio = CopyGuard.ratio(answer: copied, against: [passage])
        XCTAssertGreaterThan(ratio, 0.30)
        XCTAssertTrue(CopyGuard.copies(copied, against: [passage]))
    }

    func testGoodAnswerIsBelowTenPercent() {
        let good = """
            Flicker noise is a slow wobble in voltage that gets worse at low frequency. \
            Chopping and auto-zeroing flip or subtract that wobble so it leaves the band you care about.
            """
        let ratio = CopyGuard.ratio(answer: good, against: [passage])
        XCTAssertLessThan(ratio, 0.10)
        XCTAssertFalse(CopyGuard.copies(good, against: [passage]))
    }
}

final class HardTermDetectorTests: XCTestCase {
    func testParsesLinesAndDropsCommonWords() {
        let output = """
            1/f noise
            dynamic circuit techniques
            the
            typically
            """
        XCTAssertEqual(HardTermDetector.parse(output), ["1/f noise", "dynamic circuit techniques"])
    }

    func testFallbackKeepsTechnicalPhrases() {
        let terms = HardTermDetector.fallback(
            from: "1/f noise is typically mitigated by dynamic circuit techniques"
        )
        XCTAssertTrue(terms.contains(where: { $0.localizedCaseInsensitiveContains("1/f") }))
    }

    func testTermsDropLeakedReasoningAndKeepPassageTerms() {
        let passage = "The IA block talks to the Backend over a bus; VDD is the core supply."
        let output = """
            <think>
            Okay, let's see. The user wants me to list technical terms
            First, I need to
            </think>
            Okay, let's see. The user wants me to list technical terms
            First, I need to
            IA
            Backend
            VDD
            """
        XCTAssertEqual(HardTermDetector.terms(from: output, passage: passage), ["IA", "Backend", "VDD"])
    }

    func testTermsDropUnterminatedThinkAndTermsNotInPassage() {
        let passage = "Chopping and auto-zeroing remove 1/f noise."
        let output = "auto zeroing\nquantum tunneling\n<think>\nOkay, let's see. The user wants"
        XCTAssertEqual(HardTermDetector.terms(from: output, passage: passage), ["auto zeroing"])
    }

    func testTermsFallBackWhenOnlyReasoningSurvives() {
        let passage = "1/f noise is typically mitigated by dynamic circuit techniques"
        let terms = HardTermDetector.terms(from: "First, I need to\nOkay, let's see.", passage: passage)
        XCTAssertEqual(terms, HardTermDetector.fallback(from: passage))
        XCTAssertFalse(terms.isEmpty)
    }

    func testIsReasoningFlagsSentenceLikeLines() {
        XCTAssertTrue(HardTermDetector.isReasoning("Okay, let's see. The user wants me to list technical terms"))
        XCTAssertTrue(HardTermDetector.isReasoning("First, I need to"))
        XCTAssertTrue(HardTermDetector.isReasoning("Terms:"))
        XCTAssertFalse(HardTermDetector.isReasoning("dynamic circuit techniques"))
        XCTAssertFalse(HardTermDetector.occurs("IA", in: "sent via the bus"))
        XCTAssertTrue(HardTermDetector.occurs("auto zeroing", in: "uses auto-zeroing."))
    }

    func testParseDropsPlaceholderLines() {
        XCTAssertEqual(HardTermDetector.parse("the hard concepts here\n1/f noise"), ["1/f noise"])
        XCTAssertTrue(HardTermDetector.isPlaceholder("the hard concepts here"))
    }
}

final class LlamaSamplerSpecTests: XCTestCase {
    func testTeachChainPutsPenaltiesBeforeTempAndAddsMinP() {
        XCTAssertEqual(LlamaSamplerSpec.teach.chainSteps, ["penalties", "min_p", "temp", "top_p", "dist"])
        XCTAssertEqual(LlamaSamplerSpec.teach.temperature, 0.6)
        XCTAssertEqual(LlamaSamplerSpec.teach.minP, 0.05)
        XCTAssertEqual(LlamaSamplerSpec.teach.penaltyLastN, 64)
        XCTAssertEqual(LlamaSamplerSpec.teach.penaltyRepeat, 1.15, accuracy: 0.001)
        XCTAssertEqual(LlamaSamplerSpec.teach.maxTokens, 400)
    }

    func testBreakdownUses220Tokens() {
        XCTAssertEqual(LlamaSamplerSpec.breakdown.maxTokens, 220)
        XCTAssertEqual(LlamaSamplerSpec.fitTogether.maxTokens, 160)
    }

    func testDetectIsShortAndCool() {
        XCTAssertEqual(LlamaSamplerSpec.detect.chainSteps, ["temp", "top_p", "dist"])
        XCTAssertEqual(LlamaSamplerSpec.detect.temperature, 0.2)
        XCTAssertEqual(LlamaSamplerSpec.detect.maxTokens, 60)
    }
}
