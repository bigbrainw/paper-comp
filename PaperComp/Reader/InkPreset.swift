import Foundation
import PencilKit

enum PenType: String, CaseIterable, Identifiable {
    case ballpoint, fountain, pen, pencil, brush, crayon

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ballpoint: "Ballpoint"
        case .fountain: "Fountain"
        case .pen: "Pen"
        case .pencil: "Pencil"
        case .brush: "Brush"
        case .crayon: "Crayon"
        }
    }

    var inkType: PKInkingTool.InkType {
        switch self {
        case .ballpoint: .monoline
        case .fountain: .fountainPen
        case .pen: .pen
        case .pencil: .pencil
        case .brush: .watercolor
        case .crayon: .crayon
        }
    }
}

/// Pen type, color, and width remembered for one inking tool.
struct InkPreset: Equatable {
    var penType: PenType
    var swatch: InkSwatch
    var width: InkWidth

    static let penDefault = InkPreset(penType: .ballpoint, swatch: InkSwatch.all[0], width: .medium)
    static let highlighterDefault = InkPreset(penType: .pen, swatch: InkSwatch.all[5], width: .medium)

    init(penType: PenType, swatch: InkSwatch, width: InkWidth) {
        self.penType = penType
        self.swatch = swatch
        self.width = width
    }

    /// Reads `<prefix>.inkType`, `<prefix>.color`, `<prefix>.width`; missing or unknown values use `fallback`.
    init(defaults: UserDefaults, prefix: String, fallback: InkPreset) {
        penType = defaults.string(forKey: "\(prefix).inkType").flatMap(PenType.init(rawValue:)) ?? fallback.penType
        swatch = defaults.string(forKey: "\(prefix).color").flatMap(InkSwatch.named) ?? fallback.swatch
        width = defaults.string(forKey: "\(prefix).width").flatMap(InkWidth.init(rawValue:)) ?? fallback.width
    }

    func save(to defaults: UserDefaults, prefix: String) {
        defaults.set(penType.rawValue, forKey: "\(prefix).inkType")
        defaults.set(swatch.name, forKey: "\(prefix).color")
        defaults.set(width.rawValue, forKey: "\(prefix).width")
    }
}
