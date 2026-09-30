import PDFKit
import PencilKit
import UIKit

/// Turns a lasso path or box rect in PDF page space into a `CircleCapture`.
@MainActor
enum CircleSearchCapture {
    static let contextLength = 1_500

    static func make(
        path: CGPath,
        page: PDFPage,
        pageIndex: Int,
        documentID: UUID,
        paperTitle: String,
        drawing: PKDrawing = PKDrawing(),
        canvas: PageCanvasView? = nil,
        pdfView: PDFView? = nil
    ) -> CircleCapture? {
        let raw = path.boundingBoxOfPath.intersection(page.bounds(for: .cropBox))
        guard !raw.isNull, raw.width > 2, raw.height > 2 else { return nil }
        let rect = snapRect(raw, on: page)
        let text = selectedText(in: path, on: page, snappedRect: rect)
        return capture(
            rect: rect, text: text, page: page, pageIndex: pageIndex,
            documentID: documentID, paperTitle: paperTitle,
            drawing: drawing, canvas: canvas, pdfView: pdfView
        )
    }

    static func make(
        pageRect: CGRect,
        page: PDFPage,
        pageIndex: Int,
        documentID: UUID,
        paperTitle: String,
        drawing: PKDrawing = PKDrawing(),
        canvas: PageCanvasView? = nil,
        pdfView: PDFView? = nil
    ) -> CircleCapture? {
        let raw = pageRect.intersection(page.bounds(for: .cropBox))
        guard !raw.isNull, raw.width > 2, raw.height > 2 else { return nil }
        let rect = snapRect(raw, on: page)
        let text = selectedText(in: rect, on: page)
        return capture(
            rect: rect, text: text, page: page, pageIndex: pageIndex,
            documentID: documentID, paperTitle: paperTitle,
            drawing: drawing, canvas: canvas, pdfView: pdfView
        )
    }

    static func makeFromTap(
        at point: CGPoint,
        page: PDFPage,
        pageIndex: Int,
        documentID: UUID,
        paperTitle: String,
        drawing: PKDrawing = PKDrawing(),
        canvas: PageCanvasView? = nil,
        pdfView: PDFView? = nil
    ) -> CircleCapture? {
        guard let word = page.selectionForWord(at: point), let wordString = word.string, !wordString.isEmpty else {
            return nil
        }
        var rect = word.bounds(for: page)
        if let sentence = sentenceSelection(around: word, on: page) {
            rect = rect.union(sentence.bounds(for: page))
        }
        let text = sentenceSelection(around: word, on: page)?.string?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? wordString.trimmingCharacters(in: .whitespacesAndNewlines)
        return capture(
            rect: rect, text: text, page: page, pageIndex: pageIndex,
            documentID: documentID, paperTitle: paperTitle,
            drawing: drawing, canvas: canvas, pdfView: pdfView
        )
    }

    /// Snaps box edges within `threshold` points of PDF line bounds.
    static func snapRect(_ rect: CGRect, on page: PDFPage, threshold: CGFloat = SearchSelectionSettings.snapThreshold) -> CGRect {
        guard let pageText = page.selection(for: page.bounds(for: .cropBox)) else { return rect }
        let lineBounds = pageText.selectionsByLine().map { $0.bounds(for: page) }
        guard !lineBounds.isEmpty else { return rect }

        var r = rect.standardized
        if let x = nearestValue(to: r.minX, in: lineBounds.map(\.minX), threshold: threshold) { r.origin.x = x }
        if let x = nearestValue(to: r.maxX, in: lineBounds.map(\.maxX), threshold: threshold) { r.size.width = x - r.minX }
        if let y = nearestValue(to: r.minY, in: lineBounds.map(\.minY), threshold: threshold) { r.origin.y = y }
        if let y = nearestValue(to: r.maxY, in: lineBounds.map(\.maxY), threshold: threshold) { r.size.height = y - r.minY }
        return r.standardized
    }

    private static func nearestValue(to target: CGFloat, in values: [CGFloat], threshold: CGFloat) -> CGFloat? {
        values
            .filter { abs($0 - target) <= threshold }
            .min(by: { abs($0 - target) < abs($1 - target) })
    }

    private static func capture(
        rect: CGRect,
        text: String,
        page: PDFPage,
        pageIndex: Int,
        documentID: UUID,
        paperTitle: String,
        drawing: PKDrawing,
        canvas: PageCanvasView?,
        pdfView: PDFView?
    ) -> CircleCapture {
        let ink = canvas?.drawing ?? drawing
        let containsInk = !ink.strokes.isEmpty
        let scale = CaptureRenderScale.scale(for: rect)
        let image = renderImage(
            of: rect, on: page, scale: scale, drawing: ink, canvas: canvas, pdfView: pdfView
        )
        return CircleCapture(
            documentID: documentID,
            paperTitle: paperTitle,
            pageIndex: pageIndex,
            pageRect: rect,
            selectedText: text,
            handwritingText: "",
            containsInk: containsInk,
            image: image,
            surroundingText: surroundingText(on: page, around: text)
        )
    }

    private static func sentenceSelection(around word: PDFSelection, on page: PDFPage) -> PDFSelection? {
        guard let line = word.copy() as? PDFSelection else { return nil }
        line.extend(atStart: 1)
        line.extend(atEnd: 1)
        return line
    }

    static func selectedText(in rect: CGRect, on page: PDFPage) -> String {
        guard let selection = page.selection(for: rect) else { return "" }
        return lineStrings(from: selection, on: page, intersecting: rect).joined(separator: "\n")
    }

    /// Lines of the bbox selection whose bounds touch the lasso; the whole snapped rect if none do.
    static func selectedText(in path: CGPath, on page: PDFPage, snappedRect: CGRect? = nil) -> String {
        let box = snappedRect ?? path.boundingBoxOfPath
        guard let selection = page.selection(for: box) else { return "" }
        let region = closed(path)
        let lines = lineStrings(from: selection, on: page) { lineRect in
            region.intersects(CGPath(rect: lineRect, transform: nil))
        }
        if !lines.isEmpty { return lines.joined(separator: "\n") }
        return selectedText(in: box, on: page)
    }

    private static func lineStrings(
        from selection: PDFSelection,
        on page: PDFPage,
        intersecting: CGRect? = nil
    ) -> [String] {
        selection.selectionsByLine()
            .filter { line in
                guard let intersecting else { return true }
                return intersecting.intersects(line.bounds(for: page))
            }
            .compactMap { $0.string?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func lineStrings(
        from selection: PDFSelection,
        on page: PDFPage,
        intersects path: (CGRect) -> Bool
    ) -> [String] {
        selection.selectionsByLine()
            .filter { path($0.bounds(for: page)) }
            .compactMap { $0.string?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// About `limit` characters of page text centered on the selection (or the page start).
    static func surroundingText(on page: PDFPage, around text: String, limit: Int = contextLength) -> String {
        guard let pageText = page.string, !pageText.isEmpty else { return "" }
        let ns = pageText as NSString
        guard ns.length > limit else { return pageText }
        let anchor = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        let found = anchor.isEmpty ? NSRange(location: NSNotFound, length: 0) : ns.range(of: anchor)
        let center = found.location == NSNotFound ? 0 : found.location + found.length / 2
        let start = max(0, min(center - limit / 2, ns.length - limit))
        return ns.substring(with: NSRange(location: start, length: limit))
    }

    /// Maps a page-space rect (origin bottom-left, same space as `bounds(for:)`)
    /// onto a rendered cropBox image whose origin is top-left, in **points**.
    static func renderCropRect(pageRect: CGRect, cropBox: CGRect, renderSize: CGSize) -> CGRect {
        guard cropBox.width > 0, cropBox.height > 0, renderSize.width > 0, renderSize.height > 0 else {
            return .zero
        }
        let sx = renderSize.width / cropBox.width
        let sy = renderSize.height / cropBox.height
        let width = pageRect.width * sx
        let height = pageRect.height * sy
        let x = (pageRect.minX - cropBox.minX) * sx
        let yFromBottom = (pageRect.minY - cropBox.minY) * sy
        let y = renderSize.height - yFromBottom - height
        return CGRect(x: x, y: y, width: width, height: height)
    }

    /// Renders `rect` (page space) at `scale` on a white background, optionally compositing ink.
    /// Ink crop excludes lasso chrome and markers (`PKDrawing.image` only). Source PDF is never modified.
    static func renderImage(
        of rect: CGRect,
        on page: PDFPage,
        scale: CGFloat = 2,
        drawing: PKDrawing = PKDrawing(),
        canvas: PageCanvasView? = nil,
        pdfView: PDFView? = nil
    ) -> UIImage {
        let box = page.bounds(for: .cropBox)
        let clipped = rect.intersection(box)
        guard !clipped.isNull, clipped.width > 1, clipped.height > 1, box.width > 1, box.height > 1 else {
            return UIImage()
        }
        let pageSize = CGSize(width: box.width * scale, height: box.height * scale)
        let full = page.thumbnail(of: pageSize, for: .cropBox)
        let crop = renderCropRect(pageRect: clipped, cropBox: box, renderSize: full.size)
            .integral
            .applying(CGAffineTransform(scaleX: full.scale, y: full.scale))
        let bounds = CGRect(origin: .zero, size: CGSize(width: full.size.width * full.scale, height: full.size.height * full.scale))
        let pixel = crop.intersection(bounds).integral
        guard pixel.width > 1, pixel.height > 1, let cgImage = full.cgImage?.cropping(to: pixel) else {
            return full
        }
        let pdfCrop = UIImage(cgImage: cgImage, scale: scale, orientation: .up)
        guard !drawing.strokes.isEmpty else { return pdfCrop }

        let inkRect: CGRect
        if let canvas, let pdfView {
            inkRect = InkCaptureGeometry.canvasRect(
                pageRect: clipped, page: page, pdfView: pdfView, canvas: canvas
            ).intersection(canvas.bounds)
        } else {
            let pageBounds = canvas?.pageBounds ?? box
            inkRect = InkCaptureGeometry.drawingRect(pageRect: clipped, pageBounds: pageBounds)
        }
        guard inkRect.width > 1, inkRect.height > 1 else { return pdfCrop }

        let style = canvas?.overrideUserInterfaceStyle ?? .light
        let ink = renderInk(drawing: drawing, from: inkRect, scale: scale, userInterfaceStyle: style)
        return composite(pdfCrop, ink: ink)
    }

    /// Renders a PKDrawing crop under stable interface traits so white-page ink cannot invert.
    static func renderInk(
        drawing: PKDrawing,
        from rect: CGRect,
        scale: CGFloat,
        userInterfaceStyle: UIUserInterfaceStyle
    ) -> UIImage {
        guard rect.width > 0, rect.height > 0, !drawing.strokes.isEmpty else { return UIImage() }
        let style: UIUserInterfaceStyle = userInterfaceStyle == .unspecified ? .light : userInterfaceStyle
        var image = UIImage()
        UITraitCollection(userInterfaceStyle: style).performAsCurrent {
            image = drawing.image(from: rect, scale: scale)
        }
        return image
    }

    static func composite(_ base: UIImage, ink: UIImage) -> UIImage {
        let size = base.size
        guard size.width > 0, size.height > 0 else { return base }
        let format = UIGraphicsImageRendererFormat()
        format.scale = base.scale
        format.opaque = false
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            base.draw(in: CGRect(origin: .zero, size: size))
            ink.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    private static func closed(_ path: CGPath) -> CGPath {
        let copy = CGMutablePath()
        copy.addPath(path)
        copy.closeSubpath()
        return copy
    }
}
