import PDFKit
import Testing
import UIKit
@testable import PaperComp

@MainActor
struct PageAnchorTests {
    private func makePDFView(pages: Int = 2) -> PDFView {
        let data = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 612, height: 792)).pdfData { context in
            for _ in 0..<pages { context.beginPage() }
        }
        let pdfView = PDFView(frame: CGRect(x: 0, y: 0, width: 800, height: 1100))
        pdfView.displayMode = .singlePageContinuous
        pdfView.autoScales = true
        pdfView.document = PDFDocument(data: data)
        pdfView.layoutIfNeeded()
        return pdfView
    }

    @Test func pageRectMapsIntoViewWithFlippedY() throws {
        let pdfView = makePDFView()
        let page = try #require(pdfView.document?.page(at: 0))
        let top = CGRect(x: 100, y: 700, width: 200, height: 40)   // near the page top (page origin is bottom-left)
        let bottom = CGRect(x: 100, y: 50, width: 200, height: 40)

        let topView = PageAnchorConverter.viewRect(for: top, on: page, in: pdfView)
        let bottomView = PageAnchorConverter.viewRect(for: bottom, on: page, in: pdfView)
        #expect(topView.minY < bottomView.minY)
        #expect(topView.width > 0 && topView.height > 0)
        #expect(abs(topView.width / topView.height - 5) < 0.05, "aspect ratio is preserved")
        #expect(abs(topView.minX - bottomView.minX) < 0.5)
        #expect(pdfView.bounds.intersects(topView))
    }

    @Test func converterUsesPageIndexAndWeakView() throws {
        let converter = PageAnchorConverter()
        let rect = CGRect(x: 10, y: 10, width: 50, height: 50)
        #expect(converter.viewRect(pageIndex: 0, pageRect: rect) == nil)

        let pdfView = makePDFView()
        converter.pdfView = pdfView
        let page = try #require(pdfView.document?.page(at: 0))
        #expect(converter.viewRect(pageIndex: 0, pageRect: rect) == PageAnchorConverter.viewRect(for: rect, on: page, in: pdfView))
        #expect(converter.viewRect(pageIndex: 5, pageRect: rect) == nil)
    }
}
