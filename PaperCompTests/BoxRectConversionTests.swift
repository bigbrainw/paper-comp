import PDFKit
import Testing
import UIKit
@testable import PaperComp

@MainActor
struct BoxRectConversionTests {
    @Test func viewRectMapsToPageSpace() throws {
        let pdfView = PDFView(frame: CGRect(x: 0, y: 0, width: 400, height: 600))
        let pdf = PDFDocument()
        let page = PDFPage()
        page.setBounds(CGRect(x: 0, y: 0, width: 612, height: 792), for: .cropBox)
        pdf.insert(page, at: 0)
        pdfView.document = pdf
        pdfView.autoScales = true
        pdfView.layoutIfNeeded()

        let viewRect = CGRect(x: 40, y: 80, width: 120, height: 60)
        let pageRect = PDFKitView.Coordinator.pageRect(fromViewRect: viewRect, on: page, in: pdfView)
        #expect(pageRect.width > 0)
        #expect(pageRect.height > 0)
        #expect(page.bounds(for: .cropBox).contains(pageRect))
    }
}
