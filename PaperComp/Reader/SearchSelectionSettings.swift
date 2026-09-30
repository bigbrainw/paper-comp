import CoreGraphics
import Foundation

/// UserDefaults key shared with Settings (`selectionShape`: `box` | `freeform`).
enum SearchSelectionSettings {
    static let storageKey = "selectionShape"
    static let box = "box"
    static let freeform = "freeform"

    static let tinyBoxThreshold: CGFloat = 12
    static let snapThreshold: CGFloat = 8
}
