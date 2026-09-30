import PencilKit
import SwiftData
import Testing
@testable import PaperComp

@MainActor
struct DrawingStoreTests {
    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: PaperDocument.self, PageDrawing.self, SearchRecord.self, configurations: config)
        return ModelContext(container)
    }

    private func sampleDrawing() -> PKDrawing {
        let points = (0..<10).map { (i: Int) -> PKStrokePoint in
            let t = CGFloat(i)
            return PKStrokePoint(location: CGPoint(x: 10 + t * 8, y: 20 + t * 3), timeOffset: TimeInterval(i) * 0.01,
                                 size: CGSize(width: 3, height: 3), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        }
        let path = PKStrokePath(controlPoints: points, creationDate: .now)
        return PKDrawing(strokes: [PKStroke(ink: PKInk(.pen, color: .red), path: path)])
    }

    @Test func drawingRoundTripsThroughSwiftData() throws {
        let context = try makeContext()
        let id = UUID()
        let pageID = UUID()
        let drawing = sampleDrawing()

        DrawingStore(context: context, documentID: id).save(drawing, for: pageID, pageIndex: 3)

        let reloaded = DrawingStore(context: context, documentID: id).drawing(for: pageID)
        let stored = try #require(try context.fetch(FetchDescriptor<PageDrawing>()).first)
        #expect(stored.pageID == pageID)
        #expect(stored.drawingData == drawing.dataRepresentation())
        let stroke = try #require(reloaded.strokes.first)
        #expect(reloaded.strokes.count == 1)
        #expect(stroke.ink.inkType == .pen)
        #expect(stroke.path.count == drawing.strokes[0].path.count)
        #expect(abs(reloaded.bounds.width - drawing.bounds.width) < 0.5)
        #expect(DrawingStore(context: context, documentID: id).drawing(for: UUID()).strokes.isEmpty)
        #expect(DrawingStore(context: context, documentID: UUID()).drawing(for: pageID).strokes.isEmpty)
    }

    @Test func savingAgainUpdatesSingleRecord() throws {
        let context = try makeContext()
        let id = UUID()
        let pageID = UUID()
        let store = DrawingStore(context: context, documentID: id)
        store.save(sampleDrawing(), for: pageID)
        store.save(PKDrawing(), for: pageID)

        let records = try context.fetch(FetchDescriptor<PageDrawing>())
        #expect(records.count == 1)
        #expect(store.drawing(for: pageID).strokes.isEmpty)
    }

    @Test func emptyDrawingIsNotInserted() throws {
        let context = try makeContext()
        DrawingStore(context: context, documentID: UUID()).save(PKDrawing(), for: UUID())
        #expect(try context.fetchCount(FetchDescriptor<PageDrawing>()) == 0)
    }

    @Test func debouncedSaveLands() async throws {
        let context = try makeContext()
        let id = UUID()
        let pageID = UUID()
        let store = DrawingStore(context: context, documentID: id, delay: .milliseconds(20))
        store.scheduleSave(sampleDrawing(), for: pageID)
        #expect(try context.fetchCount(FetchDescriptor<PageDrawing>()) == 0)
        try await Task.sleep(for: .milliseconds(200))
        #expect(store.drawing(for: pageID).strokes.count == 1)
    }

    @Test func searchRecordStoresRectAsDoubles() {
        let rect = CGRect(x: 12.5, y: 40, width: 100, height: 33.25)
        let record = SearchRecord(documentID: UUID(), pageIndex: 2, pageRect: rect, question: "Explain")
        #expect(record.rectX == 12.5 && record.rectHeight == 33.25)
        #expect(record.pageRect == rect)
    }
}
