import SwiftUI

struct ReferencePopover: View {
    let reference: PaperReference
    var kind: CitationKind?
    var onAskAbout: ((PaperReference) -> Void)?

    @State private var finding = false
    @State private var foundURL: URL?
    @State private var findError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
                .foregroundStyle(Theme.ink)
            Text(reference.raw)
                .font(.footnote)
                .foregroundStyle(Theme.inkSoft)
                .textSelection(.enabled)
            HStack(spacing: 8) {
                Button("Jump to reference") {
                    ReaderJump.search(jumpQuery)
                }
                .buttonStyle(SearchCapsuleButtonStyle(prominent: true))
                Button("Find online") { Task { await findOnline() } }
                    .buttonStyle(SearchCapsuleButtonStyle())
                    .disabled(finding)
                if let onAskAbout {
                    Button("Ask about this paper") { onAskAbout(reference) }
                        .buttonStyle(SearchCapsuleButtonStyle())
                }
            }
            if finding {
                ProgressView().controlSize(.small)
            }
            if let foundURL {
                SafariSourceLink(source: WebSource(title: title, url: foundURL))
            }
            if let findError {
                Text(findError).font(.caption).foregroundStyle(Theme.danger)
            }
        }
        .padding(16)
        .frame(minWidth: 300, idealWidth: 360)
        .presentationCompactAdaptation(.popover)
    }

    private var title: String {
        reference.title ?? "Reference [\(reference.marker)]"
    }

    private var jumpQuery: String {
        if let title = reference.title, title.count > 8 { return title }
        return reference.raw.prefix(80).description
    }

    private func findOnline() async {
        finding = true
        findError = nil
        defer { finding = false }
        let query = reference.title ?? CitationQueryExtractor.query(from: reference.raw)
        if let url = await ReferenceFinder.find(query: query, doi: reference.doi, arxivID: reference.arxivID) {
            foundURL = url
        } else {
            findError = "No online copy found."
        }
    }
}

enum ReferenceFinder {
    static func find(query: String, doi: String? = nil, arxivID: String? = nil) async -> URL? {
        if ConsensusSettings.isEnabled {
            let papers = await ConsensusSearch.search(query).papers
            if let url = papers.first?.url { return url }
        }
        let lookup = KeylessLookup()
        if let doi, let hit = await firstURL(lookup.paperSearch("DOI:\(doi)")) { return hit }
        if let arxivID, let hit = await firstURL(lookup.paperSearch("arXiv:\(arxivID)")) { return hit }
        return await firstURL(lookup.paperSearch(query))
    }

    private static func firstURL(_ result: LookupResult) -> URL? {
        result.sources.first?.url
    }
}
