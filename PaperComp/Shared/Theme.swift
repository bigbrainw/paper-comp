import SwiftUI
import UIKit

/// The "rice paper" palette. Every color adapts to light and dark mode.
enum Theme {
    static let rice = Color(light: 0xF6F1E7, dark: 0x1E1B17)
    static let riceSurface = Color(light: 0xFBF8F2, dark: 0x27231E)
    static let riceDeep = Color(light: 0xECE3D2, dark: 0x332E27)
    static let ink = Color(light: 0x2E2922, dark: 0xEFE8DA)
    static let inkSoft = Color(light: 0x7D7264, dark: 0xA89D8C)
    static let accent = Color(light: 0xA8804F, dark: 0xC9A273)
    static let danger = Color(light: 0xB5533C, dark: 0xD9785F)
    static let cornerRadius: CGFloat = 14
    /// The sheet a PDF page is printed on; fixed in both modes so ink previews match the page.
    static let paper = Color(hex: 0xFDFBF6)

    /// Espresso search card: dark on cream paper, inverted in system dark mode.
    static let cardSurface = Color(light: 0x2F2A24, dark: 0xF4EEE3)
    static let cardInk = Color(light: 0xF4EEE3, dark: 0x2A251F)
    static let cardInkSoft = Color(light: 0xC4B8A8, dark: 0x6B6358)
    static let cardDeep = Color(light: 0x3A342C, dark: 0xE8DFD2)

    static let uiRice = UIColor(light: 0xF6F1E7, dark: 0x1E1B17)
    static let uiRiceSurface = UIColor(light: 0xFBF8F2, dark: 0x27231E)
    static let uiRiceDeep = UIColor(light: 0xECE3D2, dark: 0x332E27)
    static let uiInk = UIColor(light: 0x2E2922, dark: 0xEFE8DA)
    static let uiAccent = UIColor(light: 0xA8804F, dark: 0xC9A273)
    static let uiCardSurface = UIColor(light: 0x2F2A24, dark: 0xF4EEE3)
}

extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }

    convenience init(light: UInt32, dark: UInt32) {
        let lightColor = UIColor(hex: light)
        let darkColor = UIColor(hex: dark)
        self.init { $0.userInterfaceStyle == .dark ? darkColor : lightColor }
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(uiColor: UIColor(hex: hex))
    }

    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor(light: light, dark: dark))
    }
}

extension View {
    func riceShadow() -> some View {
        shadow(color: Theme.ink.opacity(0.08), radius: 12, y: 4)
    }

    func cardShadow() -> some View {
        shadow(color: Theme.ink.opacity(0.22), radius: 24, y: 8)
    }

    /// Translucent rice capsule that floats over the page (GoodNotes-style chrome).
    func readerFloatingChrome(square: Bool = false) -> some View {
        let shape = square
            ? AnyShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            : AnyShape(Capsule())
        return self
            .background {
                shape
                    .fill(.ultraThinMaterial)
                    .overlay { shape.fill(Theme.riceSurface.opacity(0.92)) }
            }
            .clipShape(shape)
            .shadow(color: Theme.ink.opacity(0.12), radius: 10, y: 3)
    }
}
