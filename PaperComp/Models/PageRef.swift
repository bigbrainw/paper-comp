import Foundation

/// One slot in a document's composed page list. The original PDF file is never rewritten.
struct PageRef: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var kind: PageKind

    init(id: UUID = UUID(), kind: PageKind) {
        self.id = id
        self.kind = kind
    }
}

enum PageKind: Codable, Hashable, Sendable {
    case pdf(originalIndex: Int)
    case note(template: NoteTemplate, size: NotePageSize, color: NotePaperColor)
}

/// Picker order is declaration order. Existing rawValues stay stable for Codable.
enum NoteTemplate: String, Codable, CaseIterable, Sendable {
    case blank
    case linedCollege
    case linedNarrow
    case wideRuled
    case grid
    case graph
    case crossGrid
    case dotted
    case isometricDot
    case hexagon
    case cornell
    case handwriting
    case musicStaff
    case checklist
}

enum NotePageSize: String, Codable, CaseIterable, Sendable {
    case a4
    case letter
    /// Match the neighbouring paper page when inserted into a PDF.
    case matching
}

enum NotePaperColor: String, Codable, CaseIterable, Sendable {
    case white
    case rice
    case dark
}
