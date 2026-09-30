import SwiftUI

/// Capsule toggle used for the library's sort and filter controls.
struct LibraryPill: View {
    let title: String
    var systemImage: String?
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage { Image(systemName: systemImage) }
                Text(title)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(isOn ? Theme.accent : Theme.inkSoft)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(isOn ? Theme.accent.opacity(0.18) : Theme.riceDeep, in: .capsule)
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}
