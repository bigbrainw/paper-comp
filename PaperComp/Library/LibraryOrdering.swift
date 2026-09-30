import Foundation
import SwiftData

enum LibrarySort: String, CaseIterable, Identifiable {
    case recent, title

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

enum LibraryKindFilter: String, CaseIterable, Identifiable {
    case all, papers, notebooks
    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: "All"
        case .papers: "Papers"
        case .notebooks: "Notebooks"
        }
    }
}

enum LibraryOrdering {
    static func apply(
        _ documents: [PaperDocument],
        sort: LibrarySort,
        notesOnly: Bool,
        withNotes: Set<UUID>,
        kind: LibraryKindFilter = .all
    ) -> [PaperDocument] {
        var filtered = documents
        switch kind {
        case .all: break
        case .papers: filtered = filtered.filter { !$0.isNotebook }
        case .notebooks: filtered = filtered.filter(\.isNotebook)
        }
        if notesOnly { filtered = filtered.filter { withNotes.contains($0.id) } }
        switch sort {
        case .recent:
            return filtered.sorted { $0.addedAt > $1.addedAt }
        case .title:
            return filtered.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        }
    }

    /// IDs of papers with any ink or any saved search answer.
    @MainActor
    static func documentIDsWithNotes(in context: ModelContext) -> Set<UUID> {
        var drawings = FetchDescriptor<PageDrawing>()
        drawings.propertiesToFetch = [\.documentID]
        var records = FetchDescriptor<SearchRecord>()
        records.propertiesToFetch = [\.documentID]
        let inked = ((try? context.fetch(drawings)) ?? []).map(\.documentID)
        let searched = ((try? context.fetch(records)) ?? []).map(\.documentID)
        return Set(inked + searched)
    }
}
