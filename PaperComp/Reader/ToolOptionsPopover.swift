import PencilKit
import SwiftUI

/// Options for the active tool: ink (type, color, width) or eraser (mode, size).
struct ToolOptionsPopover: View {
    @Bindable var toolState: ToolState

    var body: some View {
        Group {
            if toolState.tool == .eraser {
                EraserOptionsPopover(toolState: toolState)
            } else {
                InkOptionsPopover(toolState: toolState)
            }
        }
    }
}

/// Stroke/pixel mode and pixel size.
struct EraserOptionsPopover: View {
    @Bindable var toolState: ToolState
    @Namespace private var selection

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Eraser")
                .font(.headline)
                .foregroundStyle(Theme.ink)
            EraserModeToggleGroup(axis: .horizontal, selection: $toolState.eraserMode, namespace: selection)
            if toolState.eraserMode == .pixel {
                DotToggleGroup(axis: .horizontal, options: EraserWidth.allCases,
                               selection: $toolState.eraserWidth, label: "eraser size", namespace: selection)
            }
        }
        .padding(16)
        .frame(width: 280)
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
}
