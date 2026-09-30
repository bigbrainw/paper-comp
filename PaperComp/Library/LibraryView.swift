import SwiftData
import SwiftUI

struct LibraryView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \PaperDocument.addedAt, order: .reverse) private var documents: [PaperDocument]

    @State private var path: [PaperDocument] = []
    @State private var isImporting = false
    @State private var isCreatingNotebook = false
    @State private var isShowingSettings = false
    @State private var renaming: PaperDocument?
    @State private var renameText = ""
    @State private var errorMessage: String?
    @State private var sort: LibrarySort = .recent
    @State private var notesOnly = false
    @State private var kindFilter: LibraryKindFilter = .all
    @State private var withNotes: Set<UUID> = []

    private let columns = [GridItem(.adaptive(minimum: 200, maximum: 260), spacing: 24)]

    private var visibleDocuments: [PaperDocument] {
        LibraryOrdering.apply(documents, sort: sort, notesOnly: notesOnly, withNotes: withNotes, kind: kindFilter)
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if !documents.isEmpty { filterBar }
                    LazyVGrid(columns: columns, spacing: 24) {
                        ForEach(visibleDocuments) { document in
                            NavigationLink(value: document) {
                                PaperCell(document: document)
                            }
                            .buttonStyle(.plain)
                            .contextMenu { menu(for: document) }
                        }
                    }
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 12)
            }
            .background(Theme.rice)
            .overlay { emptyState }
            .navigationTitle("Papers")
            .toolbarBackground(Theme.rice, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { isShowingSettings = true } label: {
                        Image(systemName: "gearshape")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Theme.inkSoft)
                            .frame(width: 34, height: 34)
                            .background(Theme.riceDeep, in: .circle)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Settings")
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("Import PDF", systemImage: "doc") { isImporting = true }
                        Button("New notebook", systemImage: "book") { isCreatingNotebook = true }
                        Button("Add sample paper", systemImage: "doc.text.magnifyingglass") { addSamplePaper() }
                    } label: {
                        Image(systemName: "plus")
                            .font(.body.weight(.bold))
                            .foregroundStyle(Theme.riceSurface)
                            .frame(width: 34, height: 34)
                            .background(Theme.accent, in: .circle)
                    }
                    .accessibilityLabel("Add")
                }
            }
            .sheet(isPresented: $isShowingSettings) {
                SettingsView()
                    .presentationDetents([.large])
                    .presentationSizing(.page)
            }
            .sheet(isPresented: $isCreatingNotebook) {
                NewNotebookSheet { title, template, color, size, cover in
                    let notebook = DocumentStore.createNotebook(
                        title: title, template: template, color: color, size: size, cover: cover, into: context
                    )
                    path = [notebook]
                }
            }
            .navigationDestination(for: PaperDocument.self) { document in
                ReaderView(document: document)
            }
        }
        .onAppear(perform: refreshNotes)
        .onChange(of: path) { refreshNotes() }
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.pdf], allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls): urls.forEach { importFile($0) }
            case .failure(let error): errorMessage = error.localizedDescription
            }
        }
        .onOpenURL { url in
            if let document = importFile(url) { path = [document] }
        }
        .task {
            #if DEBUG
            if !DocumentStore.usesScratchLibrary { DocumentStore.importLooseFiles(into: context) }
            #else
            DocumentStore.importLooseFiles(into: context)
            #endif
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-PCSeedSamplePaper") {
                DocumentStore.seedSamplePaperIfNeeded(into: context)
            }
            if ProcessInfo.processInfo.arguments.contains("-PCOpenFirstPaper"),
               let first = try? context.fetch(FetchDescriptor<PaperDocument>(sortBy: [SortDescriptor(\.addedAt, order: .reverse)])).first {
                path = [first]
            }
            if ProcessInfo.processInfo.arguments.contains("-PCOpenSettings") { isShowingSettings = true }
            if let screenshotDocument = ScreenshotSeed.seedIfRequested(into: context) { path = [screenshotDocument] }
            if ScreenshotMode.modelReady { isShowingSettings = true }
            #endif
        }
        .alert("Rename Paper", isPresented: isRenamingBinding) {
            TextField("Title", text: $renameText)
            Button("Cancel", role: .cancel) {}
            Button("Rename") { commitRename() }
        }
        .alert("Import Failed", isPresented: isShowingErrorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var filterBar: some View {
        HStack(spacing: 8) {
            ForEach(LibrarySort.allCases) { option in
                LibraryPill(title: option.title, isOn: sort == option) {
                    withAnimation(.snappy) { sort = option }
                }
            }
            Rectangle().fill(Theme.riceDeep).frame(width: 0.5, height: 22).padding(.horizontal, 4)
            ForEach(LibraryKindFilter.allCases) { option in
                LibraryPill(title: option.title, isOn: kindFilter == option) {
                    withAnimation(.snappy) { kindFilter = option }
                }
            }
            LibraryPill(title: "Has notes", systemImage: "pencil.and.scribble", isOn: notesOnly) {
                refreshNotes()
                withAnimation(.snappy) { notesOnly.toggle() }
            }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if documents.isEmpty {
            ContentUnavailableView {
                Label("No Papers", systemImage: "doc.richtext")
                    .foregroundStyle(Theme.ink)
            } description: {
                Text("Import a PDF to start reading, or try a sample paper.")
                    .foregroundStyle(Theme.inkSoft)
            } actions: {
                HStack(spacing: 12) {
                    Button("Import PDF") { isImporting = true }
                        .buttonStyle(.borderedProminent)
                        .buttonBorderShape(.capsule)
                        .foregroundStyle(Theme.riceSurface)
                    Button("Try a sample paper") { addSamplePaper() }
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.capsule)
                        .foregroundStyle(Theme.accent)
                        .accessibilityIdentifier("library.sample")
                }
            }
        } else if visibleDocuments.isEmpty {
            ContentUnavailableView {
                Label("No Notes Yet", systemImage: "pencil.and.scribble")
                    .foregroundStyle(Theme.ink)
            } description: {
                Text("Papers you draw on or search appear here.")
                    .foregroundStyle(Theme.inkSoft)
            }
        }
    }

    private func refreshNotes() {
        withNotes = LibraryOrdering.documentIDsWithNotes(in: context)
    }

    @ViewBuilder
    private func menu(for document: PaperDocument) -> some View {
        Button("Rename", systemImage: "pencil") {
            renameText = document.title
            renaming = document
        }
        Button("Delete", systemImage: "trash", role: .destructive) {
            path.removeAll { $0.id == document.id }
            DocumentStore.delete(document, from: context)
        }
    }

    @discardableResult
    private func importFile(_ url: URL) -> PaperDocument? {
        do {
            return try DocumentStore.importPDF(from: url, into: context)
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    /// Imports the bundled CC BY sample (or finds the copy already there) and opens it.
    private func addSamplePaper() {
        do {
            path = [try DocumentStore.importSamplePaper(into: context)]
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func commitRename() {
        let title = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        if let renaming, !title.isEmpty {
            renaming.title = title
            try? context.save()
        }
        renaming = nil
    }

    private var isRenamingBinding: Binding<Bool> {
        Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })
    }

    private var isShowingErrorBinding: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }
}
