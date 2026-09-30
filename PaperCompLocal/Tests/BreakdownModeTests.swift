import XCTest
@testable import PaperComp

final class BreakdownModeTests: XCTestCase {
    func testPerTermPromptHasThreePartsAndFewShot() {
        let user = BreakdownMode.user(
            term: "VDDL",
            sentences: "A1 is supplied by VDDL.",
            wiki: "Low-voltage digital supply.",
            passage: "A1 runs on VDDL to save power.",
            brief: "An EEG front-end paper.",
            includesImage: true,
            retryMeta: false
        )
        XCTAssertTrue(user.contains("VDD"))
        XCTAssertTrue(user.contains("What it is:"))
        XCTAssertTrue(user.contains("Analogy:"))
        XCTAssertTrue(user.contains("Why it's here:"))
        XCTAssertTrue(user.contains("Do not say 'these terms'"))
        XCTAssertTrue(user.contains("VDDL"))
        XCTAssertTrue(user.contains("[S1] Wikipedia"))
        XCTAssertTrue(user.contains("attached as an image"))
        XCTAssertFalse(user.contains("Explain the concept itself."))
    }

    func testMetaDetector() {
        XCTAssertTrue(BreakdownMode.isMeta("These terms describe the power supplies."))
        XCTAssertTrue(BreakdownMode.isMeta("This passage shows an amplifier."))
        XCTAssertTrue(BreakdownMode.isMeta("The text describes the figure."))
        XCTAssertFalse(BreakdownMode.isMeta("What it is: VDDL is the low supply rail."))
        XCTAssertTrue(BreakdownMode.shouldRegenerate("These terms describe the setup."))
    }

    func testIncompleteMissingParts() {
        XCTAssertTrue(BreakdownMode.isIncomplete("What it is: a supply.\n"))
        XCTAssertFalse(BreakdownMode.isIncomplete("""
            What it is: VDDL is the low supply.
            Analogy: a dimmer switch.
            Why it's here: it powers A1 in Fig. 11.
            """))
    }

    func testHeaderAndSingleTerm() {
        XCTAssertEqual(BreakdownMode.header(terms: ["VDDL", "VDDH", "AC-coupled"]),
                       "Breaking down: VDDL · VDDH · AC-coupled")
        XCTAssertEqual(BreakdownMode.singleTerm(from: "Break down only: VDDL"), "VDDL")
        XCTAssertTrue(BreakdownMode.shouldRun("Breaking down: VDDL · VDDH"))
        XCTAssertFalse(BreakdownMode.shouldRun("Define VDDL in plain language."))
        XCTAssertFalse(BreakdownMode.shouldRun("Explain this passage to a first-year undergraduate, with an analogy."))
    }

    func testAssembleMarkdown() {
        let text = BreakdownMode.assemble(
            terms: ["VDDL", "VDDH"],
            sections: ["What it is: low rail.", "What it is: high rail."],
            fitTogether: "A1 is low-swing; A2 needs the high rail."
        )
        XCTAssertTrue(text.contains("### VDDL"))
        XCTAssertTrue(text.contains("### How they fit together"))
    }
}
