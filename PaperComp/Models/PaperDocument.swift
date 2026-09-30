import Foundation
import SwiftData

@Model
final class PaperDocument {
    @Attribute(.unique) var id: UUID
    var title: String
    /// File name inside `DocumentStore.papersDirectory`.
    var fileName: String
    var addedAt: Date
    var lastPageIndex: Int
    var isNotebook: Bool = false
    var coverColorRaw: String = NotePaperColor.rice.rawValue
    /// Codable `[PageRef]`. Empty means “not migrated yet”.
    var pagesData: Data = Data()

    init(
        id: UUID = UUID(),
        title: String,
        fileName: String,
        addedAt: Date = .now,
        lastPageIndex: Int = 0,
        pages: [PageRef] = [],
        isNotebook: Bool = false,
        coverColor: NotePaperColor = .rice
    ) {
        self.id = id
        self.title = title
        self.fileName = fileName
        self.addedAt = addedAt
        self.lastPageIndex = lastPageIndex
        self.isNotebook = isNotebook
        self.coverColorRaw = coverColor.rawValue
        self.pages = pages
    }

    var coverColor: NotePaperColor {
        NotePaperColor(rawValue: coverColorRaw) ?? .rice
    }

    var fileURL: URL { DocumentStore.papersDirectory.appending(path: fileName) }

    var pages: [PageRef] {
        get { (try? JSONDecoder().decode([PageRef].self, from: pagesData)) ?? [] }
        set { pagesData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }

    func pageID(at index: Int) -> UUID? {
        PageIdentity.pageID(in: pages, at: index)
    }
}
