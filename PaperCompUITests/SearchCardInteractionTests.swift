import XCTest

@MainActor
final class SearchCardInteractionTests: XCTestCase {
    func testCloseButtonDismissesSearchCard() {
        let app = XCUIApplication()
        app.launchArguments += ["-PCUITest", "-PCSeedSamplePaper", "-PCOpenFirstPaper", "-PCSampleCapture"]
        app.launch()

        let host = app.otherElements["search.card.host"]
        XCTAssertTrue(host.waitForExistence(timeout: 12), "search card host should appear")

        let close = host.buttons["search.card.close"]
        XCTAssertTrue(close.waitForExistence(timeout: 8), "search card close button should appear")
        XCTAssertTrue(host.exists)

        close.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()

        XCTAssertTrue(host.waitForNonExistence(timeout: 6), "close should dismiss the search card")
        XCTAssertFalse(app.buttons["search.card.close"].exists)
    }

    func testExplainChipIsTappable() {
        let app = XCUIApplication()
        app.launchArguments += ["-PCUITest", "-PCSeedSamplePaper", "-PCOpenFirstPaper", "-PCSampleCapture"]
        app.launch()

        let host = app.otherElements["search.card.host"]
        XCTAssertTrue(host.waitForExistence(timeout: 12), "search card host should appear")
        let explain = host.buttons["Explain"]
        XCTAssertTrue(explain.waitForExistence(timeout: 8), "Explain chip should be tappable")
        explain.tap()
        XCTAssertTrue(explain.exists)
    }
}
