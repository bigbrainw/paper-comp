import SwiftUI

/// Toggle pill for quick chips: palette `deep` capsule, `accent` tint while selected.
struct SearchChipStyle: ButtonStyle {
    var isSelected: Bool
    @Environment(\.searchCardPalette) private var palette

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.footnote.weight(.medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .foregroundStyle(isSelected ? Theme.accent : palette.ink)
            .background(isSelected ? Theme.accent.opacity(0.18) : palette.deep, in: .capsule)
            .opacity(configuration.isPressed ? 0.7 : 1)
            .animation(.spring(duration: 0.25), value: isSelected)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Capsule button. `prominent` fills with `accent`; otherwise a quiet `riceDeep` capsule.
struct SearchCapsuleButtonStyle: ButtonStyle {
    var prominent = false
    var role: ButtonRole?
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.searchCardPalette) private var palette

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.footnote.weight(.semibold))
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .foregroundStyle(foreground)
            .background(prominent && isEnabled ? Theme.accent : palette.deep, in: .capsule)
            .opacity(configuration.isPressed ? 0.7 : 1)
    }

    private var foreground: Color {
        if !isEnabled { return palette.inkSoft }
        if prominent { return palette.surface }
        return role == .destructive ? Theme.danger : palette.ink
    }
}

/// Lays subviews out left to right, wrapping onto new lines when the width runs out.
struct SearchFlowLayout: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = (proposal.width?.isFinite == true && (proposal.width ?? 0) > 0)
            ? proposal.width!
            : SearchCardPlacement.cardWidth
        let rows = rows(for: subviews, maxWidth: maxWidth)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.map(\.height).reduce(0, +) + lineSpacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(for: subviews, maxWidth: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y + (row.height - size.height) / 2),
                                      proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + lineSpacing
        }
    }

    private struct Row { var indices: [Int] = []; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func rows(for subviews: Subviews, maxWidth: CGFloat) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let proposedWidth = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            if proposedWidth > maxWidth, !current.indices.isEmpty {
                rows.append(current)
                current = Row()
            }
            current.width = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            current.height = max(current.height, size.height)
            current.indices.append(index)
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}

/// Segmented toggle-pill control on the rice palette: `riceDeep` track, `accent` pill for the selection.
struct SearchSegmentedToggle<Value: Hashable>: View {
    let options: [(value: Value, label: String)]
    @Binding var selection: Value
    @Namespace private var pill

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.value) { option in
                let isSelected = option.value == selection
                Button {
                    withAnimation(.spring(duration: 0.3)) { selection = option.value }
                } label: {
                    Text(option.label)
                        .font(.subheadline.weight(isSelected ? .semibold : .regular))
                        .foregroundStyle(isSelected ? Theme.accent : Theme.inkSoft)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background {
                            if isSelected {
                                Capsule()
                                    .fill(Theme.riceSurface)
                                    .overlay { Capsule().fill(Theme.accent.opacity(0.18)) }
                                    .matchedGeometryEffect(id: "pill", in: pill)
                            }
                        }
                        .contentShape(.capsule)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(3)
        .background(Theme.riceDeep, in: .capsule)
    }
}
