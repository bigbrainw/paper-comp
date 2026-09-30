import SwiftUI

enum SearchCardStyle: String, CaseIterable {
    case dark, light

    static let storageKey = "searchCardStyle"
    static let defaultValue = SearchCardStyle.dark
}

/// Colors for the floating search card. Dark (default) is espresso; Light is rice with an accent border.
struct SearchCardPalette: Equatable {
    var surface: Color
    var deep: Color
    var ink: Color
    var inkSoft: Color
    var isDark: Bool
    var showsAccentBorder: Bool

    static func resolve(styleRaw: String) -> SearchCardPalette {
        styleRaw == SearchCardStyle.light.rawValue ? .light : .dark
    }

    static let dark = SearchCardPalette(
        surface: Theme.cardSurface,
        deep: Theme.cardDeep,
        ink: Theme.cardInk,
        inkSoft: Theme.cardInkSoft,
        isDark: true,
        showsAccentBorder: false
    )

    static let light = SearchCardPalette(
        surface: Theme.riceSurface,
        deep: Theme.riceDeep,
        ink: Theme.ink,
        inkSoft: Theme.inkSoft,
        isDark: false,
        showsAccentBorder: true
    )
}

private struct SearchCardPaletteKey: EnvironmentKey {
    static let defaultValue = SearchCardPalette.dark
}

private struct SearchCardWidthKey: EnvironmentKey {
    static let defaultValue: CGFloat = SearchCardPlacement.cardWidth
}

extension EnvironmentValues {
    var searchCardPalette: SearchCardPalette {
        get { self[SearchCardPaletteKey.self] }
        set { self[SearchCardPaletteKey.self] = newValue }
    }

    var searchCardWidth: CGFloat {
        get { self[SearchCardWidthKey.self] }
        set { self[SearchCardWidthKey.self] = newValue }
    }
}

/// Last laid-out search-card content width. Tests assert this is 420 in a full-screen host.
enum SearchCardLayoutProbe {
    nonisolated(unsafe) static var contentWidth: CGFloat = 0
}

struct SearchCardWidthProbe: UIViewRepresentable {
    func makeUIView(context: Context) -> SearchCardWidthProbeView { SearchCardWidthProbeView() }
    func updateUIView(_ uiView: SearchCardWidthProbeView, context: Context) {}
}

final class SearchCardWidthProbeView: UIView {
    override func layoutSubviews() {
        super.layoutSubviews()
        if bounds.width > 1 { SearchCardLayoutProbe.contentWidth = bounds.width }
    }
}
