import PDFKit
import PencilKit
import SwiftData
import SwiftUI

/// Wraps `PDFView` with per-page PencilKit overlays, a lasso layer for Circle Search,
/// and Pencil double-tap handling. The search card is a sibling UIKit host *above* the PDF.
struct PDFKitView: UIViewRepresentable {
    let pdf: PDFDocument
    let paper: PaperDocument
    let toolState: ToolState
    var allowFingerDrawing = InputSettings.allowFingerDrawingDefault
    var markers: [SearchMarker] = []
    var onMarkerTap: (SearchMarker) -> Void = { _ in }
    let onCapture: (CircleCapture) -> Void
    var onRevealChrome: () -> Void = {}
    var anchorConverter: PageAnchorConverter?
    var selectionShape: String = SearchSelectionSettings.box
    var searchCardSession: SearchCardSession
    var inkExporter: ReaderInkExporter?
    var onNoteLongPress: (Int) -> Void = { _ in }
    var onPullToAddPage: () -> Void = {}

    @Environment(\.modelContext) private var modelContext

    func makeCoordinator() -> Coordinator { Coordinator(paper: paper, toolState: toolState) }

    func makeUIView(context: Context) -> ReaderCanvasContainer {
        let coordinator = context.coordinator
        coordinator.onCapture = onCapture

        let container = ReaderCanvasContainer()
        let pdfView = container.pdfView
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        pdfView.autoScales = true
        pdfView.backgroundColor = Theme.uiRice
        pdfView.tintColor = Theme.uiAccent
        pdfView.isInMarkupMode = true

        let provider = PageOverlayProvider(
            store: DrawingStore(context: modelContext, documentID: paper.id),
            toolState: toolState,
            allowFingerDrawing: allowFingerDrawing
        )
        provider.pages = paper.pages
        provider.setMarkers(markers)
        provider.onMarkerTap = onMarkerTap
        coordinator.provider = provider
        inkExporter?.provider = provider
        pdfView.pageOverlayViewProvider = provider
        pdfView.document = pdf

        let captureView = CircleCaptureView(frame: pdfView.bounds)
        captureView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        captureView.pdfView = pdfView
        captureView.onComplete = { [weak coordinator] points in coordinator?.completeLasso(points) }
        captureView.onBoxComplete = { [weak coordinator] rect in coordinator?.completeBox(rect) }
        pdfView.addSubview(captureView)
        pdfView.addGestureRecognizer(captureView.lassoRecognizer)
        pdfView.addGestureRecognizer(captureView.boxRecognizer)
        captureView.lassoRecognizer.delegate = coordinator
        captureView.boxRecognizer.delegate = coordinator
        coordinator.captureView = captureView
        coordinator.pdfView = pdfView
        coordinator.container = container
        anchorConverter?.pdfView = pdfView
        coordinator.applyInput(allowFinger: allowFingerDrawing)
        container.installPencilInteraction(delegate: coordinator)

        let threeFingerTap = UITapGestureRecognizer(target: coordinator, action: #selector(Coordinator.revealChrome))
        threeFingerTap.numberOfTouchesRequired = 3
        threeFingerTap.cancelsTouchesInView = false
        threeFingerTap.delegate = coordinator
        pdfView.addGestureRecognizer(threeFingerTap)

        let twoFingerDoubleTap = UITapGestureRecognizer(target: coordinator, action: #selector(Coordinator.revealChrome))
        twoFingerDoubleTap.numberOfTapsRequired = 2
        twoFingerDoubleTap.numberOfTouchesRequired = 2
        twoFingerDoubleTap.cancelsTouchesInView = false
        twoFingerDoubleTap.delegate = coordinator
        pdfView.addGestureRecognizer(twoFingerDoubleTap)

        coordinator.onRevealChrome = onRevealChrome
        coordinator.onNoteLongPress = onNoteLongPress
        coordinator.onPullToAddPage = onPullToAddPage

        let notePress = UILongPressGestureRecognizer(target: coordinator, action: #selector(Coordinator.noteLongPress(_:)))
        notePress.minimumPressDuration = 0.5
        notePress.cancelsTouchesInView = false
        notePress.delegate = coordinator
        pdfView.addGestureRecognizer(notePress)

        NotificationCenter.default.addObserver(
            coordinator, selector: #selector(Coordinator.pageChanged), name: .PDFViewPageChanged, object: pdfView
        )
        NotificationCenter.default.addObserver(
            coordinator, selector: #selector(Coordinator.scaleChanged), name: .PDFViewScaleChanged, object: pdfView
        )
        NotificationCenter.default.addObserver(
            coordinator, selector: #selector(Coordinator.jumpRequested(_:)), name: ReaderJump.notification, object: nil
        )

        let startIndex = min(max(paper.lastPageIndex, 0), pdf.pageCount - 1)
        if startIndex > 0, let page = pdf.page(at: startIndex) {
            DispatchQueue.main.async { pdfView.go(to: page) }
        }
        DispatchQueue.main.async { coordinator.attachPullObservationIfNeeded() }
        return container
    }

    func updateUIView(_ container: ReaderCanvasContainer, context: Context) {
        let coordinator = context.coordinator
        let pdfView = container.pdfView
        coordinator.container = container
        coordinator.onCapture = onCapture
        coordinator.onRevealChrome = onRevealChrome
        coordinator.onNoteLongPress = onNoteLongPress
        coordinator.onPullToAddPage = onPullToAddPage
        if pdfView.document !== pdf {
            coordinator.resetPullState()
            pdfView.document = pdf
            if let page = pdf.page(at: min(max(paper.lastPageIndex, 0), max(pdf.pageCount - 1, 0))) {
                pdfView.go(to: page)
            }
        }
        coordinator.provider?.pages = paper.pages
        coordinator.provider?.onMarkerTap = onMarkerTap
        coordinator.provider?.setMarkers(markers)
        coordinator.provider?.applyToolState()
        inkExporter?.provider = coordinator.provider
        coordinator.selectionShape = selectionShape
        coordinator.applyInput(allowFinger: allowFingerDrawing)
        container.installPencilInteraction(delegate: coordinator)
        coordinator.attachPullObservationIfNeeded()
        if toolState.isCircleSearch, let captureView = coordinator.captureView {
            pdfView.bringSubviewToFront(captureView)
        }
    }

    static func dismantleUIView(_ container: ReaderCanvasContainer, coordinator: Coordinator) {
        coordinator.detachPullObservation()
        coordinator.provider?.saveAll()
        NotificationCenter.default.removeObserver(coordinator)
        container.removePencilInteraction()
        container.removeSearchCard()
    }

    @MainActor
    final class Coordinator: NSObject, UIPencilInteractionDelegate, UIGestureRecognizerDelegate {
        let paper: PaperDocument
        let toolState: ToolState
        var provider: PageOverlayProvider?
        weak var pdfView: PDFView?
        weak var container: ReaderCanvasContainer?
        weak var captureView: CircleCaptureView?
        weak var cardHost: SearchCardHostView?
        var onNoteLongPress: ((Int) -> Void)?
        var onCapture: ((CircleCapture) -> Void)?
        var onPullToAddPage: (() -> Void)?
        var selectionShape: String = SearchSelectionSettings.box
        var allowFingerDrawing = InputSettings.allowFingerDrawingDefault

        private var contentOffsetObservation: NSKeyValueObservation?
        private weak var observedScrollView: UIScrollView?
        private var pullState: PullToAddPage.State = .idle
        private var didHapticForArm = false
        private var didTriggerThisPull = false
        private let armFeedback = UIImpactFeedbackGenerator(style: .light)

        init(paper: PaperDocument, toolState: ToolState) {
            self.paper = paper
            self.toolState = toolState
        }

        private var defaultScrollTouchTypes: [NSNumber]?

        /// Applies "Draw with finger" and the Circle Search mode to canvases, lasso, and scrolling.
        func applyInput(allowFinger: Bool) {
            allowFingerDrawing = allowFinger
            provider?.allowFingerDrawing = allowFinger
            captureView?.allowsFinger = allowFinger
            captureView?.selectionShape = selectionShape
            captureView?.isActive = toolState.isCircleSearch

            guard let pan = pdfView.flatMap(Self.scrollView(in:))?.panGestureRecognizer else { return }
            let defaults = defaultScrollTouchTypes ?? pan.allowedTouchTypes
            defaultScrollTouchTypes = defaults
            pan.minimumNumberOfTouches = InputSettings.scrollPanMinimumTouches(
                allowFinger: allowFinger, isCircleSearch: toolState.isCircleSearch
            )
            pan.allowedTouchTypes = InputSettings.scrollPanTouchTypes(
                allowFinger: allowFinger, isCircleSearch: toolState.isCircleSearch
            )?.asAllowedTouchTypes ?? defaults
        }

        /// PDFKit's document scroll view: the shallowest `UIScrollView` under the PDF view.
        static func scrollView(in pdfView: PDFView) -> UIScrollView? {
            var queue = pdfView.subviews
            while !queue.isEmpty {
                let view = queue.removeFirst()
                if let scrollView = view as? UIScrollView, !(view is PKCanvasView) { return scrollView }
                queue.append(contentsOf: view.subviews)
            }
            return nil
        }

        func attachPullObservationIfNeeded() {
            guard let pdfView, let scrollView = Self.scrollView(in: pdfView) else { return }
            if observedScrollView === scrollView { return }
            detachPullObservation()
            observedScrollView = scrollView
            contentOffsetObservation = scrollView.observe(\.contentOffset, options: [.new]) { [weak self] _, _ in
                Task { @MainActor [weak self] in
                    guard let self, let scroll = self.observedScrollView else { return }
                    self.handlePullScroll(scroll)
                }
            }
            scrollView.panGestureRecognizer.addTarget(self, action: #selector(pullPanChanged(_:)))
            armFeedback.prepare()
        }

        func detachPullObservation() {
            if let scrollView = observedScrollView {
                scrollView.panGestureRecognizer.removeTarget(self, action: #selector(pullPanChanged(_:)))
            }
            contentOffsetObservation?.invalidate()
            contentOffsetObservation = nil
            observedScrollView = nil
        }

        func resetPullState() {
            didHapticForArm = false
            didTriggerThisPull = false
            applyPullState(.idle)
        }

        private func handlePullScroll(_ scrollView: UIScrollView) {
            let overscroll = PullToAddPage.overscroll(
                contentOffsetY: scrollView.contentOffset.y,
                boundsHeight: scrollView.bounds.height,
                adjustedContentInsetBottom: scrollView.adjustedContentInset.bottom,
                contentSizeHeight: scrollView.contentSize.height
            )
            let next = PullToAddPage.state(overscroll: overscroll)
            if case .idle = next {
                didHapticForArm = false
                didTriggerThisPull = false
            }
            applyPullState(next)
        }

        @objc private func pullPanChanged(_ recognizer: UIPanGestureRecognizer) {
            switch recognizer.state {
            case .ended:
                if case .armed = pullState, !didTriggerThisPull, canTriggerPullAdd() {
                    didTriggerThisPull = true
                    onPullToAddPage?()
                }
                // Bounce-back will clear via contentOffset; hide pill if already idle-ish.
                if let scrollView = observedScrollView {
                    handlePullScroll(scrollView)
                }
            case .cancelled, .failed:
                if let scrollView = observedScrollView {
                    handlePullScroll(scrollView)
                }
            default:
                break
            }
        }

        private func canTriggerPullAdd() -> Bool {
            guard !toolState.isCircleSearch else { return false }
            guard !(provider?.isAnyCanvasActivelyDrawing ?? false) else { return false }
            guard !paper.pages.isEmpty else { return false }
            return true
        }

        private func applyPullState(_ next: PullToAddPage.State) {
            if next.isArmed, !didHapticForArm, canTriggerPullAdd() {
                didHapticForArm = true
                armFeedback.impactOccurred()
            }
            guard next != pullState else {
                container?.setPullToAddState(pullState)
                return
            }
            pullState = next
            container?.setPullToAddState(next)
        }

        @objc func pageChanged() {
            guard let pdfView, let page = pdfView.currentPage, let index = pdfView.document?.index(for: page) else { return }
            if paper.lastPageIndex != index { paper.lastPageIndex = index }
        }

        @objc func scaleChanged() {
            guard let pdfView else { return }
            provider?.scheduleBackingScaleUpdate(for: pdfView)
        }

        @objc func jumpRequested(_ note: Notification) {
            guard let pdfView else { return }
            if let index = note.userInfo?[ReaderJump.pageKey] as? Int,
               let page = pdfView.document?.page(at: index) {
                pdfView.go(to: page)
                return
            }
            if let query = note.userInfo?[ReaderJump.queryKey] as? String,
               let selection = pdfView.document?.findString(query, withOptions: .caseInsensitive).first,
               let page = selection.pages.first {
                pdfView.go(to: page)
                pdfView.setCurrentSelection(selection, animate: true)
            }
        }

        func pencilInteraction(_ interaction: UIPencilInteraction, didReceiveTap tap: UIPencilInteraction.Tap) {
            let response = PencilTapResponse.preferred(from: interaction)
            #if DEBUG
            PencilTapLog.tap.notice("didReceiveTap \(String(describing: response), privacy: .public) tool=\(self.toolState.tool.rawValue, privacy: .public)")
            print("PCPencil didReceiveTap \(response) tool=\(toolState.tool.rawValue)")
            #endif
            toolState.handlePencilTap(response)
            provider?.applyToolState()
            applyInput(allowFinger: allowFingerDrawing)
        }

        var onRevealChrome: (() -> Void)?

        @objc func revealChrome() { onRevealChrome?() }

        @objc func noteLongPress(_ recognizer: UILongPressGestureRecognizer) {
            guard recognizer.state == .began,
                  let pdfView,
                  let page = pdfView.currentPage,
                  let index = pdfView.document?.index(for: page),
                  paper.pages.indices.contains(index),
                  case .note = paper.pages[index].kind
            else { return }
            onNoteLongPress?(index)
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            let blocksInsideCard = gestureRecognizer === captureView?.boxRecognizer
                || gestureRecognizer === captureView?.lassoRecognizer
            guard blocksInsideCard, let cardHost else { return true }
            let point = gestureRecognizer.location(in: cardHost)
            return cardHost.shouldAllowPDFCapture(at: point)
        }

        /// Converts a view-space box into a capture; tiny boxes become word taps.
        func completeBox(_ viewRect: CGRect) {
            guard let pdfView, let pdf = pdfView.document else { return }
            let center = CGPoint(x: viewRect.midX, y: viewRect.midY)
            guard let page = pdfView.page(for: center, nearest: true) else { return }
            let pageIndex = pdf.index(for: page)
            let pageRect = Self.pageRect(fromViewRect: viewRect, on: page, in: pdfView)
            let canvas = provider?.canvas(at: pageIndex)
            let drawing = provider?.drawingSnapshot(at: pageIndex) ?? PKDrawing()

            if pageRect.width < SearchSelectionSettings.tinyBoxThreshold
                || pageRect.height < SearchSelectionSettings.tinyBoxThreshold {
                let tap = CGPoint(x: pageRect.midX, y: pageRect.midY)
                if let capture = CircleSearchCapture.makeFromTap(
                    at: tap, page: page, pageIndex: pageIndex, documentID: paper.id, paperTitle: paper.title,
                    drawing: drawing, canvas: canvas, pdfView: pdfView
                ) {
                    finishCapture(capture)
                }
                return
            }

            if let capture = CircleSearchCapture.make(
                pageRect: pageRect, page: page, pageIndex: pageIndex,
                documentID: paper.id, paperTitle: paper.title,
                drawing: drawing, canvas: canvas, pdfView: pdfView
            ) {
                finishCapture(capture)
            }
        }

        static func pageRect(fromViewRect viewRect: CGRect, on page: PDFPage, in pdfView: PDFView) -> CGRect {
            let topLeft = pdfView.convert(CGPoint(x: viewRect.minX, y: viewRect.minY), to: page)
            let bottomRight = pdfView.convert(CGPoint(x: viewRect.maxX, y: viewRect.maxY), to: page)
            return CGRect(
                x: min(topLeft.x, bottomRight.x),
                y: min(topLeft.y, bottomRight.y),
                width: abs(bottomRight.x - topLeft.x),
                height: abs(bottomRight.y - topLeft.y)
            ).intersection(page.bounds(for: .cropBox))
        }

        /// Converts a lasso drawn in `PDFView` coordinates into a capture on the page under its center.
        func completeLasso(_ points: [CGPoint]) {
            guard let pdfView, let first = points.first else { return }
            let viewPath = CGMutablePath()
            viewPath.addLines(between: points)
            let box = viewPath.boundingBoxOfPath
            guard let page = pdfView.page(for: CGPoint(x: box.midX, y: box.midY), nearest: true),
                  let pdf = pdfView.document else { return }

            let pagePath = CGMutablePath()
            pagePath.move(to: pdfView.convert(first, to: page))
            for point in points.dropFirst() { pagePath.addLine(to: pdfView.convert(point, to: page)) }
            pagePath.closeSubpath()

            let pageIndex = pdf.index(for: page)
            let canvas = provider?.canvas(at: pageIndex)
            let drawing = provider?.drawingSnapshot(at: pageIndex) ?? PKDrawing()
            if let capture = CircleSearchCapture.make(
                path: pagePath,
                page: page,
                pageIndex: pageIndex,
                documentID: paper.id,
                paperTitle: paper.title,
                drawing: drawing,
                canvas: canvas,
                pdfView: pdfView
            ) {
                finishCapture(capture)
            }
        }

        /// Clears lasso chrome, optionally OCRs handwriting, then delivers the capture.
        private func finishCapture(_ capture: CircleCapture) {
            captureView?.clearOverlay()
            let needsOCR = capture.selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && capture.containsInk
            guard needsOCR else {
                onCapture?(capture)
                return
            }
            Task { @MainActor in
                let text = await CaptureOCR.text(in: capture.image)
                onCapture?(capture.withHandwritingText(text))
            }
        }
    }
}
