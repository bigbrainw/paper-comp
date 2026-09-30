import CoreGraphics
import PDFKit
import UIKit

/// Pure coordinate helpers for cropping live PencilKit ink into a Circle Search capture.
/// Drawing / canvas geometry is never mutated — these only map rects.
enum InkCaptureGeometry {
    /// PDF page-space rect (origin bottom-left) → UIKit drawing space within `pageBounds` (origin top-left).
    static func drawingRect(pageRect: CGRect, pageBounds: CGRect) -> CGRect {
        guard pageBounds.width > 0, pageBounds.height > 0 else { return .zero }
        return CGRect(
            x: pageRect.minX - pageBounds.minX,
            y: pageBounds.maxY - pageRect.maxY,
            width: pageRect.width,
            height: pageRect.height
        )
    }

    /// PDF page-space rect → live overlay canvas coordinates via PDFView + UIView conversion.
    /// Handles y-axis, crop offsets, rotation, and zoom without changing stored drawing coordinates.
    @MainActor
    static func canvasRect(
        pageRect: CGRect,
        page: PDFPage,
        pdfView: PDFView,
        canvas: UIView
    ) -> CGRect {
        let inPDFView = pdfView.convert(pageRect, from: page)
        return canvas.convert(inPDFView, from: pdfView).standardized
    }
}

/// Adaptive capture render scale: long edge capped near `maxLongEdge` pixels.
enum CaptureRenderScale {
    static let maxLongEdge: CGFloat = 2048

    /// Points → image scale so `max(width, height) * scale ≤ maxLongEdge`.
    static func scale(for pageRect: CGRect, maxLongEdge: CGFloat = maxLongEdge) -> CGFloat {
        let long = max(pageRect.width, pageRect.height)
        guard long > 0 else { return 2 }
        return max(1, maxLongEdge / long)
    }
}

/// Backing-store scale for live `PKCanvasView` crispness (frame/bounds unchanged).
enum CanvasBackingScale {
    static let maxContentScale: CGFloat = 6

    /// `screenScale * (zoom / fit)`, capped. Falls back to `screenScale` when fit is invalid.
    static func contentScale(
        screenScale: CGFloat,
        zoomScale: CGFloat,
        fitScale: CGFloat,
        maxScale: CGFloat = maxContentScale
    ) -> CGFloat {
        let screen = max(screenScale, 1)
        guard fitScale > 0, zoomScale > 0 else { return min(screen, maxScale) }
        let relative = zoomScale / fitScale
        return min(max(screen * relative, screen), maxScale)
    }
}
