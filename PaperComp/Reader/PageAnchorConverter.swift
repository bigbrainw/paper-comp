import PDFKit

/// Maps page-space rects (circled regions, markers) into the reader's PDF view, whose frame the search card overlay shares.
@MainActor
final class PageAnchorConverter {
    weak var pdfView: PDFView?

    func viewRect(pageIndex: Int, pageRect: CGRect) -> CGRect? {
        guard let pdfView, let page = pdfView.document?.page(at: pageIndex) else { return nil }
        return Self.viewRect(for: pageRect, on: page, in: pdfView)
    }

    static func viewRect(for pageRect: CGRect, on page: PDFPage, in pdfView: PDFView) -> CGRect {
        pdfView.convert(pageRect, from: page).standardized
    }
}
