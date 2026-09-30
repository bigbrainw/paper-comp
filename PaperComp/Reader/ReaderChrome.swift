import SwiftUI

/// Square back button that floats over the paper. No title.
struct ReaderBackCapsule: View {
    let onBack: () -> Void

    var body: some View {
        Button(action: onBack) {
            Image(systemName: "chevron.left")
                .font(.body.weight(.semibold))
                .foregroundStyle(Theme.inkSoft)
                .frame(width: 44, height: 44)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .readerFloatingChrome(square: true)
        .accessibilityLabel("Library")
    }
}

/// Undo, redo, and the overflow menu (Share, Settings, Focus, toolbar position, title).
struct ReaderMoreCapsule: View {
    @Bindable var toolState: ToolState
    let title: String
    @Binding var isFocused: Bool
    @Binding var toolbarPositionRaw: String
    let onSettings: () -> Void
    var onShare: () -> Void = {}
    var onAddPage: () -> Void = {}
    var onPages: () -> Void = {}

    var body: some View {
        HStack(spacing: 2) {
            Button("Undo", systemImage: "arrow.uturn.backward", action: toolState.undo)
                .frame(width: 36, height: 36)
                .disabled(!toolState.canUndo)
                .opacity(toolState.canUndo ? 1 : 0.35)
            Button("Redo", systemImage: "arrow.uturn.forward", action: toolState.redo)
                .frame(width: 36, height: 36)
                .disabled(!toolState.canRedo)
                .opacity(toolState.canRedo ? 1 : 0.35)
            Menu {
                Button("Add Page", systemImage: "plus", action: onAddPage)
                Button("Pages", systemImage: "square.grid.2x2", action: onPages)
                Button("Share annotated PDF", systemImage: "square.and.arrow.up", action: onShare)
                Button("Settings", systemImage: "gearshape", action: onSettings)
                Button("Focus Mode", systemImage: "arrow.up.left.and.arrow.down.right") {
                    withAnimation(.toolbarSpring) { isFocused = true }
                }
                Picker("Toolbar position", selection: $toolbarPositionRaw) {
                    Text("Top").tag(ToolbarPosition.top.rawValue)
                    Text("Left").tag(ToolbarPosition.left.rawValue)
                }
                Section(title) {
                    Text("Paper")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.body.weight(.semibold))
                    .frame(width: 36, height: 36)
                    .contentShape(.rect)
            }
            .accessibilityLabel("More")
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.plain)
        .foregroundStyle(Theme.inkSoft)
        .padding(.horizontal, 8)
        .frame(height: 44)
        .readerFloatingChrome()
    }
}

/// Small chip under the back button while PaperIndex is building.
struct ReaderIndexingChip: View {
    var body: some View {
        Text("Indexing paper…")
            .font(.caption2.weight(.medium))
            .foregroundStyle(Theme.inkSoft)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background {
                Capsule()
                    .fill(.ultraThinMaterial)
                    .overlay { Capsule().fill(Theme.riceSurface.opacity(0.92)) }
            }
            .shadow(color: Theme.ink.opacity(0.10), radius: 8, y: 2)
            .accessibilityIdentifier("paper.index.chip")
    }
}

struct ReaderFocusNub: View {
    let onShow: () -> Void

    var body: some View {
        Button(action: onShow) {
            Image(systemName: "chevron.compact.down")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Theme.inkSoft)
                .frame(width: 64, height: 24)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .background {
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay { Capsule().fill(Theme.riceSurface.opacity(0.92)) }
        }
        .shadow(color: Theme.ink.opacity(0.12), radius: 8, y: 2)
        .padding(.top, 4)
        .accessibilityLabel("Show Toolbar")
    }
}
