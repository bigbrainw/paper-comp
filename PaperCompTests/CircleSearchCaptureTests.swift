import PDFKit
import Testing
import UIKit
@testable import PaperComp

@MainActor
struct CircleSearchCaptureTests {
    static let pageSize = CGSize(width: 612, height: 792)
    static let topLine = "Attention is all you need"
    static let bottomLine = "Figure caption lives down here"

    /// One US Letter page: a sentence near the top, another near the bottom, filler in between.
    private func makePDF() throws -> PDFDocument {
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: Self.pageSize))
        let data = renderer.pdfData { context in
            context.beginPage()
            let font = [NSAttributedString.Key.font: UIFont.systemFont(ofSize: 18)]
            (Self.topLine as NSString).draw(at: CGPoint(x: 72, y: 72), withAttributes: font)
            let filler = String(repeating: "lorem ipsum dolor sit amet ", count: 90)
            (filler as NSString).draw(in: CGRect(x: 72, y: 200, width: 468, height: 400), withAttributes: font)
            (Self.bottomLine as NSString).draw(at: CGPoint(x: 72, y: 700), withAttributes: font)
        }
        return try #require(PDFDocument(data: data))
    }

    /// A rectangle given in top-left UIKit page coordinates, as a path in PDF page space (bottom-left origin).
    private func pagePath(topLeftRect rect: CGRect) -> CGPath {
        let flipped = CGRect(x: rect.minX, y: Self.pageSize.height - rect.maxY, width: rect.width, height: rect.height)
        return CGPath(ellipseIn: flipped.insetBy(dx: -20, dy: -8), transform: nil)
    }

    @Test func extractsCircledText() throws {
        let page = try #require(makePDF().page(at: 0))
        let path = pagePath(topLeftRect: CGRect(x: 72, y: 72, width: 240, height: 22))

        let text = CircleSearchCapture.selectedText(in: path, on: page)
        #expect(text.contains("Attention"))
        #expect(text.contains("need"))
        #expect(!text.contains("caption"))
    }

    @Test func buildsFullCapture() throws {
        let pdf = try makePDF()
        let page = try #require(pdf.page(at: 0))
        let path = pagePath(topLeftRect: CGRect(x: 72, y: 700, width: 280, height: 22))
        let id = UUID()

        let capture = try #require(CircleSearchCapture.make(
            path: path, page: page, pageIndex: 0, documentID: id, paperTitle: "Test Paper"
        ))
        #expect(capture.selectedText.contains("caption"))
        #expect(!capture.selectedText.contains("Attention"))
        #expect(capture.documentID == id)
        #expect(capture.paperTitle == "Test Paper")
        #expect(capture.pageRect.minY < 100, "page-space rect should be near the bottom (origin bottom-left)")
        #expect(capture.containsInk == false)
        let longPixels = max(capture.image.size.width, capture.image.size.height) * capture.image.scale
        #expect(longPixels <= CaptureRenderScale.maxLongEdge + 1)
        #expect(abs(capture.image.size.width - capture.pageRect.width) < 1)
        #expect(capture.surroundingText.count <= CircleSearchCapture.contextLength)
        #expect(capture.surroundingText.contains("caption"))
    }

    @Test func rejectsTinyOrOffPageLasso() throws {
        let page = try #require(makePDF().page(at: 0))
        let tiny = CGPath(rect: CGRect(x: 100, y: 100, width: 1, height: 1), transform: nil)
        let offPage = CGPath(rect: CGRect(x: 2000, y: 2000, width: 50, height: 50), transform: nil)
        #expect(CircleSearchCapture.make(path: tiny, page: page, pageIndex: 0, documentID: UUID(), paperTitle: "") == nil)
        #expect(CircleSearchCapture.make(path: offPage, page: page, pageIndex: 0, documentID: UUID(), paperTitle: "") == nil)
    }

    @Test func titleFallsBackToFirstLine() throws {
        #expect(PaperTitle.title(of: try makePDF(), fallback: "file") == Self.topLine)
    }

    @Test func snapsBoxEdgesNearTextLines() throws {
        let page = try #require(makePDF().page(at: 0))
        let loose = CGRect(x: 74, y: page.bounds(for: .cropBox).maxY - 96, width: 236, height: 20)
        let snapped = CircleSearchCapture.snapRect(loose, on: page)
        #expect(abs(snapped.minX - 72) <= SearchSelectionSettings.snapThreshold)
        #expect(snapped.height >= loose.height)
    }

    @Test func tinyBoxTapSelectsWord() throws {
        let page = try #require(makePDF().page(at: 0))
        let path = pagePath(topLeftRect: CGRect(x: 72, y: 72, width: 240, height: 22))
        let box = path.boundingBoxOfPath
        let lineSelection = try #require(page.selection(for: box))
        let lineBounds = lineSelection.bounds(for: page)
        var wordPoint = CGPoint(x: lineBounds.minX + 12, y: lineBounds.midY)
        if page.selectionForWord(at: wordPoint) == nil {
            wordPoint = CGPoint(x: lineBounds.midX, y: lineBounds.midY)
        }
        let capture = try #require(CircleSearchCapture.makeFromTap(
            at: wordPoint, page: page, pageIndex: 0, documentID: UUID(), paperTitle: "T"
        ))
        #expect(capture.selectedText.localizedCaseInsensitiveContains("attention"))
    }

    @Test func boxRectMakeUsesSnappedSelection() throws {
        let page = try #require(makePDF().page(at: 0))
        let box = CGRect(x: 72, y: page.bounds(for: .cropBox).maxY - 96, width: 240, height: 22)
        let capture = try #require(CircleSearchCapture.make(
            pageRect: box, page: page, pageIndex: 0, documentID: UUID(), paperTitle: "T"
        ))
        #expect(capture.selectedText.contains("Attention"))
        #expect(capture.pageRect.width >= 200)
    }

    @Test func titlePrefersLargestTextOverArXivStamp() throws {
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: Self.pageSize))
        let data = renderer.pdfData { context in
            context.beginPage()
            ("arXiv:1706.03762v7 [cs.CL] 2 Aug 2023" as NSString)
                .draw(at: CGPoint(x: 20, y: 40), withAttributes: [.font: UIFont.systemFont(ofSize: 20)])
            ("Provided proper attribution is provided" as NSString)
                .draw(at: CGPoint(x: 72, y: 80), withAttributes: [.font: UIFont.systemFont(ofSize: 12)])
            (Self.topLine as NSString)
                .draw(at: CGPoint(x: 72, y: 120), withAttributes: [.font: UIFont.systemFont(ofSize: 17)])
        }
        let pdf = try #require(PDFDocument(data: data))
        #expect(PaperTitle.title(of: pdf, fallback: "file") == Self.topLine)
    }

    @Test func renderCropRectAccountsForOffsetCropBox() {
        let cropBox = CGRect(x: 40, y: 60, width: 500, height: 680)
        let pageRect = CGRect(x: 140, y: 200, width: 100, height: 40)
        let mapped = CircleSearchCapture.renderCropRect(
            pageRect: pageRect, cropBox: cropBox, renderSize: cropBox.size
        )
        #expect(abs(mapped.minX - 100) < 0.5)
        #expect(abs(mapped.width - 100) < 0.5)
        #expect(abs(mapped.height - 40) < 0.5)
        #expect(abs(mapped.minY - 500) < 0.5)
    }

    @Test func renderImageCropsOffsetCropBoxRegion() throws {
        let media = CGRect(x: 0, y: 0, width: Self.pageSize.width, height: Self.pageSize.height)
        let cropBox = CGRect(x: 50, y: 70, width: 500, height: 650)
        let pageRect = CGRect(x: 200, y: 300, width: 80, height: 40)
        let page = try makeOffsetCropPage(media: media, cropBox: cropBox, redRect: pageRect)

        let mapped = CircleSearchCapture.renderCropRect(
            pageRect: pageRect, cropBox: cropBox, renderSize: cropBox.size
        )
        #expect(abs(mapped.minX - (pageRect.minX - cropBox.minX)) < 0.5)
        #expect(abs(mapped.width - pageRect.width) < 0.5)

        let image = CircleSearchCapture.renderImage(of: pageRect, on: page, scale: 2)
        #expect(abs(image.size.width - pageRect.width) < 3)
        #expect(abs(image.size.height - pageRect.height) < 3)
        #expect(abs(image.size.width / image.size.height - pageRect.width / pageRect.height) < 0.15)
        #expect(abs(image.size.width / image.size.height - cropBox.width / cropBox.height) > 0.4)

        let center = try #require(image.centerRGB())
        #expect(center.r > 0.55)
        #expect(center.g < 0.45)
        #expect(center.b < 0.45)
    }

    private func makeOffsetCropPage(media: CGRect, cropBox: CGRect, redRect: CGRect) throws -> PDFPage {
        let renderer = UIGraphicsPDFRenderer(bounds: media)
        let data = renderer.pdfData { context in
            context.beginPage()
            UIColor.white.setFill()
            context.fill(media)
            UIColor.blue.setFill()
            context.fill(CGRect(x: cropBox.minX, y: media.height - cropBox.maxY, width: 24, height: 24))
            UIColor.red.setFill()
            let ui = CGRect(
                x: redRect.minX,
                y: media.height - redRect.maxY,
                width: redRect.width,
                height: redRect.height
            )
            context.fill(ui)
        }
        let pdf = try #require(PDFDocument(data: data))
        let page = try #require(pdf.page(at: 0))
        page.setBounds(media, for: .mediaBox)
        page.setBounds(cropBox, for: .cropBox)
        return page
    }
}

private extension UIImage {
    func centerRGB() -> (r: CGFloat, g: CGFloat, b: CGFloat)? {
        guard let cgImage else { return nil }
        let x = cgImage.width / 2
        let y = cgImage.height / 2
        var pixel = [UInt8](repeating: 0, count: 4)
        guard let context = CGContext(
            data: &pixel,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.draw(cgImage, in: CGRect(x: -x, y: -y, width: cgImage.width, height: cgImage.height))
        return (CGFloat(pixel[0]) / 255, CGFloat(pixel[1]) / 255, CGFloat(pixel[2]) / 255)
    }
}
