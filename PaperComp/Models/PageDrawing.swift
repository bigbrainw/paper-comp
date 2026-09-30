import Foundation
import SwiftData

@Model
final class PageDrawing {
    var documentID: UUID
    /// Stable page identity. Nil until `PageIdentity.migrate` runs.
    var pageID: UUID?
    /// Legacy composed index; used only to migrate onto `pageID`.
    var pageIndex: Int
    /// `PKDrawing.dataRepresentation()`.
    var drawingData: Data

    init(documentID: UUID, pageID: UUID? = nil, pageIndex: Int = 0, drawingData: Data) {
        self.documentID = documentID
        self.pageID = pageID
        self.pageIndex = pageIndex
        self.drawingData = drawingData
    }
}
