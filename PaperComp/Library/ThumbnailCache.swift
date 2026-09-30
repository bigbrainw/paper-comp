import PDFKit
import UIKit

@MainActor
final class ThumbnailCache {
    static let shared = ThumbnailCache()
    private let cache = NSCache<NSUUID, UIImage>()

    func thumbnail(for document: PaperDocument, size: CGSize) async -> UIImage? {
        let key = document.id as NSUUID
        if let cached = cache.object(forKey: key) { return cached }
        let url = document.fileURL
        let pages = document.pages
        let isNotebook = document.isNotebook
        let cover = document.coverColor
        let image = await Task.detached(priority: .utility) {
            if isNotebook {
                if let first = pages.first, case .note(let template, let sizeKind, let color) = first.kind,
                   let page = NotePageRenderer.makePage(template: template, size: sizeKind, color: color) {
                    return Optional(page.thumbnail(of: size, for: .cropBox))
                }
                return Optional(Self.swatch(cover, size: size))
            }
            return PDFDocument(url: url)?.page(at: 0)?.thumbnail(of: size, for: .cropBox)
        }.value
        if let image { cache.setObject(image, forKey: key) }
        return image
    }

    func remove(_ id: UUID) {
        cache.removeObject(forKey: id as NSUUID)
    }

    nonisolated private static func swatch(_ color: NotePaperColor, size: CGSize) -> UIImage {
        let ui = NotePageRenderer.paperColor(color)
        return UIGraphicsImageRenderer(size: size).image { ctx in
            ui.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
        }
    }
}
