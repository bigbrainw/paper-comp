import CoreGraphics
import Testing
import UIKit
@testable import PaperComp

struct SearchCardGestureFilterTests {
    @Test func allowsPDFCaptureOutsideCard() {
        let card = CGRect(x: 100, y: 80, width: 340, height: 300)
        #expect(SearchCardGestureFilter.shouldAllowPDFCapture(at: CGPoint(x: 50, y: 50), cardInteractiveFrame: card))
        #expect(SearchCardGestureFilter.shouldAllowPDFCapture(at: CGPoint(x: 500, y: 400), cardInteractiveFrame: card))
    }

    @Test func blocksPDFCaptureInsideCard() {
        let card = CGRect(x: 100, y: 80, width: 340, height: 300)
        #expect(!SearchCardGestureFilter.shouldAllowPDFCapture(at: CGPoint(x: 200, y: 150), cardInteractiveFrame: card))
    }

    @Test func allowsWhenCardFrameUnknown() {
        #expect(SearchCardGestureFilter.shouldAllowPDFCapture(at: CGPoint(x: 10, y: 10), cardInteractiveFrame: .zero))
    }

    @Test func cardFrameBoundaryIsInclusive() {
        let card = CGRect(x: 100, y: 80, width: 340, height: 300)
        #expect(!SearchCardGestureFilter.shouldAllowPDFCapture(at: CGPoint(x: 100, y: 80), cardInteractiveFrame: card))
        #expect(!SearchCardGestureFilter.shouldAllowPDFCapture(at: CGPoint(x: 439, y: 379), cardInteractiveFrame: card))
        #expect(SearchCardGestureFilter.shouldAllowPDFCapture(at: CGPoint(x: 99.5, y: 80), cardInteractiveFrame: card))
    }
}

@MainActor
struct SearchCardHostViewTests {
    @Test func pointInsideOnlyOnVisibleCard() {
        let host = SearchCardHostView(frame: CGRect(x: 0, y: 0, width: 800, height: 1000))
        host.visibleCardFrameOverride = CGRect(x: 100, y: 80, width: 340, height: 300)
        #expect(host.point(inside: CGPoint(x: 200, y: 150), with: nil))
        #expect(!host.point(inside: CGPoint(x: 10, y: 10), with: nil))
        #expect(host.hitTest(CGPoint(x: 10, y: 10), with: nil) == nil)
        #expect(host.shouldAllowPDFCapture(at: CGPoint(x: 10, y: 10)))
        #expect(!host.shouldAllowPDFCapture(at: CGPoint(x: 200, y: 150)))
        #expect(host.accessibilityIdentifier == "search.card.host")
        #expect(host.isAccessibilityElement == false)
    }
}

@MainActor
struct SearchCardHostInstallTests {
    @Test func dragAndStreamDoNotReplaceRootView() {
        SearchCardHostProbe.reset()
        let container = ReaderCanvasContainer(frame: CGRect(x: 0, y: 0, width: 800, height: 1000))
        let session = SearchCardSession()
        let capture = CircleCapture(
            documentID: UUID(),
            paperTitle: "Probe",
            pageIndex: 0,
            pageRect: CGRect(x: 0, y: 0, width: 40, height: 20),
            selectedText: "token",
            image: UIImage(),
            surroundingText: ""
        )
        session.showCapture(capture, anchor: CGRect(x: 40, y: 40, width: 80, height: 40), onClose: {}) { _, _, _ in }

        container.updateSearchCard(session: session)
        #expect(SearchCardHostProbe.rootViewAssignments == 1)
        #expect(container.cardHost != nil)

        for _ in 0..<20 {
            container.updateSearchCard(session: session)
        }
        #expect(SearchCardHostProbe.rootViewAssignments == 1, "drag/stream must not assign rootView again")

        let next = CircleCapture(
            documentID: capture.documentID,
            paperTitle: "Probe",
            pageIndex: 0,
            pageRect: CGRect(x: 10, y: 10, width: 40, height: 20),
            selectedText: "other",
            image: UIImage(),
            surroundingText: ""
        )
        session.showCapture(next, anchor: .zero, onClose: {}) { _, _, _ in }
        container.updateSearchCard(session: session)
        #expect(SearchCardHostProbe.rootViewAssignments == 2)

        session.dismiss()
        container.updateSearchCard(session: session)
        #expect(container.cardHost == nil)
    }

    @Test func closeCallbackRemovesHost() {
        SearchCardHostProbe.reset()
        let container = ReaderCanvasContainer(frame: CGRect(x: 0, y: 0, width: 800, height: 1000))
        let session = SearchCardSession()
        let capture = CircleCapture(
            documentID: UUID(),
            paperTitle: "Close",
            pageIndex: 0,
            pageRect: CGRect(x: 0, y: 0, width: 40, height: 20),
            selectedText: "token",
            image: UIImage(),
            surroundingText: ""
        )
        session.showCapture(capture, anchor: CGRect(x: 40, y: 40, width: 80, height: 40), onClose: {
            session.dismiss()
        }) { _, _, _ in }
        container.updateSearchCard(session: session)
        #expect(container.cardHost != nil)
        #expect(container.cardHost?.accessibilityIdentifier == "search.card.host")
        #expect(container.cardHost?.subviews.contains(where: {
            $0.accessibilityIdentifier == "search.card.close"
        }) == true)
        session.onClose()
        container.updateSearchCard(session: session)
        #expect(!session.isPresented)
        #expect(container.cardHost == nil)
    }
}
