import XCTest
@testable import PaperComp

final class AnswerMarkdownTests: XCTestCase {
    func testBoldAndHeadingLeaveNoRawAsterisks() {
        let rendered = AnswerMarkdown.nsAttributed(
            "### VDDL\n\n**What it is:** the low supply rail.",
            ink: .black
        )
        XCTAssertFalse(rendered.string.contains("**"))
        XCTAssertTrue(rendered.string.contains("What it is:"))
        XCTAssertTrue(rendered.string.contains("VDDL"))
    }

    func testInlineMarkdownHelper() {
        let inline = MarkdownText.inline("**In short:** hello")
        XCTAssertFalse(String(inline.characters).contains("**"))
        XCTAssertTrue(String(inline.characters).contains("In short:"))
    }
}
