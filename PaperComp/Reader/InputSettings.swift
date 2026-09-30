import PencilKit
import UIKit

/// "Draw with finger": whether a finger inks (and two fingers scroll) or only the Pencil does.
/// Search selection (box/lasso) always accepts a finger, so the app is usable without a Pencil;
/// while Search is active, scrolling moves to two fingers so a one-finger drag can draw the box.
enum InputSettings {
    static let allowFingerDrawingKey = "allowFingerDrawing"

    static var allowFingerDrawingDefault: Bool {
        #if targetEnvironment(simulator)
        true
        #else
        false
        #endif
    }

    /// The single touch-filtering decision: may a touch of `type` act with `tool`?
    /// Pencil always may. A finger may select for Search, and inks/erases only with "Draw with finger".
    static func accepts(_ type: UITouch.TouchType, for tool: ReaderTool, allowFinger: Bool) -> Bool {
        switch type {
        case .pencil: true
        case .direct: tool == .circleSearch || allowFinger
        default: false
        }
    }

    static func acceptedTouchTypes(for tool: ReaderTool, allowFinger: Bool) -> [UITouch.TouchType] {
        [UITouch.TouchType.direct, .pencil].filter { accepts($0, for: tool, allowFinger: allowFinger) }
    }

    /// Ink canvases (pen/highlighter/eraser). Search disables the canvas drawing gesture instead.
    static func drawingPolicy(allowFinger: Bool) -> PKCanvasViewDrawingPolicy {
        accepts(.direct, for: .pen, allowFinger: allowFinger) ? .anyInput : .pencilOnly
    }

    /// Touch types for the Search box/lasso recognizers.
    static func selectionTouchTypes(allowFinger: Bool) -> [UITouch.TouchType] {
        acceptedTouchTypes(for: .circleSearch, allowFinger: allowFinger)
    }

    /// One finger scrolls unless a one-finger drag belongs to the active tool (finger ink or Search box).
    static func scrollPanMinimumTouches(allowFinger: Bool, isCircleSearch: Bool = false) -> Int {
        allowFinger || isCircleSearch ? 2 : 1
    }

    /// Touch types the PDF scroll view may pan with, or `nil` for its defaults.
    /// While Search is active (and fingers don't ink) the Pencil must not scroll; it only selects.
    static func scrollPanTouchTypes(allowFinger: Bool, isCircleSearch: Bool) -> [UITouch.TouchType]? {
        isCircleSearch && !allowFinger ? [.direct] : nil
    }
}

extension Array where Element == UITouch.TouchType {
    var asAllowedTouchTypes: [NSNumber] { map { NSNumber(value: $0.rawValue) } }
}
