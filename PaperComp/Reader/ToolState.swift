import Foundation
import Observation
import PencilKit
import UIKit

enum ReaderTool: String, CaseIterable, Identifiable {
    case pen, highlighter, eraser, circleSearch

    var id: String { rawValue }
    var isInk: Bool { self == .pen || self == .highlighter }

    var title: String {
        switch self {
        case .pen: "Pen"
        case .highlighter: "Highlighter"
        case .eraser: "Eraser"
        case .circleSearch: "Search"
        }
    }

    var systemImage: String {
        switch self {
        case .pen: "pencil.tip"
        case .highlighter: "highlighter"
        case .eraser: "eraser"
        case .circleSearch: "text.magnifyingglass"
        }
    }
}

/// A pen color. These are ink on white paper, so they are fixed rather than light/dark dynamic.
struct InkSwatch: Identifiable, Hashable {
    let name: String
    let color: UIColor
    var id: String { name }

    static let all: [InkSwatch] = [
        InkSwatch(name: "Sumi Black", color: UIColor(hex: 0x1F1B16)),
        InkSwatch(name: "Indigo Ink", color: UIColor(hex: 0x3E5C8A)),
        InkSwatch(name: "Vermilion", color: UIColor(hex: 0xB5533C)),
        InkSwatch(name: "Moss", color: UIColor(hex: 0x5E7F4F)),
        InkSwatch(name: "Amber", color: UIColor(hex: 0xC98A2B)),
        InkSwatch(name: "Saffron", color: UIColor(hex: 0xE8C547)),
    ]

    static func named(_ name: String) -> InkSwatch? { all.first { $0.name == name } }
}

enum InkWidth: String, CaseIterable, Identifiable, DotOption {
    case thin, medium, thick

    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    var points: CGFloat {
        switch self {
        case .thin: 1.5
        case .medium: 3
        case .thick: 6
        }
    }

    var dotSize: CGFloat {
        switch self {
        case .thin: 5
        case .medium: 8
        case .thick: 12
        }
    }
}

@MainActor
@Observable
final class ToolState {
    static let penPrefix = "pen"
    static let highlighterPrefix = "highlighter"
    static let highlighterWidthScale: CGFloat = 6

    var tool: ReaderTool = .pen {
        didSet {
            guard tool != oldValue else { return }
            previousTool = oldValue
            if tool.isInk { lastInkTool = tool } else { isShowingInkOptions = false }
        }
    }
    private(set) var previousTool: ReaderTool = .pen
    private(set) var lastInkTool: ReaderTool = .pen

    var pen: InkPreset { didSet { pen.save(to: defaults, prefix: Self.penPrefix) } }
    var highlighter: InkPreset { didSet { highlighter.save(to: defaults, prefix: Self.highlighterPrefix) } }
    var eraserMode: EraserMode {
        didSet { if eraserMode != oldValue { defaults.set(eraserMode.rawValue, forKey: ReaderSettings.eraserModeKey) } }
    }
    var eraserWidth: EraserWidth {
        didSet { defaults.set(eraserWidth.rawValue, forKey: ReaderSettings.eraserPixelWidthKey) }
    }

    /// The pen/highlighter popover (pen types, color, width, preview).
    var isShowingInkOptions = false
    private(set) var canUndo = false
    private(set) var canRedo = false

    @ObservationIgnored let undoManager = UndoManager()
    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        pen = InkPreset(defaults: defaults, prefix: Self.penPrefix, fallback: .penDefault)
        highlighter = InkPreset(defaults: defaults, prefix: Self.highlighterPrefix, fallback: .highlighterDefault)
        eraserMode = EraserMode(parsing: defaults.string(forKey: ReaderSettings.eraserModeKey))
        eraserWidth = EraserWidth(parsing: defaults.string(forKey: ReaderSettings.eraserPixelWidthKey))
    }

    var isCircleSearch: Bool { tool == .circleSearch }

    /// The pen or highlighter whose settings the ink controls edit.
    var activeInkTool: ReaderTool { tool.isInk ? tool : lastInkTool }

    var activeInk: InkPreset {
        get { activeInkTool == .highlighter ? highlighter : pen }
        set { if activeInkTool == .highlighter { highlighter = newValue } else { pen = newValue } }
    }

    func toggleCircleSearch() {
        tool = isCircleSearch ? lastInkTool : .circleSearch
    }

    func handlePencilTap(_ response: PencilTapResponse) {
        #if DEBUG
        PencilTapLog.handle.notice("handlePencilTap \(String(describing: response), privacy: .public) tool=\(self.tool.rawValue, privacy: .public)")
        print("PCPencil handlePencilTap \(response) tool=\(tool.rawValue)")
        #endif
        switch response {
        case .toggleEraser:
            tool = tool == .eraser ? (previousTool == .eraser ? lastInkTool : previousTool) : .eraser
        case .switchToPrevious:
            tool = previousTool
        case .showInkOptions:
            if !tool.isInk { tool = lastInkTool }
            isShowingInkOptions.toggle()
        case .toggleCircleSearch:
            toggleCircleSearch()
        case .none:
            break
        }
    }

    /// The PencilKit tool for the current selection. Circle Search draws nothing into the canvas.
    var pkTool: PKTool {
        switch tool {
        case .pen, .circleSearch:
            PKInkingTool(pen.penType.inkType, color: pen.swatch.color, width: pen.width.points)
        case .highlighter:
            PKInkingTool(.marker, color: highlighter.swatch.color.withAlphaComponent(0.35),
                         width: highlighter.width.points * Self.highlighterWidthScale)
        case .eraser:
            switch eraserMode {
            case .stroke: PKEraserTool(.vector)
            case .pixel: PKEraserTool(.fixedWidthBitmap, width: eraserWidth.points)
            }
        }
    }

    func undo() {
        undoManager.undo()
        refreshUndoState()
    }

    func redo() {
        undoManager.redo()
        refreshUndoState()
    }

    func refreshUndoState() {
        canUndo = undoManager.canUndo
        canRedo = undoManager.canRedo
    }
}
