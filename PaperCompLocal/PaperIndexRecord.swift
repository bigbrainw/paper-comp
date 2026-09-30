import Foundation

struct PaperIndexRecord: Codable, Equatable, Sendable {
    var documentID: UUID
    var title: String
    var abstract: String
    var introduction: String
    var headings: [String]
    var chunks: [PaperChunk]
    var references: [PaperReference]
    var brief: String?
    var builtAt: Date

    static func fileURL(for documentID: UUID) -> URL {
        DocumentStore.papersDirectory.appending(path: "\(documentID.uuidString).index.json")
    }
}
