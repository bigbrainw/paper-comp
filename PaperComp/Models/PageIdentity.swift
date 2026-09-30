import Foundation
import PDFKit
import SwiftData

/// Builds the per-document page list and remaps legacy `pageIndex` keys onto stable `pageID`s.
enum PageIdentity {
    static func makeOriginalPages(count: Int) -> [PageRef] {
        (0..<max(0, count)).map { PageRef(kind: .pdf(originalIndex: $0)) }
    }

    static func pageID(in pages: [PageRef], at index: Int) -> UUID? {
        pages.indices.contains(index) ? pages[index].id : nil
    }

    /// Creates original-page refs when missing, then maps leftover `pageIndex` rows onto those IDs.
    /// Safe to run twice: existing page IDs are kept, so ink does not move.
    @discardableResult
    static func migrate(
        document: PaperDocument,
        originalPageCount: Int,
        drawings: [PageDrawing],
        records: [SearchRecord]
    ) -> [PageRef] {
        if document.pages.isEmpty, !document.isNotebook {
            document.pages = makeOriginalPages(count: originalPageCount)
        }
        let pages = document.pages
        for drawing in drawings where drawing.pageID == nil {
            drawing.pageID = pageID(in: pages, at: drawing.pageIndex)
        }
        for record in records where record.pageID == nil {
            record.pageID = pageID(in: pages, at: record.pageIndex)
        }
        return pages
    }

    static func migrate(document: PaperDocument, originalPageCount: Int, in context: ModelContext) {
        let id = document.id
        let drawings = (try? context.fetch(
            FetchDescriptor<PageDrawing>(predicate: #Predicate { $0.documentID == id })
        )) ?? []
        let records = (try? context.fetch(
            FetchDescriptor<SearchRecord>(predicate: #Predicate { $0.documentID == id })
        )) ?? []
        _ = migrate(document: document, originalPageCount: originalPageCount, drawings: drawings, records: records)
    }

    /// In-memory document: original pages copied in list order plus generated notes. Never writes the source file.
    static func compose(pages: [PageRef], original: PDFDocument?) -> PDFDocument {
        let composed = PDFDocument()
        var neighbor: CGRect?
        for ref in pages {
            switch ref.kind {
            case .pdf(let originalIndex):
                guard let original, let page = original.page(at: originalIndex),
                      let copy = page.copy() as? PDFPage else { continue }
                neighbor = page.bounds(for: .mediaBox)
                composed.insert(copy, at: composed.pageCount)
            case .note(let template, let size, let color):
                guard let page = NotePageRenderer.makePage(
                    template: template, size: size, color: color, matching: neighbor
                ), let copy = page.copy() as? PDFPage else { continue }
                neighbor = page.bounds(for: .mediaBox)
                composed.insert(copy, at: composed.pageCount)
            }
        }
        return composed
    }

    enum InsertPosition: String, CaseIterable, Sendable {
        case after, before, end
    }

    static func insertIndex(position: InsertPosition, currentIndex: Int, count: Int) -> Int {
        switch position {
        case .after: min(currentIndex + 1, count)
        case .before: max(currentIndex, 0)
        case .end: count
        }
    }

    /// PDF pages keep their relative order; only note pages may be reordered.
    static func canMove(_ pages: [PageRef], from source: Int, to destination: Int) -> Bool {
        guard pages.indices.contains(source), destination >= 0, destination <= pages.count else { return false }
        guard case .note = pages[source].kind else { return false }
        var next = pages
        let item = next.remove(at: source)
        let dest = source < destination ? destination - 1 : destination
        next.insert(item, at: min(max(dest, 0), next.count))
        return originalOrderUnchanged(next, versus: pages)
    }

    static func move(_ pages: inout [PageRef], from source: Int, to destination: Int) -> Bool {
        guard canMove(pages, from: source, to: destination) else { return false }
        let item = pages.remove(at: source)
        let dest = source < destination ? destination - 1 : destination
        pages.insert(item, at: min(max(dest, 0), pages.count))
        return true
    }

    static func originalOrderUnchanged(_ pages: [PageRef], versus previous: [PageRef]) -> Bool {
        pdfIndexes(in: pages) == pdfIndexes(in: previous)
    }

    private static func pdfIndexes(in pages: [PageRef]) -> [Int] {
        pages.compactMap {
            if case .pdf(let index) = $0.kind { index } else { nil }
        }
    }
}
