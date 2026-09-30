#if DEBUG
import ObjectiveC
import os
import UIKit

/// DEBUG-only: logs which view wins `hitTest` / `sendEvent` so we can see PDFKit vs the card.
@MainActor
enum TouchProbe {
    static let log = Logger(subsystem: "com.elijah.papercomp", category: "TouchProbe")
    private static var installed = false

    static func install() {
        guard !installed else { return }
        installed = true
        let original = class_getInstanceMethod(UIWindow.self, #selector(UIWindow.sendEvent(_:)))
        let probe = class_getInstanceMethod(UIWindow.self, #selector(UIWindow.pc_sendEvent(_:)))
        guard let original, let probe else { return }
        method_exchangeImplementations(original, probe)
        log.debug("TouchProbe installed on UIWindow.sendEvent")
    }

    static func logHitTest(point: CGPoint, hit: UIView?, host: String) {
        log.debug("\(host, privacy: .public) hitTest \(point.x, format: .fixed(precision: 1)),\(point.y, format: .fixed(precision: 1)) -> \(describe(hit), privacy: .public)")
    }

    static func describe(_ view: UIView?) -> String {
        guard let view else { return "nil" }
        var names: [String] = []
        var current: UIView? = view
        while let node = current, names.count < 8 {
            names.append(String(describing: type(of: node)))
            current = node.superview
        }
        let label = view.accessibilityLabel ?? view.accessibilityIdentifier ?? ""
        let chain = names.joined(separator: " < ")
        return label.isEmpty ? chain : "\(chain) a11y=\(label)"
    }
}

extension UIWindow {
    @objc func pc_sendEvent(_ event: UIEvent) {
        if event.type == .touches, let touch = event.allTouches?.first, touch.phase == .began {
            let point = touch.location(in: self)
            let hit = hitTest(point, with: event)
            let kind = touch.type == .pencil ? "pencil" : "finger"
            MainActor.assumeIsolated {
                TouchProbe.log.debug("window sendEvent \(kind, privacy: .public) \(point.x, format: .fixed(precision: 1)),\(point.y, format: .fixed(precision: 1)) -> \(TouchProbe.describe(hit), privacy: .public)")
            }
        }
        pc_sendEvent(event)
    }
}
#endif
