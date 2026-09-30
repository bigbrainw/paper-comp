import SwiftUI

/// One line of tools: pen, highlighter, eraser, Search, then a divider and the current color/width dots.
struct ReaderToolbar: View {
    @Bindable var toolState: ToolState
    let axis: Axis

    @Namespace private var selection

    private var isHorizontal: Bool { axis == .horizontal }

    var body: some View {
        axis.stack {
            tools
            ToolbarSeparator(axis: axis).padding(isHorizontal ? .horizontal : .vertical, 4)
            summaryDots
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.plain)
        .foregroundStyle(Theme.inkSoft)
        .font(.title3)
        .padding(isHorizontal ? .horizontal : .vertical, 8)
        .padding(isHorizontal ? .vertical : .horizontal, 0)
        .frame(width: isHorizontal ? nil : 44, height: isHorizontal ? 44 : nil)
        .readerFloatingChrome()
        .animation(.toolbarSpring, value: toolState.tool)
        .animation(.toolbarSpring, value: toolState.eraserMode)
    }

    private var tools: some View {
        axis.stack {
            ForEach(ReaderTool.allCases) { tool in
                toolToggle(tool)
            }
        }
    }

    private func toolToggle(_ tool: ReaderTool) -> some View {
        let isOn = toolState.tool == tool
        let hidesSelectionPill = toolState.isShowingInkOptions && toolState.tool == tool && tool.hasOptions
        return ZStack {
            if isOn && !hidesSelectionPill { SelectionPill(id: "tool", namespace: selection) }
            Image(systemName: tool.systemImage)
                .foregroundStyle(isOn ? Theme.accent : Theme.inkSoft)
        }
        .frame(width: 36, height: 36)
        .contentShape(.rect)
        .popover(isPresented: optionsBinding(for: tool), attachmentAnchor: .rect(.bounds),
                 arrowEdge: isHorizontal ? .top : .leading) {
            ToolOptionsPopover(toolState: toolState)
        }
        .onTapGesture { select(tool) }
        .onLongPressGesture(minimumDuration: 0.45) {
            if tool == .circleSearch { withAnimation(.toolbarSpring) { toolState.toggleCircleSearch() } }
        }
        .accessibilityElement()
        .accessibilityLabel(tool.title)
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { select(tool) }
        .accessibilityHint(tool == .circleSearch ? "Long-press to toggle Search." : "")
    }

    /// Tapping the selected ink or eraser tool opens its options; any other tap selects the tool.
    private func select(_ tool: ReaderTool) {
        if toolState.tool == tool, tool.hasOptions {
            toolState.isShowingInkOptions.toggle()
        } else {
            withAnimation(.toolbarSpring) { toolState.tool = tool }
        }
    }

    private func optionsBinding(for tool: ReaderTool) -> Binding<Bool> {
        Binding(
            get: { tool.hasOptions && toolState.tool == tool && toolState.isShowingInkOptions },
            set: { if !$0 { toolState.isShowingInkOptions = false } }
        )
    }

    @ViewBuilder
    private var summaryDots: some View {
        switch toolState.tool {
        case .pen, .highlighter:
            Circle()
                .fill(Color(uiColor: toolState.activeInk.swatch.color))
                .frame(width: 16, height: 16)
                .overlay { Circle().strokeBorder(Theme.accent.opacity(0.5), lineWidth: 1) }
                .frame(width: 28, height: 28)
                .accessibilityLabel(toolState.activeInk.swatch.name)
            Circle()
                .fill(Theme.inkSoft)
                .frame(width: toolState.activeInk.width.dotSize, height: toolState.activeInk.width.dotSize)
                .frame(width: 28, height: 28)
                .accessibilityLabel("\(toolState.activeInk.width.title) width")
        case .eraser:
            Circle()
                .strokeBorder(Theme.inkSoft, lineWidth: 1.5)
                .frame(width: 14, height: 14)
                .frame(width: 28, height: 28)
                .accessibilityLabel(toolState.eraserMode.title)
            if toolState.eraserMode == .pixel {
                Circle()
                    .fill(Theme.inkSoft)
                    .frame(width: toolState.eraserWidth.dotSize, height: toolState.eraserWidth.dotSize)
                    .frame(width: 28, height: 28)
                    .accessibilityLabel("\(toolState.eraserWidth.title) eraser size")
            }
        case .circleSearch:
            EmptyView()
        }
    }
}

private extension ReaderTool {
    var hasOptions: Bool { isInk || self == .eraser }
}
