import CoreGraphics
import PDFKit
import PencilKit
import Testing
import UIKit
@testable import PaperComp

struct InkCaptureGeometryTests {
    @Test func drawingRectFlipsYWithinPageBounds() {
        let pageBounds = CGRect(x: 10, y: 20, width: 200, height: 400)
        let pageRect = CGRect(x: 30, y: 50, width: 40, height: 20)
        let mapped = InkCaptureGeometry.drawingRect(pageRect: pageRect, pageBounds: pageBounds)
        #expect(abs(mapped.minX - 20) < 0.01)
        #expect(abs(mapped.width - 40) < 0.01)
        #expect(abs(mapped.height - 20) < 0.01)
        #expect(abs(mapped.minY - (pageBounds.maxY - pageRect.maxY)) < 0.01)
    }

    @Test func outputScaleCapsLongEdgeNear2048() {
        let large = CGRect(x: 0, y: 0, width: 1200, height: 800)
        let scale = CaptureRenderScale.scale(for: large)
        #expect(abs(scale * 1200 - CaptureRenderScale.maxLongEdge) < 0.5)

        let small = CGRect(x: 0, y: 0, width: 100, height: 40)
        let smallScale = CaptureRenderScale.scale(for: small)
        #expect(abs(smallScale * 100 - CaptureRenderScale.maxLongEdge) < 0.5)
        #expect(smallScale > 2)
    }

    @Test func backingScaleUsesZoomRelativeToFit() {
        let scale = CanvasBackingScale.contentScale(screenScale: 2, zoomScale: 1.5, fitScale: 0.75)
        #expect(abs(scale - 4) < 0.01)

        let capped = CanvasBackingScale.contentScale(screenScale: 3, zoomScale: 4, fitScale: 1, maxScale: 6)
        #expect(abs(capped - 6) < 0.01)

        let fallback = CanvasBackingScale.contentScale(screenScale: 2, zoomScale: 1, fitScale: 0)
        #expect(abs(fallback - 2) < 0.01)
    }
}

@MainActor
struct CircleSearchInkCaptureTests {
    static let pageSize = CGSize(width: 200, height: 200)

    private func makeBlankPage() throws -> PDFPage {
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: Self.pageSize))
        let data = renderer.pdfData { context in
            context.beginPage()
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: Self.pageSize))
        }
        let pdf = try #require(PDFDocument(data: data))
        return try #require(pdf.page(at: 0))
    }

    private func horizontalStrokeDrawing(in rect: CGRect) -> PKDrawing {
        let points = stride(from: rect.minX + 4, through: rect.maxX - 4, by: 4).map { x in
            PKStrokePoint(
                location: CGPoint(x: x, y: rect.midY),
                timeOffset: 0,
                size: CGSize(width: 6, height: 6),
                opacity: 1,
                force: 1,
                azimuth: 0,
                altitude: .pi / 2
            )
        }
        let path = PKStrokePath(controlPoints: points, creationDate: Date())
        let stroke = PKStroke(
            ink: PKInk(.pen, color: .black),
            path: path
        )
        return PKDrawing(strokes: [stroke])
    }

    @Test func renderImageCompositesInkPixels() throws {
        let page = try makeBlankPage()
        let pageRect = CGRect(x: 40, y: 60, width: 80, height: 40)
        let pageBounds = page.bounds(for: .cropBox)
        let drawingRect = InkCaptureGeometry.drawingRect(pageRect: pageRect, pageBounds: pageBounds)
        let drawing = horizontalStrokeDrawing(in: drawingRect)

        let plain = CircleSearchCapture.renderImage(of: pageRect, on: page, scale: 4)
        let withInk = CircleSearchCapture.renderImage(of: pageRect, on: page, scale: 4, drawing: drawing)

        #expect(withInk.size.width > 0)
        #expect(abs(withInk.size.width - pageRect.width) < 2)
        #expect(withInk.containsInkPixels(darkerThan: 0.85))
        #expect(!plain.containsInkPixels(darkerThan: 0.85))
    }

    @Test func noInkCaptureMatchesPDFOnlyContract() throws {
        let page = try makeBlankPage()
        let pageRect = CGRect(x: 20, y: 30, width: 60, height: 30)
        let capture = try #require(CircleSearchCapture.make(
            pageRect: pageRect, page: page, pageIndex: 0, documentID: UUID(), paperTitle: "T"
        ))
        #expect(capture.containsInk == false)
        #expect(capture.handwritingText.isEmpty)
        #expect(capture.selectedText.isEmpty)
        let longPixels = max(capture.image.size.width, capture.image.size.height) * capture.image.scale
        #expect(longPixels <= CaptureRenderScale.maxLongEdge + 1)
    }
}

private extension UIImage {
    /// True if any sampled pixel is darker than `threshold` (ink on white).
    func containsInkPixels(darkerThan threshold: CGFloat) -> Bool {
        guard let cgImage else { return false }
        let width = cgImage.width
        let height = cgImage.height
        guard width > 0, height > 0 else { return false }
        var data = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(
            data: &data,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return false }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        let step = max(1, min(width, height) / 32)
        for y in stride(from: 0, to: height, by: step) {
            for x in stride(from: 0, to: width, by: step) {
                let i = (y * width + x) * 4
                let r = CGFloat(data[i]) / 255
                let g = CGFloat(data[i + 1]) / 255
                let b = CGFloat(data[i + 2]) / 255
                if (r + g + b) / 3 < threshold { return true }
            }
        }
        return false
    }
}
