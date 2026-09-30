import Foundation
import Observation
import PDFKit

enum PaperIndexControllerCache {
    @MainActor
    static weak var active: PaperIndexController?

    @MainActor
    static func record(for documentID: UUID) -> PaperIndexRecord? {
        guard let active, active.record?.documentID == documentID else { return nil }
        return active.record
    }
}

@Observable @MainActor
final class PaperIndexController {
    var isIndexing = false
    var record: PaperIndexRecord?

    func start(documentID: UUID, title: String, pdf: PDFDocument) async {
        PaperIndexControllerCache.active = self
        if let cached = await PaperIndex.shared.load(documentID: documentID) {
            record = cached
            isIndexing = false
            if cached.brief == nil { await generateBrief(for: documentID) }
            return
        }
        isIndexing = true
        let pages = (0..<pdf.pageCount).map { pdf.page(at: $0)?.string ?? "" }
        let built = await PaperIndex.shared.build(documentID: documentID, title: title, pages: pages)
        await PaperIndex.shared.save(built)
        record = built
        isIndexing = false
        await generateBrief(for: documentID)
    }

    private func generateBrief(for documentID: UUID) async {
        guard ModelManager.shared.activeModelURL != nil else { return }
        guard var current = record, current.documentID == documentID else { return }
        let abstract = current.abstract
        let intro = String(current.introduction.prefix(800))
        guard !abstract.isEmpty || !intro.isEmpty else { return }
        do {
            try await LlamaRunner.shared.load(
                modelURL: ModelManager.shared.activeModelURL!,
                nCtx: ModelManager.shared.activeEntry?.nCtx ?? 4096,
                projectorURL: ModelManager.shared.activeProjectorURL,
                promptFormat: ModelManager.shared.activeEntry?.promptFormat
            )
            var text = ""
            for try await piece in await LlamaRunner.shared.generateChat(
                system: "Write exactly five sentences summarizing this paper. No preamble or heading.",
                user: "Title: \(current.title)\n\nAbstract:\n\(abstract)\n\nIntroduction:\n\(intro)",
                sampler: .brief
            ) {
                if case .text(let token) = piece { text += token }
            }
            let brief = ThinkingStrip.strip(text, usesThinking: ModelManager.shared.activeEntry?.usesThinking ?? false)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !brief.isEmpty else { return }
            current.brief = brief
            record = current
            await PaperIndex.shared.save(current)
        } catch {
            return
        }
    }
}
