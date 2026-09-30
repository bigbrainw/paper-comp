import PDFKit
import PencilKit
import SwiftData
import SwiftUI
import UIKit

struct ReaderView: View {
    let document: PaperDocument

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var records: [SearchRecord]
    @State private var toolState = ToolState()
    @State private var pdf: PDFDocument?
    @State private var loadFailed = false
    @State private var searchCardSession = SearchCardSession()
    @State private var anchorConverter = PageAnchorConverter()
    @AppStorage(InputSettings.allowFingerDrawingKey) private var allowFingerDrawing = InputSettings.allowFingerDrawingDefault
    @AppStorage(ReaderSettings.showSearchMarkersKey) private var showSearchMarkers = ReaderSettings.showSearchMarkersDefault
    @AppStorage(ReaderSettings.eraserModeKey) private var eraserModeRaw = EraserMode.defaultValue.rawValue
    @AppStorage(ReaderSettings.toolbarPositionKey) private var toolbarPositionRaw = ToolbarPosition.defaultValue.rawValue
    @AppStorage(SearchSelectionSettings.storageKey) private var selectionShape = SearchSelectionSettings.box
    @State private var isFocused = false
    @State private var isShowingSettings = false
    @State private var isAddingPage = false
    @State private var isShowingPages = false
    @State private var isSharing = false
    @State private var shareURL: URL?
    @State private var inkExporter = ReaderInkExporter()
    @State private var changingPageIndex: Int?
    @State private var noteMenuIndex: Int?
    @State private var pendingDeleteIndex: Int?
    @State private var paperIndex = PaperIndexController()
    #if DEBUG
    @State private var searchCardStartMinimized = false
    #endif

    private var toolbarPosition: ToolbarPosition { ToolbarPosition(parsing: toolbarPositionRaw) }

    init(document: PaperDocument) {
        self.document = document
        let documentID = document.id
        _records = Query(filter: #Predicate<SearchRecord> { $0.documentID == documentID }, sort: \.createdAt)
    }

    var body: some View {
        ZStack {
            content
                .ignoresSafeArea()
            if !isFocused {
                floatingChrome
                    .transition(.opacity)
            }
            #if DEBUG
            if ScreenshotMode.answerScenario != nil, searchCardSession.capture != nil {
                ScreenshotSelectionBox(rect: searchCardSession.anchor)
                    .ignoresSafeArea()
                    .zIndex(1)
            }
            #endif
            if searchCardSession.isPresented {
                SearchCardLayer(session: searchCardSession)
                    .ignoresSafeArea()
                    .zIndex(2)
            }
        }
        .overlay(alignment: .top) {
            if isFocused {
                ReaderFocusNub { withAnimation(.toolbarSpring) { isFocused = false } }
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .background(Theme.rice)
        .animation(.toolbarSpring, value: isFocused)
        .animation(.toolbarSpring, value: toolbarPositionRaw)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $isShowingSettings) {
            SettingsView()
                .presentationDetents([.large])
                .presentationSizing(.page)
        }
        .sheet(isPresented: $isAddingPage, onDismiss: { changingPageIndex = nil }) {
            AddPageSheet(showSize: document.isNotebook) { template, color, position, size in
                if let changingPageIndex {
                    replaceNote(at: changingPageIndex, template: template, color: color, size: size)
                } else {
                    insertNote(template: template, color: color, position: position, size: size)
                }
                isAddingPage = false
            }
            .presentationDetents([.medium])
        }
        .sheet(isPresented: $isShowingPages) {
            if let pdf {
                PageOverviewView(
                    pages: document.pages,
                    composed: pdf,
                    drawings: drawingMap(),
                    currentIndex: document.lastPageIndex,
                    onSelect: { index in
                        document.lastPageIndex = index
                        isShowingPages = false
                        rebuildPDF()
                    },
                    onDelete: { deleteNote(at: $0) },
                    onAddAt: { insertNote(template: NoteInsertSettings.template, color: NoteInsertSettings.color, position: .after, size: NoteInsertSettings.size, at: $0) },
                    onMove: movePages
                )
            }
        }
        .sheet(isPresented: $isSharing) {
            if let shareURL {
                ShareActivityView(url: shareURL)
            }
        }
        .confirmationDialog("Note page", isPresented: Binding(
            get: { noteMenuIndex != nil },
            set: { if !$0 { noteMenuIndex = nil } }
        ), titleVisibility: .visible) {
            Button("Duplicate") { if let noteMenuIndex { duplicateNote(at: noteMenuIndex) } }
            Button("Change template") {
                changingPageIndex = noteMenuIndex
                isAddingPage = true
            }
            Button("Move") { isShowingPages = true }
            Button("Delete", role: .destructive) { pendingDeleteIndex = noteMenuIndex }
        }
        .alert("Delete this note page?", isPresented: Binding(
            get: { pendingDeleteIndex != nil },
            set: { if !$0 { pendingDeleteIndex = nil } }
        )) {
            Button("Delete", role: .destructive) {
                if let pendingDeleteIndex { deleteNote(at: pendingDeleteIndex) }
                pendingDeleteIndex = nil
            }
            Button("Cancel", role: .cancel) { pendingDeleteIndex = nil }
        }
        .onChange(of: eraserModeRaw) { toolState.eraserMode = EraserMode(parsing: eraserModeRaw) }
        .task(id: document.id) {
            if pdf == nil {
                let original = document.isNotebook ? nil : PDFDocument(url: document.fileURL)
                if !document.isNotebook, original == nil {
                    loadFailed = true
                    return
                }
                PageIdentity.migrate(
                    document: document,
                    originalPageCount: original?.pageCount ?? document.pages.count,
                    in: modelContext
                )
                try? modelContext.save()
                pdf = PageIdentity.compose(pages: document.pages, original: original)
            }
            if let pdf {
                await paperIndex.start(documentID: document.id, title: document.title, pdf: pdf)
            }
            #if DEBUG
            presentDebugSampleCaptureIfRequested()
            presentTeachDemoIfRequested()
            applyDebugReaderStateIfRequested()
            presentScreenshotAnswerIfRequested()
            if ScreenshotMode.overview { isShowingPages = true }
            #endif
        }
    }

    /// Three floating capsules over the paper: back, tools, undo/redo/•••.
    private var floatingChrome: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 8) {
                    ReaderBackCapsule(onBack: { dismiss() })
                    if paperIndex.isIndexing {
                        ReaderIndexingChip()
                    }
                }
                Spacer(minLength: 8)
                if toolbarPosition == .top {
                    ReaderToolbar(toolState: toolState, axis: .horizontal)
                }
                Spacer(minLength: 8)
                ReaderMoreCapsule(
                    toolState: toolState,
                    title: document.title,
                    isFocused: $isFocused,
                    toolbarPositionRaw: $toolbarPositionRaw,
                    onSettings: { isShowingSettings = true },
                    onShare: presentShare,
                    onAddPage: { isAddingPage = true },
                    onPages: { isShowingPages = true }
                )
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            Spacer(minLength: 0)
        }
        .overlay(alignment: .leading) {
            if toolbarPosition == .left {
                ReaderToolbar(toolState: toolState, axis: .vertical)
                    .padding(.leading, 12)
                    .padding(.top, 60)
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
        }
        .allowsHitTesting(true)
    }

    #if DEBUG
    /// `-PCSampleCapture`: opens the search panel on a lasso around the top of page 1 (for screenshots).
    private func presentDebugSampleCaptureIfRequested() {
        guard ProcessInfo.processInfo.arguments.contains("-PCSampleCapture"),
              !searchCardSession.isPresented, let page = pdf?.page(at: 0) else { return }
        let box = page.bounds(for: .cropBox)
        let region = CGRect(x: box.minX + box.width * 0.2, y: box.maxY - box.height * 0.25,
                            width: box.width * 0.6, height: box.height * 0.06)
        guard let capture = CircleSearchCapture.make(path: CGPath(ellipseIn: region, transform: nil), page: page,
                                                     pageIndex: 0, documentID: document.id,
                                                     paperTitle: document.title) else { return }
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-PCMinimizeSearchCard") { searchCardStartMinimized = true }
        if arguments.contains("-PCDragSearchCard") {
            UserDefaults.standard.set("0.58,0.28", forKey: "searchCardPos.portrait")
        }
        Task {
            try? await Task.sleep(for: .milliseconds(600))
            present(capture)
        }
    }

    /// `-PCTeachDemo`: open a card on the flicker-noise sentence and auto-Explain.
    private func presentTeachDemoIfRequested() {
        guard ProcessInfo.processInfo.arguments.contains("-PCTeachDemo"),
              !searchCardSession.isPresented else { return }
        let passage = "1/f noise is typically mitigated by dynamic circuit techniques such as chopping and auto-zeroing."
        let page = pdf?.page(at: 0)
        let box = page?.bounds(for: .cropBox) ?? CGRect(x: 0, y: 0, width: 200, height: 40)
        let region = CGRect(x: box.minX + 36, y: box.maxY - 72, width: min(360, box.width - 72), height: 44)
        let image = page.map { CircleSearchCapture.renderImage(of: region, on: $0) } ?? UIImage()
        let capture = CircleCapture(
            documentID: document.id,
            paperTitle: document.title,
            pageIndex: 0,
            pageRect: region,
            selectedText: passage,
            image: image,
            surroundingText: "Chopping and auto-zeroing modulate offset and flicker out of the signal band."
        )
        Task {
            try? await Task.sleep(for: .milliseconds(700))
            present(capture)
        }
    }

    /// `-PCScreenshotAnswer <scenario>`: a box on the scenario's phrase or figure; the card streams a canned answer.
    private func presentScreenshotAnswerIfRequested() {
        guard let scenario = ScreenshotMode.answerScenario, !searchCardSession.isPresented,
              let pdf, let page = pdf.page(at: scenario.pageIndex) else { return }
        guard let capture = CircleSearchCapture.make(pageRect: scenario.pageRect, page: page, pageIndex: scenario.pageIndex,
                                                     documentID: document.id, paperTitle: document.title) else { return }
        Task {
            try? await Task.sleep(for: .milliseconds(800))
            present(capture)
        }
    }

    /// `-PCFocusMode`, `-PCEraserTool` (pixel mode), `-PCOpenPenPopover`: reader states for screenshots.
    private func applyDebugReaderStateIfRequested() {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-PCFocusMode") { isFocused = true }
        if arguments.contains("-PCEraserTool") {
            toolState.tool = .eraser
            toolState.eraserMode = .pixel
        }
        if arguments.contains("-PCOpenPenPopover") {
            toolState.tool = .pen
            Task {
                try? await Task.sleep(for: .milliseconds(600))
                toolState.isShowingInkOptions = true
            }
        }
    }
    #endif

    @ViewBuilder
    private var content: some View {
        if let pdf {
            PDFKitView(pdf: pdf, paper: document, toolState: toolState,
                       allowFingerDrawing: allowFingerDrawing, markers: showSearchMarkers ? markers : [],
                       onMarkerTap: showSavedAnswers,
                       onCapture: present,
                       onRevealChrome: { withAnimation(.toolbarSpring) { isFocused = false } },
                       anchorConverter: anchorConverter,
                       selectionShape: selectionShape,
                       searchCardSession: searchCardSession,
                       inkExporter: inkExporter,
                       onNoteLongPress: { noteMenuIndex = $0 },
                       onPullToAddPage: appendNoteFromPull)
                .animation(.snappy, value: searchCardSession.revision)
        } else if loadFailed {
            ContentUnavailableView("Can’t Open Paper", systemImage: "exclamationmark.triangle",
                                   description: Text("The PDF file is missing or damaged."))
                .foregroundStyle(Theme.ink)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            // Still opening: large PDFs take a moment, which isn't an error.
            ProgressView()
                .tint(Theme.inkSoft)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// One marker per distinct circled region, however many answers it has.
    private var markers: [SearchMarker] {
        var result: [SearchMarker] = []
        for record in records {
            let marker = SearchMarker(record)
            if !result.contains(marker) { result.append(marker) }
        }
        return result
    }

    // MARK: - Floating search card

    private func closeSearch() {
        searchCardSession.dismiss()
        #if DEBUG
        searchCardStartMinimized = false
        #endif
    }

    private func present(_ capture: CircleCapture) {
        let startMinimized: Bool = {
            #if DEBUG
            searchCardStartMinimized
            #else
            false
            #endif
        }()
        searchCardSession.showCapture(
            capture,
            anchor: anchorConverter.viewRect(pageIndex: capture.pageIndex, pageRect: capture.pageRect) ?? .zero,
            startMinimized: startMinimized,
            onClose: closeSearch
        ) { [modelContext] question, answer, provenance in
            modelContext.insert(SearchRecord(capture: capture, question: question,
                                             answer: answer, provenance: provenance,
                                             pageID: document.pageID(at: capture.pageIndex)))
            try? modelContext.save()
        }
    }

    private func showSavedAnswers(_ marker: SearchMarker) {
        let saved = records.filter(marker.matches)
        guard !saved.isEmpty else { return }
        searchCardSession.showMarker(
            marker,
            records: saved,
            anchor: anchorConverter.viewRect(pageIndex: marker.pageIndex, pageRect: marker.pageRect) ?? .zero,
            onClose: { self.searchCardSession.dismiss() },
            onDeleteSaved: {
                saved.forEach(modelContext.delete)
                try? modelContext.save()
                self.searchCardSession.dismiss()
            }
        )
    }

    private func originalPDF() -> PDFDocument? {
        document.isNotebook ? nil : PDFDocument(url: document.fileURL)
    }

    private func rebuildPDF() {
        pdf = PageIdentity.compose(pages: document.pages, original: originalPDF())
        try? modelContext.save()
        ThumbnailCache.shared.remove(document.id)
    }

    private func insertNote(
        template: NoteTemplate,
        color: NotePaperColor,
        position: PageIdentity.InsertPosition,
        size: NotePageSize,
        at forcedIndex: Int? = nil
    ) {
        var pages = document.pages
        let index = forcedIndex ?? PageIdentity.insertIndex(
            position: position, currentIndex: document.lastPageIndex, count: pages.count
        )
        let resolved = document.isNotebook ? size : .matching
        pages.insert(PageRef(kind: .note(template: template, size: resolved, color: color)), at: min(max(index, 0), pages.count))
        document.pages = pages
        document.lastPageIndex = min(index, pages.count - 1)
        toolState.tool = .pen
        rebuildPDF()
    }

    /// Pull-past-end uses last Add Page template/color/size and always appends at `.end`.
    private func appendNoteFromPull() {
        insertNote(
            template: NoteInsertSettings.template,
            color: NoteInsertSettings.color,
            position: .end,
            size: NoteInsertSettings.size
        )
        let newIndex = document.pages.count - 1
        DispatchQueue.main.async {
            ReaderJump.page(newIndex)
        }
    }

    private func replaceNote(at index: Int, template: NoteTemplate, color: NotePaperColor, size: NotePageSize) {
        var pages = document.pages
        guard pages.indices.contains(index), case .note = pages[index].kind else { return }
        let resolved = document.isNotebook ? size : .matching
        pages[index].kind = .note(template: template, size: resolved, color: color)
        document.pages = pages
        rebuildPDF()
    }

    private func duplicateNote(at index: Int) {
        var pages = document.pages
        guard pages.indices.contains(index), case .note(let template, let size, let color) = pages[index].kind else { return }
        pages.insert(PageRef(kind: .note(template: template, size: size, color: color)), at: index + 1)
        document.pages = pages
        document.lastPageIndex = index + 1
        rebuildPDF()
    }

    private func deleteNote(at index: Int) {
        var pages = document.pages
        guard pages.indices.contains(index), case .note = pages[index].kind else { return }
        pages.remove(at: index)
        document.pages = pages
        document.lastPageIndex = min(document.lastPageIndex, max(pages.count - 1, 0))
        rebuildPDF()
    }

    private func movePages(from offsets: IndexSet, to destination: Int) {
        guard let source = offsets.first else { return }
        var pages = document.pages
        guard PageIdentity.move(&pages, from: source, to: destination) else { return }
        document.pages = pages
        rebuildPDF()
    }

    private func drawingMap() -> [UUID: PKDrawing] {
        let id = document.id
        let rows = (try? modelContext.fetch(FetchDescriptor<PageDrawing>(predicate: #Predicate { $0.documentID == id }))) ?? []
        var map: [UUID: PKDrawing] = [:]
        for row in rows {
            guard let pageID = row.pageID, let drawing = try? PKDrawing(data: row.drawingData) else { continue }
            map[pageID] = drawing
        }
        return map
    }

    /// Persisted offscreen ink plus live visible canvas snapshots (live wins).
    private func drawingsForExport() -> [UUID: PKDrawing] {
        AnnotatedPDF.mergedDrawings(
            persisted: drawingMap(),
            live: inkExporter.flushAndSnapshotVisible()
        )
    }

    /// Build a fresh annotated PDF at tap time, then present the system share sheet.
    private func presentShare() {
        guard let data = AnnotatedPDF.make(
            pages: document.pages,
            original: originalPDF(),
            drawings: drawingsForExport()
        ) else { return }
        let url = FileManager.default.temporaryDirectory
            .appending(path: "\(document.id.uuidString)-annotated.pdf")
        do {
            try data.write(to: url, options: .atomic)
            shareURL = url
            // Let the overflow Menu finish dismissing before presenting the share sheet.
            DispatchQueue.main.async { isSharing = true }
        } catch {
            // Leave sheet closed if the temp write fails.
        }
    }
}

#if DEBUG
/// The dashed box a Pencil box-selection draws, kept on screen for screenshots.
private struct ScreenshotSelectionBox: View {
    let rect: CGRect

    var body: some View {
        Rectangle()
            .fill(Theme.accent.opacity(0.1))
            .overlay(Rectangle().stroke(Theme.accent, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round, dash: [8, 6])))
            .frame(width: rect.width, height: rect.height)
            .position(x: rect.midX, y: rect.midY)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .allowsHitTesting(false)
    }
}
#endif

