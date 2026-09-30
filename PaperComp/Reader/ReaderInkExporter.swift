import Foundation
import PencilKit

/// Bridge from `PDFKitView`'s live overlay canvases to Reader share/export.
@MainActor
final class ReaderInkExporter {
    weak var provider: PageOverlayProvider?

    /// Synchronously snapshots every visible canvas, persists those drawings, and returns the live map.
    func flushAndSnapshotVisible() -> [UUID: PKDrawing] {
        guard let provider else { return [:] }
        let live = provider.liveDrawingsByPageID()
        provider.saveAll()
        return live
    }
}
