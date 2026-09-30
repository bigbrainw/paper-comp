import SwiftUI

/// Content of the floating card that reopens the answers saved at one page marker.
struct SavedSearchPanel: View {
    let marker: SearchMarker
    let records: [SearchRecord]
    let onDelete: () -> Void

    @Environment(\.searchCardPalette) private var palette
    @Environment(\.searchCardWidth) private var cardWidth

    private var references: [PaperReference] {
        guard let documentID = records.first?.documentID else { return [] }
        return PaperIndexControllerCache.record(for: documentID)?.references ?? []
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Page \(marker.pageIndex + 1)")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(palette.inkSoft)
                    Spacer()
                    Button(role: .destructive, action: onDelete) {
                        Label("Delete", systemImage: "trash")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.danger)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Theme.danger.opacity(0.12), in: .capsule)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Delete Marker")
                }
                ForEach(records) { record in
                    entry(record)
                    if record.id != records.last?.id {
                        Rectangle().fill(palette.deep).frame(height: 0.5)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollContentBackground(.hidden)
        .frame(width: cardWidth, alignment: .topLeading)
        .background(palette.surface)
        .foregroundStyle(palette.ink)
        .safariLinkHost()
    }

    private func entry(_ record: SearchRecord) -> some View {
        let provenance = record.decodedProvenance()
        return VStack(alignment: .leading, spacing: 10) {
            Text(record.question)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(palette.ink)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(palette.deep, in: .rect(cornerRadius: 10, style: .continuous))
            AnswerCitationText(text: record.answer, references: references, sources: provenance.sources)
            AnswerSourcesBlock(passages: provenance.passages, sources: provenance.sources, allowEmptyMessage: true)
            Text(record.createdAt, format: .dateTime.month().day().hour().minute())
                .font(.caption2)
                .foregroundStyle(palette.inkSoft.opacity(0.7))
        }
    }
}
