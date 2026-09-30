import SwiftUI

/// Always shown under an answer: paper pages used, then web sources.
struct AnswerSourcesBlock: View {
    var passages: [PaperPassage]
    var sources: [WebSource]
    var allowEmptyMessage = false

    @Environment(\.searchCardPalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Sources")
                .font(.caption.weight(.semibold))
                .foregroundStyle(palette.inkSoft)
            if passages.isEmpty && sources.isEmpty {
                if allowEmptyMessage {
                    Text("No sources saved")
                        .font(.footnote)
                        .foregroundStyle(palette.inkSoft)
                }
            } else {
                if !passages.isEmpty {
                    Text("From this paper")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(palette.inkSoft)
                    ForEach(uniquePages, id: \.self) { page in
                        Button("Page \(page + 1)") { ReaderJump.page(page) }
                            .buttonStyle(.plain)
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(Theme.accent)
                    }
                }
                if !sources.isEmpty {
                    Text("From the web")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(palette.inkSoft)
                    ForEach(Array(sources.enumerated()), id: \.element.id) { index, source in
                        VStack(alignment: .leading, spacing: 2) {
                            SafariSourceLink(source: numbered(source, index: index + 1))
                            meta(source)
                        }
                    }
                }
            }
        }
    }

    private var uniquePages: [Int] {
        var seen = Set<Int>()
        return passages.compactMap { seen.insert($0.pageIndex).inserted ? $0.pageIndex : nil }
    }

    private func numbered(_ source: WebSource, index: Int) -> WebSource {
        var copy = source
        if !copy.title.hasPrefix("[S") {
            copy = WebSource(
                title: "[S\(index)] \(source.title)",
                url: source.url,
                site: source.site,
                year: source.year,
                studyType: source.studyType,
                takeaway: source.takeaway,
                doi: source.doi
            )
        }
        return copy
    }

    @ViewBuilder
    private func meta(_ source: WebSource) -> some View {
        let bits = [source.displaySite, source.year, source.studyType].compactMap { $0 }.filter { !$0.isEmpty }
        if !bits.isEmpty {
            Text(bits.joined(separator: " · "))
                .font(.caption2)
                .foregroundStyle(palette.inkSoft)
        }
        if let takeaway = source.takeaway, !takeaway.isEmpty {
            Text(takeaway)
                .font(.caption)
                .foregroundStyle(palette.inkSoft)
        }
    }
}
