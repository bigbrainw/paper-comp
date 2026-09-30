import SwiftUI
import UIKit

/// Threshold/state logic for “pull past last page to append a note”.
enum PullToAddPage {
    static let bounceTolerance: CGFloat = 8
    static let defaultThreshold: CGFloat = 90

    enum State: Equatable {
        case idle
        case pulling(progress: CGFloat)
        case armed

        var isVisible: Bool {
            switch self {
            case .idle: false
            case .pulling, .armed: true
            }
        }

        var progress: CGFloat {
            switch self {
            case .idle: 0
            case .pulling(let progress): min(max(progress, 0), 1)
            case .armed: 1
            }
        }

        var isArmed: Bool {
            if case .armed = self { return true }
            return false
        }
    }

    /// Points scrolled past the bottom of the document (scroll-view coordinates).
    static func overscroll(
        contentOffsetY: CGFloat,
        boundsHeight: CGFloat,
        adjustedContentInsetBottom: CGFloat,
        contentSizeHeight: CGFloat
    ) -> CGFloat {
        contentOffsetY + boundsHeight - adjustedContentInsetBottom - contentSizeHeight
    }

    /// Maps bottom overscroll into idle / pulling / armed. Values under `bounceTolerance` stay idle.
    static func state(overscroll: CGFloat, threshold: CGFloat = defaultThreshold) -> State {
        guard overscroll >= bounceTolerance else { return .idle }
        if overscroll >= threshold { return .armed }
        return .pulling(progress: min(max(overscroll / threshold, 0), 1))
    }
}

/// Rice-paper capsule shown below the last page while pulling.
struct PullToAddPagePill: View {
    let state: PullToAddPage.State

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "plus.circle")
                .font(.subheadline.weight(.semibold))
            Text(state.isArmed ? "Release to add page" : "Pull to add page")
                .font(.subheadline.weight(.medium))
        }
        .foregroundStyle(state.isArmed ? Theme.accent : Theme.ink)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background {
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay { Capsule().fill(Theme.riceSurface.opacity(0.92)) }
        }
        .shadow(color: Theme.ink.opacity(0.12), radius: 8, y: 2)
        .opacity(Double(state.progress))
        .accessibilityIdentifier("reader.pullToAdd.pill")
        .accessibilityLabel(state.isArmed ? "Release to add page" : "Pull to add page")
    }
}
