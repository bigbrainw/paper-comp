import PDFKit
import SwiftUI
import UIKit

/// Stacks `PDFView` under a pass-through SwiftUI host so the search card sits in UIKit
/// above PencilKit/PDFKit and can win hit-testing.
final class ReaderCanvasContainer: UIView {
    let pdfView = PDFView()
    private(set) var cardHost: SearchCardHostView?
    private var lastCardRevision = ""
    private var pencilInteraction: UIPencilInteraction?
    private weak var pencilDelegate: UIPencilInteractionDelegate?
    private var pullPillHost: UIHostingController<PullToAddPagePill>?
    private var pullPillState: PullToAddPage.State = .idle

    override init(frame: CGRect) {
        super.init(frame: frame)
        pdfView.frame = bounds
        pdfView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(pdfView)
        if Self.hidesPDFAccessibility {
            pdfView.isAccessibilityElement = false
            pdfView.accessibilityElementsHidden = true
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil { attachPencilInteractionIfNeeded() }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        pdfView.frame = bounds
        cardHost?.frame = bounds
        layoutPullPill()
    }

    /// Shows or hides the pull-to-add capsule pinned above the bottom safe area.
    func setPullToAddState(_ state: PullToAddPage.State) {
        pullPillState = state
        guard state.isVisible else {
            pullPillHost?.view.isHidden = true
            return
        }
        if let pullPillHost {
            pullPillHost.rootView = PullToAddPagePill(state: state)
            pullPillHost.view.isHidden = false
            layoutPullPill()
            return
        }
        let host = UIHostingController(rootView: PullToAddPagePill(state: state))
        host.sizingOptions = [.intrinsicContentSize]
        host.view.backgroundColor = .clear
        host.view.isOpaque = false
        host.view.isUserInteractionEnabled = false
        addSubview(host.view)
        pullPillHost = host
        if let cardHost { bringSubviewToFront(cardHost) }
        layoutPullPill()
    }

    private func layoutPullPill() {
        guard let view = pullPillHost?.view, !view.isHidden else { return }
        let size = view.intrinsicContentSize
        let width = size.width > 1 ? size.width : 200
        let height = size.height > 1 ? size.height : 36
        let bottom = safeAreaInsets.bottom + 16
        view.frame = CGRect(
            x: (bounds.width - width) / 2,
            y: bounds.height - bottom - height,
            width: width,
            height: height
        )
        if let cardHost { bringSubviewToFront(cardHost) }
        else { bringSubviewToFront(view) }
    }

    /// Barrel tap must live on a view that stays in the window and is not covered by the card host.
    func installPencilInteraction(delegate: UIPencilInteractionDelegate) {
        pencilDelegate = delegate
        attachPencilInteractionIfNeeded()
    }

    func removePencilInteraction() {
        if let pencilInteraction {
            pencilInteraction.view?.removeInteraction(pencilInteraction)
        }
        pencilInteraction = nil
        pencilDelegate = nil
    }

    private func attachPencilInteractionIfNeeded() {
        guard let pencilDelegate else { return }
        let host = pencilHostView
        if let pencilInteraction, pencilInteraction.view === host {
            pencilInteraction.delegate = pencilDelegate
            return
        }
        if let pencilInteraction {
            pencilInteraction.view?.removeInteraction(pencilInteraction)
            self.pencilInteraction = nil
        }
        Self.stripPencilInteractions(from: host)
        Self.stripPencilInteractions(from: pdfView)
        let pencil = UIPencilInteraction()
        pencil.delegate = pencilDelegate
        host.addInteraction(pencil)
        pencilInteraction = pencil
    }

    /// The SwiftUI hosting view that contains both the paper and the floating chrome.
    private var pencilHostView: UIView {
        var current: UIView = self
        while let parent = current.superview {
            if parent.next is UIViewController { return parent }
            current = parent
        }
        return self
    }

    static func stripPencilInteractions(from view: UIView) {
        view.interactions.compactMap { $0 as? UIPencilInteraction }.forEach { view.removeInteraction($0) }
    }

    /// Installs or removes the card host. `rootView` is assigned only when `session.revision` changes.
    func updateSearchCard(session: SearchCardSession) {
        SearchCardHostProbe.updateSearchCardCalls += 1
        guard session.isPresented else {
            lastCardRevision = ""
            removeSearchCard()
            return
        }
        if cardHost != nil, lastCardRevision == session.revision { return }

        lastCardRevision = session.revision
        if let cardHost, let host = cardHost.hostingController {
            SearchCardHostProbe.rootViewAssignments += 1
            host.rootView = SearchCardRootView(session: session)
            if host.parent == nil { attach(host, in: cardHost) }
            setCardAccessibilityActive(true)
            return
        }

        let hostView = SearchCardHostView(frame: bounds)
        hostView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        let controller = UIHostingController(rootView: SearchCardRootView(session: session))
        controller.sizingOptions = [.intrinsicContentSize]
        controller.view.backgroundColor = .clear
        controller.view.isOpaque = false
        controller.safeAreaRegions = []
        hostView.install(controller)
        Self.stripPencilInteractions(from: hostView)
        if let hosted = controller.view { Self.stripPencilInteractions(from: hosted) }
        addSubview(hostView)
        cardHost = hostView
        attach(controller, in: hostView)
        bringSubviewToFront(hostView)
        setCardAccessibilityActive(true)
        SearchCardHostProbe.rootViewAssignments += 1
    }

    func removeSearchCard() {
        guard let cardHost else { return }
        if let controller = cardHost.hostingController {
            controller.willMove(toParent: nil)
            controller.view.removeFromSuperview()
            controller.removeFromParent()
        }
        cardHost.closeHandler = nil
        cardHost.removeFromSuperview()
        self.cardHost = nil
        setCardAccessibilityActive(false)
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hit = super.hitTest(point, with: event)
        #if DEBUG
        TouchProbe.logHitTest(point: point, hit: hit, host: "ReaderCanvasContainer")
        #endif
        return hit
    }

    private func attach(_ controller: UIHostingController<SearchCardRootView>, in hostView: SearchCardHostView) {
        if let parent = parentViewController {
            parent.addChild(controller)
            controller.didMove(toParent: parent)
        }
        hostView.frame = bounds
        setCardAccessibilityActive(true)
    }

    /// Keep XCTest / VoiceOver inside the card host so PDFKit's huge tree cannot stall queries.
    private func setCardAccessibilityActive(_ active: Bool) {
        pdfView.isAccessibilityElement = false
        pdfView.accessibilityElementsHidden = active || Self.hidesPDFAccessibility
        cardHost?.accessibilityViewIsModal = active
        cardHost?.isAccessibilityElement = false
        cardHost?.hostingController?.view.accessibilityElementsHidden = false
    }

    static var hidesPDFAccessibility: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-PCUITest")
        #else
        false
        #endif
    }
}

/// Full-size host. `point(inside:)` is true only inside the visible card chrome.
final class SearchCardHostView: UIView {
    weak var cardAnchor: SearchCardHitAnchorView?
    var visibleCardFrameOverride: CGRect?
    var closeHandler: (() -> Void)?
    private(set) var hostingController: UIHostingController<SearchCardRootView>?
    private let closeButton = UIButton(type: .custom)

    var visibleCardFrame: CGRect {
        if let visibleCardFrameOverride { return visibleCardFrameOverride }
        guard let cardAnchor, cardAnchor.bounds.width > 1 else { return .zero }
        return cardAnchor.convert(cardAnchor.bounds, to: self)
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        isUserInteractionEnabled = true
        isAccessibilityElement = false
        accessibilityIdentifier = "search.card.host"
        accessibilityContainerType = .semanticGroup
        closeButton.accessibilityIdentifier = "search.card.close"
        closeButton.accessibilityLabel = "Close"
        closeButton.accessibilityTraits = .button
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        addSubview(closeButton)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func install(_ controller: UIHostingController<SearchCardRootView>) {
        hostingController?.view.removeFromSuperview()
        hostingController = controller
        controller.sizingOptions = [.intrinsicContentSize]
        controller.view.backgroundColor = .clear
        controller.view.isOpaque = false
        controller.view.frame = bounds
        controller.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        controller.view.isAccessibilityElement = false
        controller.view.accessibilityElementsHidden = false
        controller.view.accessibilityIdentifier = "search.card.hosting"
        addSubview(controller.view)
        bringSubviewToFront(closeButton)
        layoutCloseControl()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        hostingController?.view.frame = bounds
        layoutCloseControl()
    }

    func layoutCloseControl() {
        let card = visibleCardFrame
        guard card.width > 1, card.height > 1 else {
            closeButton.frame = .zero
            return
        }
        closeButton.frame = CGRect(x: card.maxX - 46, y: card.minY + 26, width: 40, height: 40)
        bringSubviewToFront(closeButton)
    }

    @objc private func closeTapped() {
        if let closeHandler {
            closeHandler()
        } else {
            hostingController?.rootView.session.onClose()
        }
    }

    func shouldAllowPDFCapture(at point: CGPoint) -> Bool {
        SearchCardGestureFilter.shouldAllowPDFCapture(at: point, cardInteractiveFrame: visibleCardFrame)
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        let frame = visibleCardFrame
        guard frame.width > 1, frame.height > 1 else { return false }
        return frame.contains(point)
    }

    override func hitTest(_ location: CGPoint, with event: UIEvent?) -> UIView? {
        if closeButton.frame.contains(location), closeButton.bounds.width > 1 { return closeButton }
        guard point(inside: location, with: event) else { return nil }
        return super.hitTest(location, with: event)
    }
}

private extension UIView {
    var parentViewController: UIViewController? {
        sequence(first: next, next: { $0?.next }).compactMap { $0 as? UIViewController }.first
    }
}
