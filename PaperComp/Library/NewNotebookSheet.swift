import SwiftUI

struct NewNotebookSheet: View {
    var onCreate: (String, NoteTemplate, NotePaperColor, NotePageSize, NotePaperColor) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var template = NoteTemplate.linedCollege
    @State private var color = NotePaperColor.rice
    @State private var size = NotePageSize.a4
    @State private var cover = NotePaperColor.rice

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $title)
                    SearchSegmentedToggle(
                        options: NotePaperColor.allCases.map { ($0.rawValue, $0.pillLabel) },
                        selection: coverRaw
                    )
                } header: {
                    Text("Notebook")
                } footer: {
                    Text("Cover")
                }
                Section("Pages") {
                    NoteTemplatePicker(selection: templateRaw, paper: color)
                    SearchSegmentedToggle(
                        options: NotePaperColor.allCases.map { ($0.rawValue, $0.pillLabel) },
                        selection: colorRaw
                    )
                    SearchSegmentedToggle(
                        options: NotePageSize.visibleCases.map { ($0.rawValue, $0.pillLabel) },
                        selection: sizeRaw
                    )
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.rice)
            .navigationTitle("New notebook")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        onCreate(title, template, color, size, cover)
                        dismiss()
                    }
                }
            }
        }
    }

    private var templateRaw: Binding<String> {
        Binding(get: { template.rawValue }, set: { template = NoteTemplate(rawValue: $0) ?? template })
    }
    private var colorRaw: Binding<String> {
        Binding(get: { color.rawValue }, set: { color = NotePaperColor(rawValue: $0) ?? color })
    }
    private var sizeRaw: Binding<String> {
        Binding(get: { size.rawValue }, set: { size = NotePageSize(rawValue: $0) ?? size })
    }
    private var coverRaw: Binding<String> {
        Binding(get: { cover.rawValue }, set: { cover = NotePaperColor(rawValue: $0) ?? cover })
    }
}
