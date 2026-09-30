import PDFKit
import PencilKit
import UIKit

/// Builds a shareable PDF: composed page order with ink flattened. Never writes the original file.
enum AnnotatedPDF {
    /// Live visible snapshots override persisted drawings for the same `pageID`.
    static func mergedDrawings(
        persisted: [UUID: PKDrawing],
        live: [UUID: PKDrawing]
    ) -> [UUID: PKDrawing] {
        var map = persisted
        for (pageID, drawing) in live {
            map[pageID] = drawing
        }
        return map
    }

    static func make(
        pages: [PageRef],
        original: PDFDocument?,
        drawings: [UUID: PKDrawing]
    ) -> Data? {
        let composed = PageIdentity.compose(pages: pages, original: original)
        guard composed.pageCount > 0 else { return nil }
        let renderScale: CGFloat = 2
        var images: [(bounds: CGRect, image: UIImage)] = []
        images.reserveCapacity(composed.pageCount)
        for index in 0..<composed.pageCount {
            guard let page = composed.page(at: index) else { continue }
            let bounds = page.bounds(for: .mediaBox)
            let drawing: PKDrawing? = {
                guard let pageID = PageIdentity.pageID(in: pages, at: index) else { return nil }
                return drawings[pageID]
            }()
            images.append((
                bounds,
                flattenedPageImage(page: page, bounds: bounds, drawing: drawing, scale: renderScale)
            ))
        }
        guard let first = images.first else { return nil }

        let data = NSMutableData()
        var mediaBox = first.bounds
        guard let consumer = CGDataConsumer(data: data),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil)
        else { return nil }

        for item in images {
            var box = item.bounds
            context.beginPage(mediaBox: &box)
            UIGraphicsPushContext(context)
            context.translateBy(x: 0, y: box.height)
            context.scaleBy(x: 1, y: -1)
            item.image.draw(in: CGRect(origin: .zero, size: box.size))
            UIGraphicsPopContext()
            context.endPage()
        }
        context.closePDF()
        return data as Data
    }

    /// Composite PDF page thumbnail + ink into one opaque UIKit image (top-left origin).
    static func flattenedPageImage(
        page: PDFPage,
        bounds: CGRect,
        drawing: PKDrawing?,
        scale: CGFloat = 2
    ) -> UIImage {
        let size = CGSize(width: bounds.width, height: bounds.height)
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            let thumbSize = CGSize(width: bounds.width * scale, height: bounds.height * scale)
            page.thumbnail(of: thumbSize, for: .mediaBox).draw(in: CGRect(origin: .zero, size: size))
            guard let drawing, !drawing.strokes.isEmpty else { return }
            var ink = UIImage()
            UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
                ink = drawing.image(from: bounds, scale: scale)
            }
            ink.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
