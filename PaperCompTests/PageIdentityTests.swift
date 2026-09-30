import Foundation
import PDFKit
import PencilKit
import SwiftData
import Testing
import UIKit
@testable import PaperComp

@MainActor
struct PageIdentityTests {
    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: PaperDocument.self, PageDrawing.self, SearchRecord.self,
            configurations: config
        )
        return ModelContext(container)
    }

    private func drawing(offset: CGFloat) -> PKDrawing {
        let points = (0..<6).map { (i: Int) -> PKStrokePoint in
            let t = CGFloat(i)
            return PKStrokePoint(
                location: CGPoint(x: offset + t * 4, y: 10 + t * 2),
                timeOffset: TimeInterval(i) * 0.01,
                size: CGSize(width: 3, height: 3),
                opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2
            )
        }
        return PKDrawing(strokes: [PKStroke(ink: PKInk(.pen, color: .blue), path: PKStrokePath(controlPoints: points, creationDate: .now))])
    }

    private func samplePDF(pageCount: Int) throws -> (url: URL, data: Data, pdf: PDFDocument) {
        let bounds = CGRect(x: 0, y: 0, width: 200, height: 280)
        let data = UIGraphicsPDFRenderer(bounds: bounds).pdfData { renderer in
            for index in 0..<pageCount {
                renderer.beginPage()
                ("Page \(index)" as NSString).draw(
                    at: CGPoint(x: 24, y: 24),
                    withAttributes: [.font: UIFont.systemFont(ofSize: 18)]
                )
            }
        }
        let url = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).pdf")
        try data.write(to: url)
        let pdf = try #require(PDFDocument(data: data))
        return (url, data, pdf)
    }

    @Test func insertIndexEndLandsAtCount() {
        #expect(PageIdentity.insertIndex(position: .end, currentIndex: 0, count: 0) == 0)
        #expect(PageIdentity.insertIndex(position: .end, currentIndex: 2, count: 5) == 5)
        #expect(PageIdentity.insertIndex(position: .after, currentIndex: 2, count: 5) == 3)
        #expect(PageIdentity.insertIndex(position: .before, currentIndex: 2, count: 5) == 2)
    }

    @Test func pullAppendUsesNoteInsertSettingsAtEnd() {
        let defaults = UserDefaults.standard
        let priorTemplate = defaults.string(forKey: NoteInsertSettings.templateKey)
        let priorColor = defaults.string(forKey: NoteInsertSettings.colorKey)
        let priorPosition = defaults.string(forKey: NoteInsertSettings.positionKey)
        let priorSize = defaults.string(forKey: NoteInsertSettings.sizeKey)
        defer {
            defaults.set(priorTemplate, forKey: NoteInsertSettings.templateKey)
            defaults.set(priorColor, forKey: NoteInsertSettings.colorKey)
            defaults.set(priorPosition, forKey: NoteInsertSettings.positionKey)
            defaults.set(priorSize, forKey: NoteInsertSettings.sizeKey)
        }
        NoteInsertSettings.remember(
            template: .grid, color: .dark, position: .after, size: .letter
        )
        #expect(NoteInsertSettings.template == .grid)
        #expect(NoteInsertSettings.color == .dark)
        #expect(NoteInsertSettings.size == .letter)

        var pages = PageIdentity.makeOriginalPages(count: 2)
        let index = PageIdentity.insertIndex(
            position: .end, currentIndex: 0, count: pages.count
        )
        pages.insert(
            PageRef(kind: .note(
                template: NoteInsertSettings.template,
                size: NoteInsertSettings.size,
                color: NoteInsertSettings.color
            )),
            at: index
        )
        #expect(pages.count == 3)
        #expect(index == 2)
        guard case .note(let t, let s, let c) = pages[2].kind else {
            Issue.record("expected note at end")
            return
        }
        #expect(t == .grid)
        #expect(s == .letter)
        #expect(c == .dark)
    }

    @Test func migrationKeepsDrawingsOnTheSamePages() throws {
        let context = try makeContext()
        let document = PaperDocument(title: "Paper", fileName: "paper.pdf")
        context.insert(document)
        let page0 = drawing(offset: 10)
        let page2 = drawing(offset: 80)
        context.insert(PageDrawing(documentID: document.id, pageIndex: 0, drawingData: page0.dataRepresentation()))
        context.insert(PageDrawing(documentID: document.id, pageIndex: 2, drawingData: page2.dataRepresentation()))
        context.insert(SearchRecord(documentID: document.id, pageIndex: 1, pageRect: CGRect(x: 1, y: 2, width: 3, height: 4), question: "q"))

        let drawings = try context.fetch(FetchDescriptor<PageDrawing>())
        let records = try context.fetch(FetchDescriptor<SearchRecord>())
        let pages = PageIdentity.migrate(
            document: document, originalPageCount: 3, drawings: drawings, records: records
        )

        #expect(pages.count == 3)
        for (index, page) in pages.enumerated() {
            guard case .pdf(let originalIndex) = page.kind else {
                Issue.record("expected original PDF page")
                return
            }
            #expect(originalIndex == index)
        }

        #expect(drawings.first { $0.pageIndex == 0 }?.pageID == pages[0].id)
        #expect(drawings.first { $0.pageIndex == 2 }?.pageID == pages[2].id)
        #expect(drawings.first { $0.pageIndex == 0 }?.drawingData == page0.dataRepresentation())
        #expect(drawings.first { $0.pageIndex == 2 }?.drawingData == page2.dataRepresentation())

        let store = DrawingStore(context: context, documentID: document.id)
        #expect(store.drawing(for: pages[0].id).strokes.count == page0.strokes.count)
        #expect(store.drawing(for: pages[2].id).strokes.count == page2.strokes.count)
        #expect(store.drawing(for: pages[1].id).strokes.isEmpty)
        #expect(records.first?.pageID == pages[1].id)

        let again = PageIdentity.migrate(
            document: document, originalPageCount: 3, drawings: drawings, records: records
        )
        #expect(again.map(\.id) == pages.map(\.id))
        #expect(store.drawing(for: again[0].id).strokes.count == page0.strokes.count)
        #expect(store.drawing(for: again[2].id).strokes.count == page2.strokes.count)
        #expect(records.first?.pageID == again[1].id)
    }

    @Test func composeLeavesOriginalFileUnchanged() throws {
        let sample = try samplePDF(pageCount: 3)
        let before = try Data(contentsOf: sample.url)
        #expect(before == sample.data)

        let pages = PageIdentity.makeOriginalPages(count: 3)
        let composed = PageIdentity.compose(pages: pages, original: sample.pdf)
        #expect(composed.pageCount == 3)
        #expect(try Data(contentsOf: sample.url) == before)
        #expect(sample.pdf.pageCount == 3)
    }

    @Test func importCreatesPageRefsForEachOriginalPage() throws {
        let sample = try samplePDF(pageCount: 2)
        let context = try makeContext()
        let document = try DocumentStore.importPDF(from: sample.url, into: context)
        #expect(document.pages.count == 2)
        #expect(document.pages.enumerated().allSatisfy { index, page in
            if case .pdf(let originalIndex) = page.kind { originalIndex == index } else { false }
        })
        #expect(try Data(contentsOf: sample.url) == sample.data)
    }

    @Test func templatesMatchA4SizeAndLineSpacing() throws {
        for template in NoteTemplate.allCases {
            let page = try #require(NotePageRenderer.makePage(template: template, size: .a4, color: .white))
            #expect(abs(page.bounds(for: .mediaBox).width - NotePageRenderer.a4.width) < 0.5)
            #expect(abs(page.bounds(for: .mediaBox).height - NotePageRenderer.a4.height) < 0.5)
        }
        let college = NotePageRenderer.lineYs(in: NotePageRenderer.a4, spacing: NotePageRenderer.mmToPoints(7.1), inset: 36)
        let narrow = NotePageRenderer.lineYs(in: NotePageRenderer.a4, spacing: NotePageRenderer.mmToPoints(6), inset: 36)
        #expect(!college.isEmpty && !narrow.isEmpty)
        if college.count > 1 {
            #expect(abs((college[1] - college[0]) - NotePageRenderer.mmToPoints(7.1)) < 0.05)
        }
        if narrow.count > 1 {
            #expect(abs((narrow[1] - narrow[0]) - NotePageRenderer.mmToPoints(6)) < 0.05)
        }
        #expect(narrow.count > college.count)
    }

    @Test func insertingBeforeAfterAndEndKeepsInkOnPageIDs() throws {
        let context = try makeContext()
        let sample = try samplePDF(pageCount: 2)
        let document = try DocumentStore.importPDF(from: sample.url, into: context)
        let store = DrawingStore(context: context, documentID: document.id)
        let firstID = document.pages[0].id
        let lastID = document.pages[1].id
        let firstInk = drawing(offset: 4)
        let lastInk = drawing(offset: 90)
        store.save(firstInk, for: firstID, pageIndex: 0)
        store.save(lastInk, for: lastID, pageIndex: 1)

        var pages = document.pages
        pages.insert(PageRef(kind: .note(template: .blank, size: .matching, color: .rice)), at: 0)
        document.pages = pages
        #expect(store.drawing(for: firstID).strokes.count == firstInk.strokes.count)
        #expect(store.drawing(for: lastID).strokes.count == lastInk.strokes.count)

        pages.insert(PageRef(kind: .note(template: .grid, size: .matching, color: .white)), at: 2)
        document.pages = pages
        pages.append(PageRef(kind: .note(template: .dotted, size: .matching, color: .white)))
        document.pages = pages
        #expect(document.pages.count == 5)
        #expect(store.drawing(for: firstID).strokes.count == firstInk.strokes.count)
        #expect(store.drawing(for: lastID).strokes.count == lastInk.strokes.count)
        #expect(try Data(contentsOf: sample.url) == sample.data)
    }

    @Test func reorderingNotePagesPersistsAndKeepsPDFOrder() {
        var pages = PageIdentity.makeOriginalPages(count: 2)
        let pdf0 = pages[0].id
        let pdf1 = pages[1].id
        let noteA = PageRef(kind: .note(template: .blank, size: .a4, color: .rice))
        let noteB = PageRef(kind: .note(template: .grid, size: .a4, color: .white))
        pages.insert(noteA, at: 1)
        pages.append(noteB)
        #expect(PageIdentity.move(&pages, from: 3, to: 1))
        #expect(pages.map(\.id) == [pdf0, noteB.id, noteA.id, pdf1])
        #expect(pages.compactMap { if case .pdf(let i) = $0.kind { i } else { nil } } == [0, 1])
        #expect(!PageIdentity.canMove(pages, from: 0, to: 2))
    }

    @Test func exportIncludesNotePagesInOrder() throws {
        let sample = try samplePDF(pageCount: 2)
        var pages = PageIdentity.makeOriginalPages(count: 2)
        pages.insert(PageRef(kind: .note(template: .linedCollege, size: .matching, color: .rice)), at: 1)
        let data = try #require(AnnotatedPDF.make(pages: pages, original: sample.pdf, drawings: [:]))
        let exported = try #require(PDFDocument(data: data))
        #expect(exported.pageCount == 3)
        #expect(try Data(contentsOf: sample.url) == sample.data)
    }

    @Test func strokeDrawingRasterizesDarkPixels() {
        let bounds = CGRect(x: 0, y: 0, width: 200, height: 280)
        let region = CGRect(x: 40, y: 80, width: 50, height: 24)
        let drawing = strokeDrawing(in: region)
        #expect(!drawing.strokes.isEmpty)
        #expect(drawing.bounds.width > 0)
        var ink = UIImage()
        UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
            ink = drawing.image(from: bounds, scale: 2)
        }
        #expect(darkPixelCount(ink, in: region, scale: ink.scale) > 20,
                "ink pixels \(darkPixelCount(ink, in: region, scale: ink.scale)) size=\(ink.size) scale=\(ink.scale)")
    }

    @Test func exportFlattensDistinctInkOnEveryPageIncludingNote() throws {
        let sample = try samplePDF(pageCount: 2)
        var pages = PageIdentity.makeOriginalPages(count: 2)
        let note = PageRef(kind: .note(template: .blank, size: .matching, color: .white))
        pages.insert(note, at: 1)

        // Distinct stroke regions so each exported page can be checked independently.
        // Keep clear of the sample PDF's "Page N" label near (24, 24).
        let region0 = CGRect(x: 40, y: 80, width: 50, height: 24)
        let regionNote = CGRect(x: 80, y: 140, width: 50, height: 24)
        let region2 = CGRect(x: 120, y: 200, width: 50, height: 24)
        let drawings: [UUID: PKDrawing] = [
            pages[0].id: strokeDrawing(in: region0),
            pages[1].id: strokeDrawing(in: regionNote),
            pages[2].id: strokeDrawing(in: region2),
        ]

        let blankData = try #require(AnnotatedPDF.make(pages: pages, original: sample.pdf, drawings: [:]))
        let data = try #require(AnnotatedPDF.make(pages: pages, original: sample.pdf, drawings: drawings))
        #expect(data.count > blankData.count,
                "inked \(data.count) blank \(blankData.count)")

        // Prove flatten itself has ink in UIKit top-left space before PDF round-trip.
        let composed = PageIdentity.compose(pages: pages, original: sample.pdf)
        for (index, region) in [region0, regionNote, region2].enumerated() {
            let page = try #require(composed.page(at: index))
            let bounds = page.bounds(for: .mediaBox)
            let flat = AnnotatedPDF.flattenedPageImage(
                page: page, bounds: bounds, drawing: drawings[pages[index].id], scale: 2
            )
            let blankFlat = AnnotatedPDF.flattenedPageImage(page: page, bounds: bounds, drawing: nil, scale: 2)
            #expect(
                darkPixelCount(flat, in: region, scale: flat.scale)
                    > darkPixelCount(blankFlat, in: region, scale: blankFlat.scale) + 8,
                "flatten[\(index)]"
            )
        }

        let exported = try #require(PDFDocument(data: data))
        #expect(exported.pageCount == 3)
        #expect(try #require(PDFDocument(data: blankData)).pageCount == 3)

        let page0 = try #require(exported.page(at: 0))
        let page1 = try #require(exported.page(at: 1))
        let page2 = try #require(exported.page(at: 2))
        #expect(page0.bounds(for: .mediaBox).size == sample.pdf.page(at: 0)!.bounds(for: .mediaBox).size)
        #expect(page2.bounds(for: .mediaBox).size == sample.pdf.page(at: 1)!.bounds(for: .mediaBox).size)
        #expect(page1.bounds(for: .mediaBox).size == page0.bounds(for: .mediaBox).size)

        // Each page of the multipage export must embed its own ink.
        #expect(cgPDFFullDark(data, pageIndex: 0) > cgPDFFullDark(blankData, pageIndex: 0) + 30, "full0")
        #expect(cgPDFFullDark(data, pageIndex: 1) > cgPDFFullDark(blankData, pageIndex: 1) + 30, "full1")
        #expect(cgPDFFullDark(data, pageIndex: 2) > cgPDFFullDark(blankData, pageIndex: 2) + 30, "full2")

        // Ink scoped to one page must not spill onto the others.
        let onlyNote = try #require(AnnotatedPDF.make(
            pages: pages, original: sample.pdf, drawings: [pages[1].id: drawings[pages[1].id]!]
        ))
        #expect(cgPDFFullDark(onlyNote, pageIndex: 1) > cgPDFFullDark(blankData, pageIndex: 1) + 30, "note-only target")
        #expect(cgPDFFullDark(onlyNote, pageIndex: 0) <= cgPDFFullDark(blankData, pageIndex: 0) + 5, "note-only no spill0")
        #expect(cgPDFFullDark(onlyNote, pageIndex: 2) <= cgPDFFullDark(blankData, pageIndex: 2) + 5, "note-only no spill2")
        #expect(try Data(contentsOf: sample.url) == sample.data)
    }

    @Test func exportPreservesVariablePageSizesWithInk() throws {
        let sample = try samplePDF(pageCount: 1)
        var pages = PageIdentity.makeOriginalPages(count: 1)
        let note = PageRef(kind: .note(template: .blank, size: .a4, color: .white))
        pages.append(note)
        let pdfRegion = CGRect(x: 40, y: 80, width: 50, height: 24)
        let noteRegion = CGRect(x: 70, y: 120, width: 50, height: 24)
        let drawings: [UUID: PKDrawing] = [
            pages[0].id: strokeDrawing(in: pdfRegion),
            pages[1].id: strokeDrawing(in: noteRegion),
        ]
        let blankData = try #require(AnnotatedPDF.make(pages: pages, original: sample.pdf, drawings: [:]))
        let data = try #require(AnnotatedPDF.make(pages: pages, original: sample.pdf, drawings: drawings))
        let exported = try #require(PDFDocument(data: data))
        #expect(exported.pageCount == 2)
        let pdfSize = try #require(exported.page(at: 0)).bounds(for: .mediaBox).size
        let noteSize = try #require(exported.page(at: 1)).bounds(for: .mediaBox).size
        #expect(abs(pdfSize.width - 200) < 0.5)
        #expect(abs(pdfSize.height - 280) < 0.5)
        #expect(abs(noteSize.width - NotePageRenderer.a4.width) < 0.5)
        #expect(abs(noteSize.height - NotePageRenderer.a4.height) < 0.5)
        #expect(cgPDFFullDark(data, pageIndex: 0) > cgPDFFullDark(blankData, pageIndex: 0) + 30)
        #expect(cgPDFFullDark(data, pageIndex: 1) > cgPDFFullDark(blankData, pageIndex: 1) + 30)
        #expect(try Data(contentsOf: sample.url) == sample.data)
    }

    @Test func mergedDrawingsPreferLiveSnapshots() {
        let pageID = UUID()
        let otherID = UUID()
        let persistedOnly = strokeDrawing(in: CGRect(x: 10, y: 10, width: 30, height: 12))
        let stale = strokeDrawing(in: CGRect(x: 20, y: 20, width: 30, height: 12))
        let live = strokeDrawing(in: CGRect(x: 30, y: 30, width: 30, height: 12))
        let merged = AnnotatedPDF.mergedDrawings(
            persisted: [pageID: stale, otherID: persistedOnly],
            live: [pageID: live]
        )
        #expect(merged[pageID]?.dataRepresentation() == live.dataRepresentation())
        #expect(merged[otherID]?.dataRepresentation() == persistedOnly.dataRepresentation())
    }

    private func strokeDrawing(in rect: CGRect) -> PKDrawing {
        let points = (0..<10).map { (i: Int) -> PKStrokePoint in
            let t = CGFloat(i) / 9
            return PKStrokePoint(
                location: CGPoint(x: rect.minX + rect.width * t, y: rect.midY),
                timeOffset: TimeInterval(i) * 0.01,
                size: CGSize(width: 8, height: 8),
                opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2
            )
        }
        return PKDrawing(strokes: [
            PKStroke(ink: PKInk(.pen, color: .black), path: PKStrokePath(controlPoints: points, creationDate: .now))
        ])
    }

    private func renderCGPDFPage(_ data: Data, at index: Int) -> UIImage? {
        guard let provider = CGDataProvider(data: data as CFData),
              let pdf = CGPDFDocument(provider),
              let page = pdf.page(at: index + 1)
        else { return nil }
        let box = page.getBoxRect(.mediaBox)
        let scale: CGFloat = 2
        let size = CGSize(width: box.width * scale, height: box.height * scale)
        return UIGraphicsImageRenderer(size: size).image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            let cg = ctx.cgContext
            cg.saveGState()
            cg.translateBy(x: 0, y: size.height)
            cg.scaleBy(x: scale, y: -scale)
            cg.drawPDFPage(page)
            cg.restoreGState()
        }
    }

    private func cgPDFFullDark(_ data: Data, pageIndex: Int) -> Int {
        guard let image = renderCGPDFPage(data, at: pageIndex) else { return 0 }
        return darkPixelCount(image, in: CGRect(origin: .zero, size: image.size), scale: image.scale)
    }

    private func darkPixelCount(_ image: UIImage, in rect: CGRect, scale: CGFloat) -> Int {
        guard let cgImage = image.cgImage else { return 0 }
        let minX = max(0, Int(rect.minX * scale))
        let maxX = min(cgImage.width - 1, Int(rect.maxX * scale))
        let minY = max(0, Int(rect.minY * scale))
        let maxY = min(cgImage.height - 1, Int(rect.maxY * scale))
        guard minX <= maxX, minY <= maxY else { return 0 }
        var data = [UInt8](repeating: 0, count: cgImage.width * cgImage.height * 4)
        guard let context = CGContext(
            data: &data, width: cgImage.width, height: cgImage.height,
            bitsPerComponent: 8, bytesPerRow: cgImage.width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return 0 }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))
        var count = 0
        for y in stride(from: minY, through: maxY, by: 1) {
            for x in stride(from: minX, through: maxX, by: 1) {
                let i = (y * cgImage.width + x) * 4
                let brightness = (CGFloat(data[i]) + CGFloat(data[i + 1]) + CGFloat(data[i + 2])) / (3 * 255)
                if brightness < 0.55 { count += 1 }
            }
        }
        return count
    }
}
