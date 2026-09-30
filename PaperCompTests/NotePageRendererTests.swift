import Foundation
import PDFKit
import Testing
import UIKit
@testable import PaperComp

struct NotePageRendererTests {
    @Test func allCasesCountIsFourteen() {
        #expect(NoteTemplate.allCases.count == 14)
    }

    @Test func legacyRawValuesRemainStable() {
        #expect(NoteTemplate.blank.rawValue == "blank")
        #expect(NoteTemplate.linedCollege.rawValue == "linedCollege")
        #expect(NoteTemplate.linedNarrow.rawValue == "linedNarrow")
        #expect(NoteTemplate.grid.rawValue == "grid")
        #expect(NoteTemplate.dotted.rawValue == "dotted")
        #expect(NoteTemplate.cornell.rawValue == "cornell")
    }

    @Test func newRawValuesAreStable() {
        #expect(NoteTemplate.wideRuled.rawValue == "wideRuled")
        #expect(NoteTemplate.graph.rawValue == "graph")
        #expect(NoteTemplate.crossGrid.rawValue == "crossGrid")
        #expect(NoteTemplate.isometricDot.rawValue == "isometricDot")
        #expect(NoteTemplate.hexagon.rawValue == "hexagon")
        #expect(NoteTemplate.handwriting.rawValue == "handwriting")
        #expect(NoteTemplate.musicStaff.rawValue == "musicStaff")
        #expect(NoteTemplate.checklist.rawValue == "checklist")
    }

    @Test func pickerListsEveryCaseInOrder() {
        let labels = NoteTemplate.allCases.map(\.pillLabel)
        #expect(labels.count == NoteTemplate.allCases.count)
        #expect(NoteTemplate.allCases.map(\.rawValue) == [
            "blank", "linedCollege", "linedNarrow", "wideRuled",
            "grid", "graph", "crossGrid", "dotted",
            "isometricDot", "hexagon", "cornell", "handwriting",
            "musicStaff", "checklist",
        ])
        #expect(Set(labels).count == labels.count)
    }

    @Test func everyTemplateRendersForEachColorAndSize() throws {
        for template in NoteTemplate.allCases {
            for color in NotePaperColor.allCases {
                for size in [NotePageSize.a4, .letter] {
                    let page = try #require(NotePageRenderer.makePage(template: template, size: size, color: color))
                    let bounds = page.bounds(for: .mediaBox)
                    let expected = NotePageRenderer.bounds(for: size)
                    #expect(abs(bounds.width - expected.width) < 0.5)
                    #expect(abs(bounds.height - expected.height) < 0.5)
                    let data = NotePageRenderer.makePDFData(template: template, size: size, color: color)
                    #expect(!data.isEmpty)
                }
            }
        }
    }

    @Test func nonBlankTemplatesDifferFromBlankBitmap() throws {
        // Half-A4 raster so 0.6pt / low-alpha marks survive PDFKit downscaling.
        let size = CGSize(width: 298, height: 421)
        for color in NotePaperColor.allCases {
            let blankData = NotePageRenderer.makePDFData(template: .blank, size: .a4, color: color)
            let blankPNG = try #require(
                NotePageRenderer.thumbnail(template: .blank, color: color, size: size).pngData()
            )
            for template in NoteTemplate.allCases where template != .blank {
                let data = NotePageRenderer.makePDFData(template: template, size: .a4, color: color)
                #expect(data != blankData, "\(template.rawValue) PDF matched blank on \(color.rawValue)")
                let png = try #require(
                    NotePageRenderer.thumbnail(template: template, color: color, size: size).pngData()
                )
                #expect(png != blankPNG, "\(template.rawValue) bitmap matched blank on \(color.rawValue)")
            }
        }
    }
}
