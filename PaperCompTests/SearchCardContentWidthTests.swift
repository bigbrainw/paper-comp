import SwiftUI
import UIKit
import XCTest
@testable import PaperComp

@MainActor
final class SearchCardContentWidthTests: XCTestCase {
    override func setUp() {
        super.setUp()
        for key in ["searchCardSize.portrait", "searchCardSize.landscape",
                    "searchCardPos.portrait", "searchCardPos.landscape"] {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    func testCardContentWidthEqualsCardWidthAt420() {
        let screen = CGSize(width: 1024, height: 1366)
        let container = ReaderCanvasContainer(frame: CGRect(origin: .zero, size: screen))
        let session = SearchCardSession()
        let capture = CircleCapture(
            documentID: UUID(),
            paperTitle: "Width",
            pageIndex: 0,
            pageRect: CGRect(x: 10, y: 10, width: 80, height: 20),
            selectedText: "1/f noise",
            image: UIImage(),
            surroundingText: ""
        )
        session.showCapture(
            capture,
            anchor: CGRect(x: 40, y: 80, width: 100, height: 30),
            onClose: {},
            onAnswered: { _, _, _ in }
        )

        let window = UIWindow(frame: CGRect(origin: .zero, size: screen))
        let root = UIViewController()
        root.view.addSubview(container)
        container.frame = root.view.bounds
        container.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        window.rootViewController = root
        window.makeKeyAndVisible()

        container.updateSearchCard(session: session)
        if let controller = container.cardHost?.hostingController {
            root.addChild(controller)
            controller.didMove(toParent: root)
        }

        SearchCardLayoutProbe.contentWidth = 0
        var cardFrame = CGRect.zero
        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline {
            window.layoutIfNeeded()
            container.layoutIfNeeded()
            container.cardHost?.layoutIfNeeded()
            container.cardHost?.hostingController?.view.layoutIfNeeded()
            if let frame = container.cardHost?.visibleCardFrame, frame.width > 100 {
                cardFrame = frame
            }
            if cardFrame.width > 100, SearchCardLayoutProbe.contentWidth > 100 { break }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }

        XCTAssertEqual(cardFrame.width, SearchCardPlacement.cardWidth, accuracy: 1.5)
        XCTAssertEqual(SearchCardLayoutProbe.contentWidth, SearchCardPlacement.cardWidth, accuracy: 2)
        XCTAssertLessThan(cardFrame.width, screen.width - 20)
        XCTAssertLessThan(SearchCardLayoutProbe.contentWidth, screen.width - 20)
    }
}

extension UIView {
    func firstDescendant(identifier: String) -> UIView? {
        if accessibilityIdentifier == identifier { return self }
        for child in subviews {
            if let found = child.firstDescendant(identifier: identifier) { return found }
        }
        return nil
    }
}
