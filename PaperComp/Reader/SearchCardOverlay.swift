import SwiftUI
import UIKit

/// Card chrome + panel, driven by `SearchCardSession` so the UIKit host never rebuilds `rootView`.
/// Full-screen UIKit host above the chrome; `point(inside:)` is only the card.
struct SearchCardLayer: UIViewRepresentable {
    @Bindable var session: SearchCardSession

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> SearchCardHostView {
        context.coordinator.revision = session.revision
        let host = SearchCardHostView()
        host.backgroundColor = .clear
        host.isOpaque = false
        let controller = UIHostingController(rootView: SearchCardRootView(session: session))
        controller.sizingOptions = [.intrinsicContentSize]
        controller.view.backgroundColor = .clear
        controller.view.isOpaque = false
        controller.safeAreaRegions = []
        host.install(controller)
        host.closeHandler = session.onClose
        return host
    }

    func updateUIView(_ host: SearchCardHostView, context: Context) {
        host.closeHandler = session.onClose
        guard context.coordinator.revision != session.revision else { return }
        context.coordinator.revision = session.revision
        host.hostingController?.rootView = SearchCardRootView(session: session)
    }

    final class Coordinator {
        var revision = ""
    }
}

struct SearchCardRootView: View {
    @Bindable var session: SearchCardSession

    var body: some View {
        Group {
            if session.isPresented {
                SearchCardOverlay(session: session)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct SearchCardOverlay: View {
    @Bindable var session: SearchCardSession

    var body: some View {
        GeometryReader { _ in
            ZStack(alignment: .topLeading) {
                Color.clear.allowsHitTesting(false)
                FloatingSearchCard(
                    anchor: session.anchor,
                    title: session.title,
                    onClose: session.onClose,
                    startMinimized: session.startMinimized
                ) {
                    cardBody
                }
                .onPreferenceChange(SearchCardFrameKey.self) { session.interactiveFrame = $0 }
            }
        }
    }

    @ViewBuilder
    private var cardBody: some View {
        if let capture = session.capture {
            SearchPanel(capture: capture, onClose: session.onClose, onAnswered: session.onAnswered)
                .id(capture.id)
        } else if let marker = session.marker {
            SavedSearchPanel(marker: marker, records: session.savedRecords, onDelete: { session.onDeleteSaved?() })
        }
    }
}

/// Whether PDF-level capture gestures should begin at a point (inverse of the card rect).
enum SearchCardGestureFilter {
    static func shouldAllowPDFCapture(at point: CGPoint, cardInteractiveFrame: CGRect) -> Bool {
        guard cardInteractiveFrame.width > 1, cardInteractiveFrame.height > 1 else { return true }
        return !cardInteractiveFrame.contains(point)
    }
}

/// Invisible UIKit view matching the visible card; `SearchCardHostView` uses it for hit-testing.
struct SearchCardHitAnchor: UIViewRepresentable {
    func makeUIView(context: Context) -> SearchCardHitAnchorView { SearchCardHitAnchorView() }
    func updateUIView(_ uiView: SearchCardHitAnchorView, context: Context) {}
}

final class SearchCardHitAnchorView: UIView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .clear
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        findHost()?.cardAnchor = self
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if let host = findHost() {
            host.cardAnchor = self
            host.layoutCloseControl()
        }
    }

    private func findHost() -> SearchCardHostView? {
        var current = superview
        while let view = current {
            if let host = view as? SearchCardHostView { return host }
            current = view.superview
        }
        return nil
    }
}
