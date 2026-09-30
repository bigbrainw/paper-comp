import PDFKit
import PencilKit
import UIKit

/// Supplies one `PageCanvasView` per visible PDF page and persists its drawing by `pageID`.
@MainActor
final class PageOverlayProvider: NSObject {
    private let store: DrawingStore
    private let toolState: ToolState
    private var canvases: [Int: PageCanvasView] = [:]
    private var markers: [UUID: [CGRect]] = [:]
    private var scaleDebounce: Task<Void, Never>?
    private var pendingBackingScale: CGFloat?
    var pages: [PageRef] = []
    var onMarkerTap: ((SearchMarker) -> Void)?

    var allowFingerDrawing: Bool {
        didSet { if allowFingerDrawing != oldValue { applyToolState() } }
    }

    init(store: DrawingStore, toolState: ToolState, allowFingerDrawing: Bool = InputSettings.allowFingerDrawingDefault) {
        self.store = store
        self.toolState = toolState
        self.allowFingerDrawing = allowFingerDrawing
    }

    func applyToolState() {
        canvases.values.forEach(configure)
    }

    /// Visible live canvas for Circle Search ink capture, if the page overlay is on screen.
    func canvas(at pageIndex: Int) -> PageCanvasView? {
        canvases[pageIndex]
    }

    /// Immutable snapshot of the live drawing (or empty if the page is not visible).
    func drawingSnapshot(at pageIndex: Int) -> PKDrawing {
        canvases[pageIndex]?.drawing ?? PKDrawing()
    }

    /// True while any on-screen canvas has an in-progress Pencil/finger stroke.
    var isAnyCanvasActivelyDrawing: Bool {
        canvases.values.contains { $0.isActivelyDrawing }
    }

    /// Current stroke data for every on-screen canvas, keyed by stable `pageID`.
    func liveDrawingsByPageID() -> [UUID: PKDrawing] {
        var map: [UUID: PKDrawing] = [:]
        for canvas in canvases.values {
            map[canvas.pageID] = canvas.drawing
        }
        return map
    }

    func setMarkers(_ newMarkers: [SearchMarker]) {
        markers = Dictionary(grouping: newMarkers, by: \.pageID).mapValues { $0.map(\.pageRect) }
        for canvas in canvases.values { canvas.setMarkers(markers[canvas.pageID] ?? []) }
    }

    func saveAll() {
        for canvas in canvases.values {
            store.save(canvas.drawing, for: canvas.pageID, pageIndex: canvas.pageIndex)
        }
    }

    /// Debounced content-scale update after PDF zoom. Skips canvases mid-stroke.
    func scheduleBackingScaleUpdate(for pdfView: PDFView, delayNanoseconds: UInt64 = 80_000_000) {
        let screen = pdfView.window?.screen.scale ?? UIScreen.main.scale
        let fit = pdfView.scaleFactorForSizeToFit
        let zoom = pdfView.scaleFactor
        let scale = CanvasBackingScale.contentScale(screenScale: screen, zoomScale: zoom, fitScale: fit)
        pendingBackingScale = scale
        scaleDebounce?.cancel()
        scaleDebounce = Task { @MainActor in
            try? await Task.sleep(nanoseconds: delayNanoseconds)
            guard !Task.isCancelled, let pending = self.pendingBackingScale else { return }
            self.applyBackingScale(pending)
        }
    }

    func applyBackingScale(_ scale: CGFloat) {
        for canvas in canvases.values {
            guard !canvas.isActivelyDrawing else { continue }
            if abs(canvas.contentScaleFactor - scale) > 0.01 {
                canvas.contentScaleFactor = scale
                canvas.setNeedsDisplay()
            }
        }
    }

    private func pageID(at index: Int) -> UUID {
        PageIdentity.pageID(in: pages, at: index) ?? UUID()
    }

    private func configure(_ canvas: PageCanvasView) {
        canvas.tool = toolState.pkTool
        canvas.drawingPolicy = InputSettings.drawingPolicy(allowFinger: allowFingerDrawing)
        canvas.drawingGestureRecognizer.isEnabled = !toolState.isCircleSearch
        // Paper pages stay light so dark ink never inverts; dark note pages keep dark traits for light ink.
        if pages.indices.contains(canvas.pageIndex),
           case .note(_, _, let color) = pages[canvas.pageIndex].kind, color == .dark {
            canvas.overrideUserInterfaceStyle = .dark
        } else {
            canvas.overrideUserInterfaceStyle = .light
        }
    }
}

extension PageOverlayProvider: @preconcurrency PDFPageOverlayViewProvider {
    func pdfView(_ view: PDFView, overlayViewFor page: PDFPage) -> UIView? {
        guard let index = view.document?.index(for: page) else { return nil }
        if let existing = canvases[index] { return existing }
        let pageID = pageID(at: index)
        let canvas = PageCanvasView(pageID: pageID, pageIndex: index, undoManager: toolState.undoManager)
        canvas.drawing = store.drawing(for: pageID)
        canvas.delegate = self
        canvas.pageBounds = page.bounds(for: view.displayBox)
        canvas.setMarkers(markers[pageID] ?? [])
        canvas.onMarkerTap = { [weak self] rect in
            self?.onMarkerTap?(SearchMarker(pageID: pageID, pageIndex: index, pageRect: rect))
        }
        configure(canvas)
        canvases[index] = canvas
        if let pending = pendingBackingScale {
            canvas.contentScaleFactor = pending
        } else {
            let screen = view.window?.screen.scale ?? UIScreen.main.scale
            let fit = view.scaleFactorForSizeToFit
            let zoom = view.scaleFactor
            canvas.contentScaleFactor = CanvasBackingScale.contentScale(
                screenScale: screen, zoomScale: zoom, fitScale: fit
            )
        }
        return canvas
    }

    func pdfView(_ pdfView: PDFView, willEndDisplayingOverlayView overlayView: UIView, for page: PDFPage) {
        guard let canvas = overlayView as? PageCanvasView else { return }
        store.save(canvas.drawing, for: canvas.pageID, pageIndex: canvas.pageIndex)
        toolState.undoManager.removeAllActions(withTarget: canvas)
        toolState.refreshUndoState()
        canvases[canvas.pageIndex] = nil
    }
}

extension PageOverlayProvider: PKCanvasViewDelegate {
    func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
        guard let canvas = canvasView as? PageCanvasView else { return }
        store.scheduleSave(canvas.drawing, for: canvas.pageID, pageIndex: canvas.pageIndex)
        toolState.refreshUndoState()
    }
}
