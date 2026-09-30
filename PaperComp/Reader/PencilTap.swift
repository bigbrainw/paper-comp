import os
import UIKit

#if DEBUG
enum PencilTapLog {
    static let tap = Logger(subsystem: "com.elijah.papercomp", category: "pencil")
    static let handle = Logger(subsystem: "com.elijah.papercomp", category: "pencil")
}
#endif

/// What a Pencil double-tap does, following the system's preferred action.
enum PencilTapResponse: Equatable {
    case toggleEraser
    case switchToPrevious
    case showInkOptions
    case toggleCircleSearch
    case none

    init(_ action: UIPencilPreferredAction) {
        switch action {
        case .switchEraser: self = .toggleEraser
        case .switchPrevious: self = .switchToPrevious
        case .showColorPalette, .showInkAttributes, .showContextualPalette: self = .showInkOptions
        case .ignore: self = .toggleCircleSearch
        case .runSystemShortcut: self = .none
        @unknown default: self = .none
        }
    }

    /// The user's Settings preference for barrel tap.
    /// UIKit documents consulting `UIPencilInteraction.preferredTapAction` from `didReceiveTap`.
    /// Prefer an instance getter when the SDK adds one (`interaction.preferredTapAction`).
    @MainActor
    static func preferred(from interaction: UIPencilInteraction) -> PencilTapResponse {
        let sel = NSSelectorFromString("preferredTapAction")
        let instanceIMP = class_getInstanceMethod(type(of: interaction), sel)
            .map { method_getImplementation($0) }
        if instanceIMP != nil, let imp = interaction.method(for: sel) {
            typealias Getter = @convention(c) (AnyObject, Selector) -> Int
            if let action = UIPencilPreferredAction(rawValue: unsafeBitCast(imp, to: Getter.self)(interaction, sel)) {
                return PencilTapResponse(action)
            }
        }
        return PencilTapResponse(UIPencilInteraction.preferredTapAction)
    }
}
