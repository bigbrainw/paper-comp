import XCTest
@testable import PaperComp

final class AnswerMathTests: XCTestCase {
    func testStripsInlineDollars() {
        XCTAssertEqual(AnswerMath.render("The pole is at $1/f$."), "The pole is at 1/f.")
        XCTAssertFalse(AnswerMath.render("See $1/f$ noise.").contains("$"))
    }

    func testGreekAndScripts() {
        XCTAssertEqual(AnswerMath.render("$\\mu$V"), "μV")
        XCTAssertEqual(AnswerMath.render("$x^2$"), "x²")
        XCTAssertEqual(AnswerMath.render("$x_2$"), "x₂")
        XCTAssertEqual(AnswerMath.render("$x^{2}$"), "x²")
    }

    func testFracAndUnmatchedDollars() {
        XCTAssertEqual(AnswerMath.render("$\\frac{1}{f}$"), "1/f")
        XCTAssertFalse(AnswerMath.render("leftover $1/f").contains("$"))
    }
}
