import SwiftUI

struct PaperCell: View {
    let document: PaperDocument
    @State private var thumbnail: UIImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                Theme.riceDeep
                if let thumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .scaledToFit()
                } else {
                    ProgressView().tint(Theme.inkSoft)
                }
            }
            .aspectRatio(0.77, contentMode: .fit)
            .clipShape(.rect(cornerRadius: 10, style: .continuous))

            Text(document.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.ink)
                .lineLimit(2, reservesSpace: true)
            HStack(spacing: 6) {
                if document.isNotebook {
                    Text("Notebook")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Theme.accent.opacity(0.16), in: .capsule)
                        .foregroundStyle(Theme.accent)
                }
                Text(document.addedAt, format: .dateTime.day().month().year())
                    .font(.caption)
                    .foregroundStyle(Theme.inkSoft)
            }
        }
        .padding(12)
        .background(Theme.riceSurface, in: .rect(cornerRadius: Theme.cornerRadius, style: .continuous))
        .riceShadow()
        .contentShape(.rect(cornerRadius: Theme.cornerRadius, style: .continuous))
        .task(id: document.id) {
            thumbnail = await ThumbnailCache.shared.thumbnail(for: document, size: CGSize(width: 400, height: 520))
        }
    }
}
