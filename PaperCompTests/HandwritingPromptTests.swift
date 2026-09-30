import XCTest
@testable import PaperComp

@MainActor
final class HandwritingPromptTests: XCTestCase {
    func testOnlinePromptIncludesHandwritingOCR() {
        let capture = CircleCapture(
            documentID: UUID(),
            paperTitle: "Notes",
            pageIndex: 0,
            pageRect: CGRect(x: 0, y: 0, width: 40, height: 20),
            selectedText: "",
            handwritingText: "margin note: check fig 2",
            containsInk: true,
            image: UIImage(),
            surroundingText: ""
        )
        let prompt = SearchAgent.prompt(for: capture, question: "What did I write?")
        XCTAssertTrue(prompt.contains("Handwriting (OCR)"))
        XCTAssertTrue(prompt.contains("margin note: check fig 2"))
        XCTAssertFalse(prompt.contains("no readable text"))
    }

    func testOnlinePromptKeepsSelectedTextAndHandwritingSeparate() {
        let capture = CircleCapture(
            documentID: UUID(),
            paperTitle: "Paper",
            pageIndex: 1,
            pageRect: CGRect(x: 0, y: 0, width: 40, height: 20),
            selectedText: "attention",
            handwritingText: "my underline note",
            containsInk: true,
            image: UIImage(),
            surroundingText: "context"
        )
        let prompt = SearchAgent.prompt(for: capture, question: "Explain")
        XCTAssertTrue(prompt.contains("Selected passage"))
        XCTAssertTrue(prompt.contains("attention"))
        XCTAssertTrue(prompt.contains("Handwriting (OCR)"))
        XCTAssertTrue(prompt.contains("my underline note"))
    }

    func testWithHandwritingTextPreservesInkFlag() {
        let base = CircleCapture(
            documentID: UUID(),
            paperTitle: "N",
            pageIndex: 0,
            pageRect: .zero,
            selectedText: "",
            containsInk: true,
            image: UIImage(),
            surroundingText: ""
        )
        let updated = base.withHandwritingText("hello")
        XCTAssertEqual(updated.handwritingText, "hello")
        XCTAssertTrue(updated.containsInk)
        XCTAssertTrue(updated.selectedText.isEmpty)
    }

    func testTextOnlyModelUsesOCROrReportsVisionNeed() {
        let withOCR = CapturePromptText.resolve(
            selectedText: "", handwritingText: "ink words", containsInk: true, hasProjector: false
        )
        XCTAssertEqual(withOCR.text, "ink words")
        XCTAssertFalse(withOCR.needsVisionCapableModel)

        let noOCR = CapturePromptText.resolve(
            selectedText: "", handwritingText: "", containsInk: true, hasProjector: false
        )
        XCTAssertTrue(noOCR.text.isEmpty)
        XCTAssertTrue(noOCR.needsVisionCapableModel)

        let vision = CapturePromptText.resolve(
            selectedText: "", handwritingText: "", containsInk: true, hasProjector: true
        )
        XCTAssertTrue(vision.text.isEmpty)
        XCTAssertFalse(vision.needsVisionCapableModel)

        let noInk = CapturePromptText.resolve(
            selectedText: "", handwritingText: "", containsInk: false, hasProjector: false
        )
        XCTAssertFalse(noInk.needsVisionCapableModel)
    }
}
