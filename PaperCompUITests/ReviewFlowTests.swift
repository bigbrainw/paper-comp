import XCTest

/// The App Review path without an Apple Pencil: empty library → "Try a sample paper" → Search →
/// one-finger box → search card. "Draw with finger" is forced off. Scratch library = empty, and the
/// simulator's real library is untouched.
@MainActor
final class ReviewFlowTests: XCTestCase {
    private func launch(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-PCUITest", "-PCScratchLibrary", "-allowFingerDrawing", "NO"] + extra
        app.launch()
        return app
    }

    private func snapshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testSamplePaperAndFingerBoxSearch() {
        let app = launch()

        let sample = app.buttons["library.sample"]
        XCTAssertTrue(sample.waitForExistence(timeout: 10), "empty library should offer the sample paper")
        snapshot("review-empty-library")
        sample.tap()

        let search = app.buttons["Search"]
        XCTAssertTrue(search.waitForExistence(timeout: 10), "sample should open in the reader")
        sleep(2)
        snapshot("review-sample-open")

        search.tap()
        sleep(1)
        // One-finger drag across the abstract (upper left column of page 1).
        let window = app.windows.firstMatch
        let start = window.coordinate(withNormalizedOffset: CGVector(dx: 0.14, dy: 0.30))
        let end = window.coordinate(withNormalizedOffset: CGVector(dx: 0.48, dy: 0.36))
        start.press(forDuration: 0.15, thenDragTo: end)

        let host = app.otherElements["search.card.host"]
        XCTAssertTrue(host.waitForExistence(timeout: 10), "a finger box should open the search card")
        sleep(2)
        snapshot("review-finger-search")
    }

    func testAboutShowsBundledPrivacyPolicy() {
        let app = launch(["-PCOpenSettings"])
        let privacy = app.buttons["settings.about.privacy"]
        let form = app.collectionViews.firstMatch
        XCTAssertTrue(form.waitForExistence(timeout: 10))
        for _ in 0..<8 where !privacy.isHittable { form.swipeUp() }
        XCTAssertTrue(privacy.waitForExistence(timeout: 5), "Settings should have About → Privacy Policy")
        snapshot("review-about-section")
        privacy.tap()

        let heading = app.webViews.staticTexts["PaperComp Privacy Policy"]
        XCTAssertTrue(heading.waitForExistence(timeout: 10), "bundled privacy page should load")
        sleep(1)
        snapshot("review-about-privacy")
    }
}
