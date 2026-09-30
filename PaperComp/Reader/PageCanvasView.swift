import PencilKit
import UIKit

/// A transparent PencilKit canvas that sits over one PDF page and shares the reader's undo stack.
/// Also hosts the tappable markers for saved Circle Search answers on this page.
final class PageCanvasView: PKCanvasView {
    let pageID: UUID
    let pageIndex: Int
    private let sharedUndoManager: UndoManager

    /// The page's display box in PDF page coordinates; maps marker rects into this view.
    var pageBounds: CGRect = .zero {
        didSet { if pageBounds != oldValue { setNeedsLayout() } }
    }
    var onMarkerTap: ((CGRect) -> Void)?
    private var markerRects: [CGRect] = []
    private var markerViews: [UIView] = []

    init(pageID: UUID, pageIndex: Int, undoManager: UndoManager) {
        self.pageID = pageID
        self.pageIndex = pageIndex
        self.sharedUndoManager = undoManager
        super.init(frame: .zero)
        backgroundColor = .clear
        isOpaque = false
        isScrollEnabled = false
        showsVerticalScrollIndicator = false
        showsHorizontalScrollIndicator = false
        drawingPolicy = .pencilOnly
        // PDF pages stay white in dark mode; without this PencilKit inverts dark ink to light.
        overrideUserInterfaceStyle = .light
        stripPencilInteractions()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        stripPencilInteractions()
    }

    /// PKCanvasView installs its own barrel-tap handler; the reader owns ToolState instead.
    private func stripPencilInteractions() {
        interactions.compactMap { $0 as? UIPencilInteraction }.forEach(removeInteraction)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var undoManager: UndoManager? { sharedUndoManager }

    /// True while a stroke is in progress (used to defer contentScaleFactor updates).
    var isActivelyDrawing: Bool {
        let state = drawingGestureRecognizer.state
        return state == .began || state == .changed
    }

    /// Circled regions (PDF page coordinates) that have saved answers.
    func setMarkers(_ rects: [CGRect]) {
        guard rects != markerRects else { return }
        markerViews.forEach { $0.removeFromSuperview() }
        markerRects = rects
        markerViews = rects.map(makeMarker)
        markerViews.forEach(addSubview)
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard pageBounds.width > 0, pageBounds.height > 0 else { return }
        let scaleX = bounds.width / pageBounds.width
        let scaleY = bounds.height / pageBounds.height
        for (view, rect) in zip(markerViews, markerRects) {
            // Pin to the circle's top-right corner; page space has its origin at the bottom-left.
            view.center = CGPoint(x: (rect.maxX - pageBounds.minX) * scaleX,
                                  y: (pageBounds.maxY - rect.maxY) * scaleY)
            bringSubviewToFront(view)
        }
    }

    private func makeMarker(for rect: CGRect) -> UIView {
        let size: CGFloat = 26
        let marker = UIImageView(image: UIImage(
            systemName: "sparkle.magnifyingglass",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
        ))
        marker.frame = CGRect(x: 0, y: 0, width: size, height: size)
        marker.contentMode = .center
        marker.tintColor = Theme.uiRiceSurface
        marker.backgroundColor = Theme.uiAccent
        marker.layer.cornerRadius = size / 2
        marker.layer.borderColor = Theme.uiRiceSurface.resolvedColor(with: traitCollection).cgColor
        marker.layer.borderWidth = 1.5
        marker.layer.shadowColor = Theme.uiInk.resolvedColor(with: traitCollection).cgColor
        marker.layer.shadowOpacity = 0.2
        marker.layer.shadowRadius = 2
        marker.layer.shadowOffset = CGSize(width: 0, height: 1)
        marker.isUserInteractionEnabled = true
        marker.isAccessibilityElement = true
        marker.accessibilityLabel = "Saved answer"
        marker.accessibilityTraits = .button

        let tap = UITapGestureRecognizer(target: self, action: #selector(markerTapped(_:)))
        marker.addGestureRecognizer(tap)
        drawingGestureRecognizer.require(toFail: tap)
        return marker
    }

    @objc private func markerTapped(_ recognizer: UITapGestureRecognizer) {
        guard let view = recognizer.view, let index = markerViews.firstIndex(of: view) else { return }
        onMarkerTap?(markerRects[index])
    }
}
