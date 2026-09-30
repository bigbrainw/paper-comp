import Foundation

actor PaperIndex {
    static let shared = PaperIndex()

    func build(documentID: UUID, title: String, pages: [String]) -> PaperIndexRecord {
        let structure = PaperStructureDetector.detect(titleHint: title, pages: pages)
        let chunks = PaperChunker.chunk(pages: pages)
        let references = ReferenceParser.parse(pages: pages)
        let brief = PaperText.extractiveBrief(abstract: structure.abstract, introduction: structure.introduction)
        return PaperIndexRecord(
            documentID: documentID,
            title: structure.title,
            abstract: structure.abstract,
            introduction: structure.introduction,
            headings: structure.headings,
            chunks: chunks,
            references: references,
            brief: brief.isEmpty ? nil : brief,
            builtAt: Date()
        )
    }

    func load(documentID: UUID) -> PaperIndexRecord? {
        let url = PaperIndexRecord.fileURL(for: documentID)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(PaperIndexRecord.self, from: data)
    }

    func save(_ record: PaperIndexRecord) {
        let url = PaperIndexRecord.fileURL(for: record.documentID)
        guard let data = try? JSONEncoder().encode(record) else { return }
        try? data.write(to: url, options: .atomic)
    }

    func delete(documentID: UUID) {
        try? FileManager.default.removeItem(at: PaperIndexRecord.fileURL(for: documentID))
    }

    func search(_ record: PaperIndexRecord, query: String, limit: Int = 3) -> [PaperChunk] {
        BM25Index(chunks: record.chunks).ranked(query: query, limit: limit)
    }
}

enum PaperIndexQuery {
    static func passages(in record: PaperIndexRecord, selection: String, question: String) -> [PaperChunk] {
        let query = [selection, question].filter { !$0.isEmpty }.joined(separator: " ")
        return BM25Index(chunks: record.chunks).ranked(query: query, limit: 3)
    }

    static func citedReferences(in record: PaperIndexRecord, selection: String) -> [PaperReference] {
        ReferenceParser.matching(selection: selection, in: record.references)
    }

    static func citedPaperQuery(selection: String, record: PaperIndexRecord?) -> String {
        if let record {
            let refs = citedReferences(in: record, selection: selection)
            if let title = refs.first?.title, title.count > 6 { return title }
        }
        return CitationQueryExtractor.query(from: selection)
    }
}
