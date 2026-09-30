import CoreGraphics
import Foundation

/// A circled region on a page that has one or more saved answers.
struct SearchMarker: Equatable {
    let pageID: UUID
    let pageIndex: Int
    /// PDF page coordinates, matching `SearchRecord.pageRect`.
    let pageRect: CGRect

    init(pageID: UUID, pageIndex: Int, pageRect: CGRect) {
        self.pageID = pageID
        self.pageIndex = pageIndex
        self.pageRect = pageRect
    }

    init(_ record: SearchRecord) {
        self.init(pageID: record.pageID ?? UUID(), pageIndex: record.pageIndex, pageRect: record.pageRect)
    }

    func matches(_ record: SearchRecord) -> Bool {
        let samePage = record.pageID == pageID || (record.pageID == nil && record.pageIndex == pageIndex)
        return samePage && record.pageRect == pageRect
    }
}
