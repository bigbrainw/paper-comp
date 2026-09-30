import Foundation
import PDFKit
import SwiftData
import UIKit

/// Copies PDFs into the app sandbox and keeps the library in sync with the files.
@MainActor
enum DocumentStore {
    nonisolated static var documentsDirectory: URL { URL.documentsDirectory }

    #if DEBUG
    /// `-PCScratchLibrary`: in-memory SwiftData + papers in tmp, so UI tests start from an empty library
    /// without touching the simulator's real library.
    nonisolated static var usesScratchLibrary: Bool {
        ProcessInfo.processInfo.arguments.contains("-PCScratchLibrary")
    }
    #endif

    nonisolated static var papersDirectory: URL {
        var root = documentsDirectory
        #if DEBUG
        if usesScratchLibrary { root = FileManager.default.temporaryDirectory.appending(path: "ScratchLibrary") }
        #endif
        let url = root.appending(path: "Papers", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    enum ImportError: LocalizedError {
        case unreadable(String)
        var errorDescription: String? {
            switch self {
            case .unreadable(let name): "“\(name)” is not a readable PDF."
            }
        }
    }

    /// Copies (or moves) a PDF into `Papers/` and inserts a `PaperDocument`.
    @discardableResult
    static func importPDF(
        from source: URL,
        into context: ModelContext,
        move: Bool = false,
        id: UUID = UUID(),
        title: String? = nil
    ) throws -> PaperDocument {
        let accessing = source.startAccessingSecurityScopedResource()
        defer { if accessing { source.stopAccessingSecurityScopedResource() } }

        let fileName = "\(id.uuidString).pdf"
        let destination = papersDirectory.appending(path: fileName)
        try? FileManager.default.removeItem(at: destination)
        if move {
            try FileManager.default.moveItem(at: source, to: destination)
        } else {
            try FileManager.default.copyItem(at: source, to: destination)
        }

        guard let pdf = PDFDocument(url: destination) else {
            try? FileManager.default.removeItem(at: destination)
            throw ImportError.unreadable(source.lastPathComponent)
        }

        let fallback = source.deletingPathExtension().lastPathComponent
        let document = PaperDocument(
            id: id,
            title: title ?? PaperTitle.title(of: pdf, fallback: fallback),
            fileName: fileName,
            pages: PageIdentity.makeOriginalPages(count: pdf.pageCount),
            isNotebook: false
        )
        context.insert(document)
        try context.save()
        return document
    }

    /// Copies the bundled sample paper into the library through the normal import path.
    /// Returns the existing copy if it is already there, so it never duplicates.
    @discardableResult
    static func importSamplePaper(into context: ModelContext, bundle: Bundle = .main) throws -> PaperDocument {
        let id = SamplePaper.documentID
        if let existing = try? context.fetch(FetchDescriptor<PaperDocument>(predicate: #Predicate { $0.id == id })).first {
            return existing
        }
        guard let source = SamplePaper.bundledURL(in: bundle) else {
            throw ImportError.unreadable(SamplePaper.resourceName)
        }
        return try importPDF(from: source, into: context, id: id, title: SamplePaper.title)
    }

    #if DEBUG
    /// Inserts a one-page PDF when the library is empty so UI tests can open the reader.
    @discardableResult
    static func seedSamplePaperIfNeeded(into context: ModelContext) -> PaperDocument? {
        let count = (try? context.fetchCount(FetchDescriptor<PaperDocument>())) ?? 0
        guard count == 0 else { return nil }
        let bounds = CGRect(x: 0, y: 0, width: 612, height: 792)
        let data = UIGraphicsPDFRenderer(bounds: bounds).pdfData { renderer in
            renderer.beginPage()
            ("PaperComp sample" as NSString).draw(
                at: CGPoint(x: 72, y: 72),
                withAttributes: [.font: UIFont.systemFont(ofSize: 24)]
            )
        }
        let url = FileManager.default.temporaryDirectory.appending(path: "PC-Sample.pdf")
        do {
            try data.write(to: url)
            return try importPDF(from: url, into: context)
        } catch {
            return nil
        }
    }
    #endif

    @discardableResult
    static func createNotebook(
        title: String,
        template: NoteTemplate,
        color: NotePaperColor,
        size: NotePageSize,
        cover: NotePaperColor,
        into context: ModelContext
    ) -> PaperDocument {
        let id = UUID()
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let document = PaperDocument(
            id: id,
            title: trimmed.isEmpty ? "Untitled Notebook" : trimmed,
            fileName: "\(id.uuidString).notebook",
            pages: [PageRef(kind: .note(template: template, size: size, color: color))],
            isNotebook: true,
            coverColor: cover
        )
        context.insert(document)
        try? context.save()
        return document
    }

    /// Imports PDFs dropped into the Documents root (Finder/Files sharing) or the Inbox.
    @discardableResult
    static func importLooseFiles(into context: ModelContext) -> [PaperDocument] {
        let fm = FileManager.default
        let folders = [documentsDirectory, documentsDirectory.appending(path: "Inbox")]
        let urls = folders.flatMap { (try? fm.contentsOfDirectory(at: $0, includingPropertiesForKeys: nil)) ?? [] }
        return urls
            .filter { $0.pathExtension.lowercased() == "pdf" }
            .compactMap { try? importPDF(from: $0, into: context, move: true) }
    }

    static func delete(_ document: PaperDocument, from context: ModelContext) {
        let id = document.id
        try? FileManager.default.removeItem(at: document.fileURL)
        try? FileManager.default.removeItem(at: PaperIndexRecord.fileURL(for: id))
        try? context.delete(model: PageDrawing.self, where: #Predicate { $0.documentID == id })
        try? context.delete(model: SearchRecord.self, where: #Predicate { $0.documentID == id })
        context.delete(document)
        try? context.save()
        ThumbnailCache.shared.remove(id)
    }
}
