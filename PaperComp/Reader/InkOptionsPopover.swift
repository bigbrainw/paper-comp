import PencilKit
import SwiftUI

/// Pen type, color, and width for the pen or highlighter, with a live sample stroke.
struct InkOptionsPopover: View {
    @Bindable var toolState: ToolState
    @Namespace private var selection

    private var isHighlighter: Bool { toolState.activeInkTool == .highlighter }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(toolState.activeInkTool.title)
                .font(.headline)
                .foregroundStyle(Theme.ink)

            InkPreview(tool: previewTool)
                .frame(height: 56)
                .background(Theme.paper, in: .rect(cornerRadius: 10, style: .continuous))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            if !isHighlighter {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 88), spacing: 8)], spacing: 8) {
                    ForEach(PenType.allCases) { type in
                        penTypePill(type)
                    }
                }
            }

            SwatchToggleGroup(axis: .horizontal, selection: $toolState.activeInk.swatch)
            DotToggleGroup(axis: .horizontal, options: InkWidth.allCases, selection: $toolState.activeInk.width,
                           label: "width", namespace: selection)
        }
        .padding(16)
        .frame(width: 320)
        .background {
            RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                .fill(Theme.riceSurface)
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
        .presentationCompactAdaptation(.popover)
        .presentationBackground {
            RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                .fill(Theme.riceSurface)
        }
        .presentationCornerRadius(Theme.cornerRadius)
    }

    private var previewTool: PKInkingTool {
        let ink = toolState.activeInk
        if isHighlighter {
            return PKInkingTool(.marker, color: ink.swatch.color.withAlphaComponent(0.35),
                                width: ink.width.points * ToolState.highlighterWidthScale)
        }
        return PKInkingTool(ink.penType.inkType, color: ink.swatch.color, width: ink.width.points)
    }

    private func penTypePill(_ type: PenType) -> some View {
        let isOn = toolState.pen.penType == type
        return Button {
            withAnimation(.toolbarSpring) { toolState.pen.penType = type }
        } label: {
            Text(type.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isOn ? Theme.accent : Theme.inkSoft)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(isOn ? Theme.accent.opacity(0.18) : Theme.riceDeep, in: .capsule)
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// A non-interactive canvas showing one synthesized S-curve in the given ink.
struct InkPreview: UIViewRepresentable {
    let tool: PKInkingTool

    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = PKCanvasView()
        canvas.isUserInteractionEnabled = false
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.overrideUserInterfaceStyle = .light
        return canvas
    }

    func updateUIView(_ canvas: PKCanvasView, context: Context) {
        canvas.drawing = Self.sample(tool: tool, size: canvas.bounds.size == .zero ? CGSize(width: 288, height: 56) : canvas.bounds.size)
    }

    static func sample(tool: PKInkingTool, size: CGSize) -> PKDrawing {
        let count = 40
        let width = max(tool.width, 1)
        let points = (0..<count).map { i -> PKStrokePoint in
            let t = CGFloat(i) / CGFloat(count - 1)
            let x = 16 + t * (size.width - 32)
            let y = size.height / 2 + sin(t * .pi * 2) * size.height * 0.25
            let force = 0.4 + 0.8 * sin(t * .pi)
            return PKStrokePoint(location: CGPoint(x: x, y: y), timeOffset: TimeInterval(t) * 0.4,
                                 size: CGSize(width: width * force, height: width * force), opacity: 1,
                                 force: force, azimuth: .pi / 4, altitude: .pi / 3)
        }
        let path = PKStrokePath(controlPoints: points, creationDate: .now)
        return PKDrawing(strokes: [PKStroke(ink: PKInk(tool.inkType, color: tool.color), path: path)])
    }
}
