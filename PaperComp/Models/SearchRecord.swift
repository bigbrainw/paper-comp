import CoreGraphics
import Foundation
import SwiftData

@Model
final class SearchRecord {
    @Attribute(.unique) var id: UUID
    var documentID: UUID
    /// Stable page identity. Nil until `PageIdentity.migrate` runs.
    var pageID: UUID?
    var pageIndex: Int
    var rectX: Double
    var rectY: Double
    var rectWidth: Double
    var rectHeight: Double
    var question: String
    var answer: String
    /// JSON-encoded array of sources, owned by the search feature.
    var sourcesJSON: String
    var createdAt: Date

    init(
        id: UUID = UUID(),
        documentID: UUID,
        pageIndex: Int,
        pageID: UUID? = nil,
        pageRect: CGRect,
        question: String,
        answer: String = "",
        sourcesJSON: String = "[]",
        createdAt: Date = .now
    ) {
        self.id = id
        self.documentID = documentID
        self.pageID = pageID
        self.pageIndex = pageIndex
        self.rectX = pageRect.origin.x
        self.rectY = pageRect.origin.y
        self.rectWidth = pageRect.width
        self.rectHeight = pageRect.height
        self.question = question
        self.answer = answer
        self.sourcesJSON = sourcesJSON
        self.createdAt = createdAt
    }

    /// A record for an answer about `capture`. `sources` is any Codable array, e.g. `[WebSource]`.
    convenience init(capture: CircleCapture, question: String, answer: String, sources: some Encodable, pageID: UUID? = nil) {
        let json = (try? JSONEncoder().encode(sources)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        self.init(documentID: capture.documentID, pageIndex: capture.pageIndex, pageID: pageID, pageRect: capture.pageRect,
                  question: question, answer: answer, sourcesJSON: json)
    }

    convenience init(capture: CircleCapture, question: String, answer: String, provenance: SearchAnswerProvenance, pageID: UUID? = nil) {
        self.init(documentID: capture.documentID, pageIndex: capture.pageIndex, pageID: pageID, pageRect: capture.pageRect,
                  question: question, answer: answer, sourcesJSON: provenance.encodeJSON())
    }

    func decodedSources<Source: Decodable>(as type: Source.Type = Source.self) -> [Source] {
        (try? JSONDecoder().decode([Source].self, from: Data(sourcesJSON.utf8))) ?? []
    }

    func decodedProvenance() -> SearchAnswerProvenance {
        SearchAnswerProvenance.decode(from: sourcesJSON)
    }

    /// Circled region in PDF page coordinates.
    var pageRect: CGRect {
        get { CGRect(x: rectX, y: rectY, width: rectWidth, height: rectHeight) }
        set {
            rectX = newValue.origin.x
            rectY = newValue.origin.y
            rectWidth = newValue.width
            rectHeight = newValue.height
        }
    }
}
