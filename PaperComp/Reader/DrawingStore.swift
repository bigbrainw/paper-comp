import Foundation
import PencilKit
import SwiftData

/// Loads and saves per-page drawings for one document, keyed by stable `pageID`.
@MainActor
final class DrawingStore {
    private let context: ModelContext
    private let documentID: UUID
    private var pending: [UUID: Task<Void, Never>] = [:]
    private let delay: Duration

    init(context: ModelContext, documentID: UUID, delay: Duration = .milliseconds(600)) {
        self.context = context
        self.documentID = documentID
        self.delay = delay
    }

    func drawing(for pageID: UUID) -> PKDrawing {
        guard let data = record(for: pageID)?.drawingData else { return PKDrawing() }
        return (try? PKDrawing(data: data)) ?? PKDrawing()
    }

    func scheduleSave(_ drawing: PKDrawing, for pageID: UUID, pageIndex: Int? = nil) {
        pending[pageID]?.cancel()
        pending[pageID] = Task { [delay] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self.save(drawing, for: pageID, pageIndex: pageIndex)
        }
    }

    func save(_ drawing: PKDrawing, for pageID: UUID, pageIndex: Int? = nil) {
        pending[pageID]?.cancel()
        pending[pageID] = nil
        let data = drawing.dataRepresentation()
        if let existing = record(for: pageID) {
            guard existing.drawingData != data else { return }
            existing.drawingData = data
            if let pageIndex { existing.pageIndex = pageIndex }
        } else {
            guard !drawing.strokes.isEmpty else { return }
            context.insert(PageDrawing(
                documentID: documentID,
                pageID: pageID,
                pageIndex: pageIndex ?? 0,
                drawingData: data
            ))
        }
        try? context.save()
    }

    private func record(for pageID: UUID) -> PageDrawing? {
        let id = documentID
        let descriptor = FetchDescriptor<PageDrawing>(
            predicate: #Predicate { $0.documentID == id }
        )
        return (try? context.fetch(descriptor))?.first { $0.pageID == pageID }
    }
}
