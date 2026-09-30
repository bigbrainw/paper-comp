import PDFKit
import PencilKit
import SwiftUI

struct PageOverviewView: View {
    let pages: [PageRef]
    let composed: PDFDocument
    let drawings: [UUID: PKDrawing]
    let currentIndex: Int
    var onSelect: (Int) -> Void
    var onDelete: (Int) -> Void
    var onAddAt: (Int) -> Void
    var onMove: (IndexSet, Int) -> Void

    var body: some View {
        NavigationStack {
            List {
                ForEach(Array(pages.enumerated()), id: \.element.id) { index, page in
                    Button { onSelect(index) } label: {
                        HStack(spacing: 12) {
                            thumbnail(at: index, pageID: page.id)
                                .frame(width: 56, height: 72)
                                .background(Theme.riceDeep)
                                .clipShape(.rect(cornerRadius: 6, style: .continuous))
                                .overlay {
                                    if index == currentIndex {
                                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                                            .stroke(Theme.accent, lineWidth: 2)
                                    }
                                }
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Page \(index + 1)")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Theme.ink)
                                if case .note = page.kind {
                                    Text("Note")
                                        .font(.caption2.weight(.semibold))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Theme.accent.opacity(0.18), in: .capsule)
                                        .foregroundStyle(Theme.accent)
                                }
                            }
                            Spacer()
                        }
                    }
                    .listRowBackground(Theme.riceSurface)
                    .contextMenu {
                        if case .note = page.kind {
                            Button("Delete", role: .destructive) { onDelete(index) }
                        }
                        Button("Add page after") { onAddAt(index + 1) }
                    }
                }
                .onMove(perform: onMove)
            }
            .scrollContentBackground(.hidden)
            .background(Theme.rice)
            .navigationTitle("Pages")
            .navigationBarTitleDisplayMode(.inline)
            .environment(\.editMode, .constant(.active))
        }
    }

    @ViewBuilder
    private func thumbnail(at index: Int, pageID: UUID) -> some View {
        if let page = composed.page(at: index) {
            let size = CGSize(width: 56, height: 72)
            let base = page.thumbnail(of: size, for: .cropBox)
            if let drawing = drawings[pageID], !drawing.strokes.isEmpty {
                let ink = drawing.image(from: page.bounds(for: .cropBox), scale: 1)
                Image(uiImage: composite(base, ink: ink)).resizable().scaledToFit()
            } else {
                Image(uiImage: base).resizable().scaledToFit()
            }
        } else {
            Theme.riceDeep
        }
    }

    private func composite(_ base: UIImage, ink: UIImage) -> UIImage {
        let size = base.size
        let format = UIGraphicsImageRendererFormat()
        format.scale = base.scale
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            base.draw(in: CGRect(origin: .zero, size: size))
            ink.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
