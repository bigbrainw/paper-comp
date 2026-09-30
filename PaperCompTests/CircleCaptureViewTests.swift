import Testing
import UIKit
@testable import PaperComp

@MainActor
struct CircleCaptureViewTests {
    @Test func doesNotInterceptTouches() {
        let view = CircleCaptureView(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        view.isActive = true
        #expect(view.isUserInteractionEnabled == false)
        #expect(view.hitTest(CGPoint(x: 200, y: 200), with: nil) == nil)
    }

    @Test func hiddenWhenSearchToolOff() {
        let view = CircleCaptureView(frame: .zero)
        view.isActive = false
        #expect(view.isHidden)
    }

    @Test func clearOverlayRemovesPathAndHides() {
        let view = CircleCaptureView(frame: CGRect(x: 0, y: 0, width: 400, height: 400))
        view.isActive = true
        view.isHidden = false
        view.clearOverlay()
        #expect(view.isHidden)
        #expect(view.hitTest(CGPoint(x: 50, y: 50), with: nil) == nil)
    }
}
