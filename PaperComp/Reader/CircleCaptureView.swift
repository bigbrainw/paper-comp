import PDFKit
import UIKit

/// Dashed box or freeform lasso for Search. Gestures attach to the PDF view; this view only draws.
final class CircleCaptureView: UIView {
    var onComplete: (([CGPoint]) -> Void)?
    var onBoxComplete: ((CGRect) -> Void)?

    let lassoRecognizer = LassoGestureRecognizer()
    let boxRecognizer = BoxGestureRecognizer()

    weak var pdfView: PDFView?

    var selectionShape: String = SearchSelectionSettings.box {
        didSet { applyRecognizerMode() }
    }

    var isActive = false {
        didSet {
            isUserInteractionEnabled = false
            lassoRecognizer.isEnabled = isActive && selectionShape == SearchSelectionSettings.freeform
            boxRecognizer.isEnabled = isActive && selectionShape == SearchSelectionSettings.box
            if !isActive {
                clearOverlay()
                isHidden = true
            }
        }
    }

    /// Clears any live box/lasso drawing. Call after a capture is handed to the search card.
    func clearOverlay() {
        shapeLayer.removeAllAnimations()
        shapeLayer.path = nil
        shapeLayer.opacity = 1
        isHidden = true
    }

    var allowsFinger = false {
        didSet {
            let types = InputSettings.selectionTouchTypes(allowFinger: allowsFinger).asAllowedTouchTypes
            lassoRecognizer.allowedTouchTypes = types
            boxRecognizer.allowedTouchTypes = types
        }
    }

    private let shapeLayer = CAShapeLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isUserInteractionEnabled = false
        isHidden = true
        lassoRecognizer.isEnabled = false
        boxRecognizer.isEnabled = false
        lassoRecognizer.allowedTouchTypes = InputSettings.selectionTouchTypes(allowFinger: false).asAllowedTouchTypes
        boxRecognizer.allowedTouchTypes = lassoRecognizer.allowedTouchTypes
        lassoRecognizer.addTarget(self, action: #selector(handleLasso(_:)))
        boxRecognizer.addTarget(self, action: #selector(handleBox(_:)))
        applyColors()
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: CircleCaptureView, _) in view.applyColors() }
        shapeLayer.lineWidth = 2.5
        shapeLayer.lineDashPattern = [8, 6]
        shapeLayer.lineCap = .round
        shapeLayer.lineJoin = .round
        layer.addSublayer(shapeLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    var activeRecognizer: UIGestureRecognizer {
        selectionShape == SearchSelectionSettings.freeform ? lassoRecognizer : boxRecognizer
    }

    private func applyRecognizerMode() {
        lassoRecognizer.isEnabled = isActive && selectionShape == SearchSelectionSettings.freeform
        boxRecognizer.isEnabled = isActive && selectionShape == SearchSelectionSettings.box
    }

    private func applyColors() {
        let accent = Theme.uiAccent.resolvedColor(with: traitCollection)
        shapeLayer.fillColor = accent.withAlphaComponent(0.1).cgColor
        shapeLayer.strokeColor = accent.cgColor
    }

    @objc private func handleLasso(_ recognizer: LassoGestureRecognizer) {
        let points = recognizer.points
        switch recognizer.state {
        case .began:
            isHidden = false
            shapeLayer.removeAllAnimations()
            shapeLayer.opacity = 1
            redrawLasso(points)
        case .changed:
            redrawLasso(points)
        case .ended:
            redrawLasso(points, closed: true)
            if points.count > 2 { onComplete?(points) }
            clearOverlay()
        default:
            redrawLasso([])
        }
    }

    @objc private func handleBox(_ recognizer: BoxGestureRecognizer) {
        guard let rect = recognizer.viewRect else { return }
        switch recognizer.state {
        case .began:
            isHidden = false
            shapeLayer.removeAllAnimations()
            shapeLayer.opacity = 1
            shapeLayer.path = UIBezierPath(rect: rect).cgPath
        case .changed:
            shapeLayer.removeAllAnimations()
            shapeLayer.opacity = 1
            shapeLayer.path = UIBezierPath(rect: rect).cgPath
        case .ended:
            onBoxComplete?(rect)
            clearOverlay()
        default:
            shapeLayer.path = nil
        }
    }

    private func redrawLasso(_ points: [CGPoint], closed: Bool = false) {
        guard let first = points.first else {
            shapeLayer.path = nil
            return
        }
        let source = lassoRecognizer.view
        let path = UIBezierPath()
        path.move(to: convert(first, from: source))
        points.dropFirst().forEach { path.addLine(to: convert($0, from: source)) }
        if closed { path.close() }
        shapeLayer.path = path.cgPath
    }

}

/// Two-corner axis-aligned box drag in the PDF view.
/// A second finger fails it (or cancels a finger box already drawing) so two-finger scroll/zoom wins;
/// a resting palm doesn't cancel a Pencil box.
final class BoxGestureRecognizer: UIGestureRecognizer {
    private(set) var viewRect: CGRect?
    private var start: CGPoint?
    private var tracked: UITouch?

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        guard tracked == nil, touches.count == 1, let touch = touches.first else {
            if state == .possible {
                state = .failed
            } else if Self.secondTouchCancels(trackedType: tracked?.type, state: state) {
                state = .cancelled
            }
            return
        }
        tracked = touch
        start = touch.location(in: view)
        viewRect = nil
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let tracked, touches.contains(tracked), let start else { return }
        let current = tracked.location(in: view)
        viewRect = CGRect(x: min(start.x, current.x), y: min(start.y, current.y),
                          width: abs(current.x - start.x), height: abs(current.y - start.y))
        if state == .possible { state = .began }
        state = .changed
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let tracked, touches.contains(tracked) else { return }
        state = viewRect == nil ? .failed : .ended
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        state = .cancelled
    }

    override func reset() {
        super.reset()
        tracked = nil
        start = nil
        viewRect = nil
    }

    /// A finger box in progress gives way to a second touch (the user is scrolling or zooming).
    static func secondTouchCancels(trackedType: UITouch.TouchType?, state: UIGestureRecognizer.State) -> Bool {
        trackedType == .direct && (state == .began || state == .changed)
    }
}

/// Single-touch freehand stroke. Fails if a second touch lands first, so two-finger scrolling still works.
final class LassoGestureRecognizer: UIGestureRecognizer {
    private(set) var points: [CGPoint] = []
    private var tracked: UITouch?
    private let startDistance: CGFloat = 6

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        guard tracked == nil, touches.count == 1, let touch = touches.first else {
            if state == .possible {
                state = .failed
            } else if BoxGestureRecognizer.secondTouchCancels(trackedType: tracked?.type, state: state) {
                state = .cancelled
            }
            return
        }
        tracked = touch
        points = [touch.location(in: view)]
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let tracked, touches.contains(tracked) else { return }
        let samples = event.coalescedTouches(for: tracked) ?? [tracked]
        points.append(contentsOf: samples.map { $0.location(in: view) })
        if state == .possible {
            guard let first = points.first, let last = points.last,
                  hypot(last.x - first.x, last.y - first.y) >= startDistance else { return }
            state = .began
        } else {
            state = .changed
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let tracked, touches.contains(tracked) else { return }
        state = state == .possible ? .failed : .ended
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        state = state == .possible ? .failed : .cancelled
    }

    override func reset() {
        super.reset()
        tracked = nil
        points = []
    }
}
