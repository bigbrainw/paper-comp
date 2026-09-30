import Foundation
import Testing
@testable import PaperComp

struct PullToAddPageTests {
    @Test func overscrollMathIsBottomPastEnd() {
        // contentOffset.y + bounds - inset.bottom - contentSize
        let value = PullToAddPage.overscroll(
            contentOffsetY: 900,
            boundsHeight: 800,
            adjustedContentInsetBottom: 20,
            contentSizeHeight: 1600
        )
        #expect(abs(value - 80) < 0.01)
    }

    @Test func smallBounceStaysIdle() {
        #expect(PullToAddPage.state(overscroll: 0) == .idle)
        #expect(PullToAddPage.state(overscroll: 7.9) == .idle)
        #expect(PullToAddPage.state(overscroll: -12) == .idle)
    }

    @Test func pullingProgressBetweenBounceAndThreshold() {
        let mid = PullToAddPage.state(overscroll: 45)
        guard case .pulling(let progress) = mid else {
            Issue.record("expected pulling at 45pt")
            return
        }
        #expect(abs(progress - 0.5) < 0.01)

        let justPastBounce = PullToAddPage.state(overscroll: 8)
        guard case .pulling(let low) = justPastBounce else {
            Issue.record("expected pulling at bounce floor")
            return
        }
        #expect(low > 0 && low < 1)

        let nearArm = PullToAddPage.state(overscroll: 89.9)
        guard case .pulling(let high) = nearArm else {
            Issue.record("expected pulling just under threshold")
            return
        }
        #expect(high < 1)
        #expect(high > 0.9)
    }

    @Test func armedAtDefaultThreshold() {
        #expect(PullToAddPage.state(overscroll: 90) == .armed)
        #expect(PullToAddPage.state(overscroll: 120) == .armed)
    }

    @Test func customThreshold() {
        #expect(PullToAddPage.state(overscroll: 40, threshold: 50) == .pulling(progress: 0.8))
        #expect(PullToAddPage.state(overscroll: 50, threshold: 50) == .armed)
        #expect(PullToAddPage.state(overscroll: 7, threshold: 50) == .idle)
    }

    @Test func stateVisibilityAndProgressHelpers() {
        #expect(!PullToAddPage.State.idle.isVisible)
        #expect(PullToAddPage.State.pulling(progress: 0.3).isVisible)
        #expect(PullToAddPage.State.armed.isVisible)
        #expect(PullToAddPage.State.armed.progress == 1)
        #expect(PullToAddPage.State.armed.isArmed)
        #expect(!PullToAddPage.State.pulling(progress: 0.5).isArmed)
    }
}
