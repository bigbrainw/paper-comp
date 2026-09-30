import SwiftUI

extension Axis {
    var stack: AnyLayout {
        self == .horizontal ? AnyLayout(HStackLayout(spacing: 2)) : AnyLayout(VStackLayout(spacing: 2))
    }
}

struct ToolbarSeparator: View {
    let axis: Axis

    var body: some View {
        Rectangle()
            .fill(Theme.riceDeep)
            .frame(width: axis == .horizontal ? 0.5 : 24, height: axis == .horizontal ? 24 : 0.5)
    }
}

/// Accent-18% capsule behind the selected item of a toggle group; slides between items.
struct SelectionPill: View {
    let id: String
    let namespace: Namespace.ID

    var body: some View {
        Capsule()
            .fill(Theme.accent.opacity(0.18))
            .matchedGeometryEffect(id: id, in: namespace)
    }
}

/// Three dots of increasing size; exactly one is on.
struct DotToggleGroup<Option: DotOption>: View {
    let axis: Axis
    let options: [Option]
    @Binding var selection: Option
    let label: String
    let namespace: Namespace.ID

    var body: some View {
        axis.stack {
            ForEach(options) { option in
                let isOn = selection == option
                Button {
                    withAnimation(.toolbarSpring) { selection = option }
                } label: {
                    Circle()
                        .fill(isOn ? Theme.accent : Theme.inkSoft)
                        .frame(width: option.dotSize, height: option.dotSize)
                        .frame(width: 30, height: 30)
                        .background { if isOn { SelectionPill(id: label, namespace: namespace) } }
                        .contentShape(.capsule)
                }
                .accessibilityLabel("\(option.title) \(label)")
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
    }
}

struct SwatchToggleGroup: View {
    let axis: Axis
    @Binding var selection: InkSwatch

    var body: some View {
        axis.stack {
            ForEach(InkSwatch.all) { swatch in
                let isOn = selection == swatch
                Button {
                    selection = swatch
                } label: {
                    Circle()
                        .fill(Color(uiColor: swatch.color))
                        .frame(width: 20, height: 20)
                        .padding(3)
                        .overlay { Circle().strokeBorder(Theme.accent, lineWidth: isOn ? 2 : 0) }
                        .padding(2)
                        .contentShape(.circle)
                }
                .accessibilityLabel(swatch.name)
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
    }
}

/// Stroke / Pixel eraser toggle. Text pills when horizontal, icon pills when stacked.
struct EraserModeToggleGroup: View {
    let axis: Axis
    @Binding var selection: EraserMode
    let namespace: Namespace.ID

    var body: some View {
        axis.stack {
            ForEach(EraserMode.allCases) { mode in
                let isOn = selection == mode
                Button {
                    withAnimation(.toolbarSpring) { selection = mode }
                } label: {
                    Group {
                        if axis == .horizontal {
                            Text(mode.title)
                                .font(.subheadline.weight(.semibold))
                                .padding(.horizontal, 12)
                                .frame(height: 30)
                        } else {
                            Image(systemName: mode.systemImage)
                                .frame(width: 36, height: 32)
                        }
                    }
                    .foregroundStyle(isOn ? Theme.accent : Theme.inkSoft)
                    .background { if isOn { SelectionPill(id: "eraserMode", namespace: namespace) } }
                    .contentShape(.capsule)
                }
                .accessibilityLabel("\(mode.title) eraser")
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
    }
}

extension Animation {
    static let toolbarSpring = Animation.spring(response: 0.35, dampingFraction: 0.8)
}
