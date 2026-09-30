import XCTest
@testable import PaperComp

final class VisionSendPolicyTests: XCTestCase {
    func testShortFragmentedAndFigureCaptionsAreVisual() {
        XCTAssertTrue(VisionSendPolicy.isVisualSelection(""))
        XCTAssertTrue(VisionSendPolicy.isVisualSelection("Fig. 2"))
        XCTAssertTrue(VisionSendPolicy.isVisualSelection("Table 1. Results"))
        XCTAssertTrue(VisionSendPolicy.isVisualSelection("see Equation (3)"))
        XCTAssertTrue(VisionSendPolicy.isVisualSelection("a\nb\nc\nd"))
        XCTAssertTrue(VisionSendPolicy.isVisualSelection("x = α + β + γ"))
    }

    func testLongProseIsNotVisualButStillSendsImageByDefault() {
        let prose = String(repeating: "Attention is a mapping of queries to keys. ", count: 6)
        XCTAssertFalse(VisionSendPolicy.isVisualSelection(prose))
        XCTAssertTrue(VisionSendPolicy.shouldSendImage(selectedText: prose, hasProjector: true))
        XCTAssertFalse(VisionSendPolicy.shouldSendImage(selectedText: prose, hasProjector: false))
    }

    func testQwenWithoutProjectorNeverSendsImage() {
        XCTAssertFalse(VisionSendPolicy.shouldSendImage(selectedText: "Fig. 1", hasProjector: false))
    }
}
