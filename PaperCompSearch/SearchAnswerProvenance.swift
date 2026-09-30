import Foundation

/// A passage from this PDF that was given to the model.
struct PaperPassage: Codable, Equatable, Sendable, Identifiable, Hashable {
    var pageIndex: Int
    var text: String
    var id: String { "\(pageIndex)-\(text.prefix(40))" }
}

/// Sources and paper passages saved with an answer. Old records are a bare `[WebSource]` array.
struct SearchAnswerProvenance: Codable, Equatable, Sendable {
    var sources: [WebSource]
    var passages: [PaperPassage]

    var isEmpty: Bool { sources.isEmpty && passages.isEmpty }

    func encodeJSON() -> String {
        (try? JSONEncoder().encode(self)).flatMap { String(data: $0, encoding: .utf8) } ?? "{\"sources\":[],\"passages\":[]}"
    }

    static func decode(from json: String) -> SearchAnswerProvenance {
        let data = Data(json.utf8)
        if let envelope = try? JSONDecoder().decode(SearchAnswerProvenance.self, from: data) {
            return envelope
        }
        let sources = (try? JSONDecoder().decode([WebSource].self, from: data)) ?? []
        return SearchAnswerProvenance(sources: sources, passages: [])
    }
}

extension PaperChunk {
    var asPassage: PaperPassage { PaperPassage(pageIndex: pageIndex, text: text) }
}
