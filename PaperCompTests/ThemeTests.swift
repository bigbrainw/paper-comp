import SwiftUI
import Testing
import UIKit
@testable import PaperComp

@MainActor
struct ThemeTests {
    private func rgb(_ color: UIColor) -> (Int, Int, Int) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        return (Int((r * 255).rounded()), Int((g * 255).rounded()), Int((b * 255).rounded()))
    }

    private func resolved(_ color: Color, _ style: UIUserInterfaceStyle) -> UIColor {
        UIColor(color).resolvedColor(with: UITraitCollection(userInterfaceStyle: style))
    }

    @Test func hexInitSplitsComponents() {
        let (r, g, b) = rgb(UIColor(Color(hex: 0xA8804F)))
        #expect(r == 0xA8 && g == 0x80 && b == 0x4F)
    }

    @Test func paletteAdaptsToDarkMode() {
        for color in [Theme.rice, Theme.riceSurface, Theme.riceDeep, Theme.ink, Theme.inkSoft, Theme.accent, Theme.danger, Theme.cardSurface, Theme.cardInk] {
            #expect(rgb(resolved(color, .light)) != rgb(resolved(color, .dark)))
        }
        let (r, g, b) = rgb(resolved(Theme.rice, .dark))
        #expect(r == 0x1E && g == 0x1B && b == 0x17)
        let espresso = rgb(resolved(Theme.cardSurface, .light))
        #expect(espresso.0 == 0x2F && espresso.1 == 0x2A && espresso.2 == 0x24)
        let creamInk = rgb(resolved(Theme.cardInk, .light))
        #expect(creamInk.0 == 0xF4 && creamInk.1 == 0xEE && creamInk.2 == 0xE3)
    }

    @Test func backgroundsAreNeverPureWhiteOrBlack() {
        for color in [Theme.rice, Theme.riceSurface] {
            for style in [UIUserInterfaceStyle.light, .dark] {
                let (r, g, b) = rgb(resolved(color, style))
                #expect(!(r == 255 && g == 255 && b == 255))
                #expect(!(r == 0 && g == 0 && b == 0))
            }
        }
    }

    @Test func libraryOrderingSortsAndFilters() {
        let old = PaperDocument(title: "Zebra", fileName: "z.pdf", addedAt: .distantPast)
        let new = PaperDocument(title: "apple", fileName: "a.pdf", addedAt: .now)
        let docs = [old, new]
        #expect(LibraryOrdering.apply(docs, sort: .recent, notesOnly: false, withNotes: []).map(\.title) == ["apple", "Zebra"])
        #expect(LibraryOrdering.apply(docs, sort: .title, notesOnly: false, withNotes: []).map(\.title) == ["apple", "Zebra"])
        #expect(LibraryOrdering.apply([new, old], sort: .title, notesOnly: false, withNotes: []).first?.title == "apple")
        #expect(LibraryOrdering.apply(docs, sort: .recent, notesOnly: true, withNotes: [old.id]).map(\.title) == ["Zebra"])
    }
}
