import XCTest
@testable import PaperComp

@MainActor
final class SearchAgentPromptTests: XCTestCase {
    func testPromptUsesSelectedPassageLabels() {
        let capture = CircleCapture(
            documentID: UUID(),
            paperTitle: "Noise",
            pageIndex: 2,
            pageRect: CGRect(x: 0, y: 0, width: 10, height: 10),
            selectedText: "1/f noise",
            image: UIImage(),
            surroundingText: "Input-referred noise of the circuit."
        )
        let prompt = SearchAgent.prompt(for: capture, question: "What is this?")
        XCTAssertTrue(prompt.contains("Selected passage"))
        XCTAssertTrue(prompt.contains("Paper context"))
        XCTAssertFalse(prompt.localizedCaseInsensitiveContains("circled"))
        XCTAssertFalse(prompt.localizedCaseInsensitiveContains("surrounding text"))
        XCTAssertTrue(SearchSettings.instructions.contains("Answer the user's question directly"))
        XCTAssertTrue(SearchSettings.instructions.contains("[S1]"))
    }
}
