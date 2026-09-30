import SwiftUI
import XCTest
@testable import PaperComp

@MainActor
final class LocalModelAvailabilityBodyTests: XCTestCase {
    func testAvailabilityAndSearchPanelBodyDoNoFileIOOrMutations() {
        _ = ModelManager.shared
        ModelManagerIOProbe.reset()
        let snapshot = ModelManager.shared.states

        let capture = CircleCapture(
            documentID: UUID(),
            paperTitle: "Probe",
            pageIndex: 0,
            pageRect: CGRect(x: 0, y: 0, width: 40, height: 20),
            selectedText: "token",
            image: UIImage(),
            surroundingText: ""
        )
        let panel = SearchPanel(capture: capture, onClose: {})

        for _ in 0..<40 {
            _ = LocalModelStatus.availability()
            _ = panel.body
            _ = SearchAgent(capture: capture).needsLocalModelDownload
        }

        XCTAssertEqual(ModelManagerIOProbe.fileIOCount, 0, "availability/body must not touch the models directory")
        XCTAssertEqual(ModelManagerIOProbe.mutationCount, 0, "availability/body must not write observable state")
        XCTAssertEqual(ModelManager.shared.states, snapshot)
    }
}
