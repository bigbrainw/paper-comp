import CoreGraphics
import Foundation

/// UserDefaults keys shared with the Settings screen. Raw strings are parsed defensively.
enum ReaderSettings {
    static let showSearchMarkersKey = "showSearchMarkers"
    static let showSearchMarkersDefault = true

    static let eraserModeKey = "eraserMode"
    static let eraserPixelWidthKey = "eraserPixelWidth"
    static let toolbarPositionKey = "toolbarPosition"
}

enum EraserMode: String, CaseIterable, Identifiable {
    case stroke, pixel

    static let defaultValue = EraserMode.pixel

    init(parsing raw: String?) {
        self = raw.flatMap(EraserMode.init(rawValue:)) ?? .defaultValue
    }

    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    var systemImage: String {
        switch self {
        case .stroke: "scribble"
        case .pixel: "square.grid.3x3"
        }
    }
}

enum EraserWidth: String, CaseIterable, Identifiable, DotOption {
    case small, medium, large

    static let defaultValue = EraserWidth.medium

    init(parsing raw: String?) {
        self = raw.flatMap(EraserWidth.init(rawValue:)) ?? .defaultValue
    }

    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    var points: CGFloat {
        switch self {
        case .small: 8
        case .medium: 20
        case .large: 40
        }
    }

    var dotSize: CGFloat {
        switch self {
        case .small: 6
        case .medium: 10
        case .large: 14
        }
    }
}

enum ToolbarPosition: String, CaseIterable {
    case top, left

    static let defaultValue = ToolbarPosition.top

    init(parsing raw: String?) {
        self = raw.flatMap(ToolbarPosition.init(rawValue:)) ?? .defaultValue
    }
}

/// An option drawn as a dot in a 3-dot size toggle.
protocol DotOption: Hashable, Identifiable {
    var title: String { get }
    var dotSize: CGFloat { get }
}
