import SwiftUI

struct AddPageSheet: View {
    var showSize: Bool
    var onAdd: (NoteTemplate, NotePaperColor, PageIdentity.InsertPosition, NotePageSize) -> Void

    @AppStorage(NoteInsertSettings.templateKey) private var templateRaw = NoteTemplate.linedCollege.rawValue
    @AppStorage(NoteInsertSettings.colorKey) private var colorRaw = NotePaperColor.rice.rawValue
    @AppStorage(NoteInsertSettings.positionKey) private var positionRaw = PageIdentity.InsertPosition.after.rawValue
    @AppStorage(NoteInsertSettings.sizeKey) private var sizeRaw = NotePageSize.a4.rawValue

    private var paperColor: NotePaperColor {
        NotePaperColor(rawValue: colorRaw) ?? .rice
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Add page").font(.headline).foregroundStyle(Theme.ink)
                labeled("Template") {
                    NoteTemplatePicker(selection: $templateRaw, paper: paperColor)
                }
                labeled("Color") {
                    SearchSegmentedToggle(
                        options: NotePaperColor.allCases.map { ($0.rawValue, $0.pillLabel) },
                        selection: $colorRaw
                    )
                }
                if showSize {
                    labeled("Size") {
                        SearchSegmentedToggle(
                            options: NotePageSize.visibleCases.map { ($0.rawValue, $0.pillLabel) },
                            selection: $sizeRaw
                        )
                    }
                }
                labeled("Position") {
                    SearchSegmentedToggle(
                        options: PageIdentity.InsertPosition.allCases.map { ($0.rawValue, $0.pillLabel) },
                        selection: $positionRaw
                    )
                }
                Button("Add Page") {
                    let template = NoteTemplate(rawValue: templateRaw) ?? .linedCollege
                    let color = NotePaperColor(rawValue: colorRaw) ?? .rice
                    let position = PageIdentity.InsertPosition(rawValue: positionRaw) ?? .after
                    let size = NotePageSize(rawValue: sizeRaw) ?? .a4
                    NoteInsertSettings.remember(template: template, color: color, position: position, size: size)
                    onAdd(template, color, position, size)
                }
                .buttonStyle(SearchCapsuleButtonStyle())
            }
            .padding(20)
        }
        .frame(minWidth: 360)
        .frame(maxHeight: 520)
        .background(Theme.rice)
    }

    private func labeled(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.subheadline).foregroundStyle(Theme.inkSoft)
            content()
        }
    }
}

extension NoteTemplate {
    var pillLabel: String {
        switch self {
        case .blank: "Blank"
        case .linedCollege: "Lined"
        case .linedNarrow: "Narrow"
        case .wideRuled: "Wide"
        case .grid: "Grid"
        case .graph: "Graph"
        case .crossGrid: "Cross"
        case .dotted: "Dotted"
        case .isometricDot: "Isometric"
        case .hexagon: "Hex"
        case .cornell: "Cornell"
        case .handwriting: "Handwriting"
        case .musicStaff: "Music"
        case .checklist: "Checklist"
        }
    }
}

extension NotePaperColor {
    var pillLabel: String {
        switch self {
        case .white: "White"
        case .rice: "Rice"
        case .dark: "Dark"
        }
    }
}

extension NotePageSize {
    static var visibleCases: [NotePageSize] { [.a4, .letter] }

    var pillLabel: String {
        switch self {
        case .a4: "A4"
        case .letter: "Letter"
        case .matching: "Match"
        }
    }
}

extension PageIdentity.InsertPosition {
    var pillLabel: String {
        switch self {
        case .after: "After this page"
        case .before: "Before this page"
        case .end: "At end"
        }
    }
}
