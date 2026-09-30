import SwiftUI
import UIKit

/// Compact grid of live template thumbnails for Add Page / New Notebook sheets.
struct NoteTemplatePicker: View {
    @Binding var selection: String
    var paper: NotePaperColor

    private let columns = [GridItem(.adaptive(minimum: 72), spacing: 10)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(NoteTemplate.allCases, id: \.rawValue) { template in
                let selected = selection == template.rawValue
                Button {
                    selection = template.rawValue
                } label: {
                    VStack(spacing: 6) {
                        Image(uiImage: TemplateThumbnailCache.image(for: template, color: paper))
                            .resizable()
                            .aspectRatio(NotePageRenderer.a4.width / NotePageRenderer.a4.height, contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .strokeBorder(
                                        selected ? Theme.accent : Theme.riceDeep,
                                        lineWidth: selected ? 2 : 0.5
                                    )
                            }
                        Text(template.pillLabel)
                            .font(.caption2.weight(selected ? .semibold : .regular))
                            .foregroundStyle(selected ? Theme.ink : Theme.inkSoft)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(template.pillLabel)
                .accessibilityAddTraits(selected ? [.isSelected] : [])
            }
        }
    }
}

/// Small static cache so sheet rebuilds don't re-rasterize every cell.
enum TemplateThumbnailCache {
    nonisolated(unsafe) private static let cache = NSCache<NSString, UIImage>()
    private static let thumbSize = CGSize(width: 88, height: 124)

    static func image(for template: NoteTemplate, color: NotePaperColor) -> UIImage {
        let key = "\(template.rawValue)|\(color.rawValue)" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        let image = NotePageRenderer.thumbnail(template: template, color: color, size: thumbSize)
        cache.setObject(image, forKey: key)
        return image
    }
}
