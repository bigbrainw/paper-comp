import SwiftUI

/// Renders streaming Markdown line by line: headings and list items get block styling,
/// inline syntax (bold, code, links) goes through `AttributedString(markdown:)`.
struct MarkdownText: View {
    let markdown: String
    @Environment(\.searchCardPalette) private var palette

    private var cleaned: String { AnswerMath.render(markdown) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(Self.blocks(cleaned).enumerated()), id: \.offset) { _, block in
                row(for: block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .font(.system(size: 16))
        .lineSpacing(4.8)
        .foregroundStyle(palette.ink)
        .tint(Theme.accent)
        .textSelection(.enabled)
    }

    @ViewBuilder
    private func row(for line: String) -> some View {
        if let heading = Self.strip(line, prefixes: ["### ", "## ", "# "]) {
            Text(Self.inline(heading)).font(.headline)
        } else if let item = Self.strip(line, prefixes: ["- ", "* ", "• "]) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("•")
                Text(Self.inline(item))
            }
        } else {
            Text(Self.inline(line))
        }
    }

    static func blocks(_ markdown: String) -> [String] {
        markdown
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    static func inline(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .full,
            failurePolicy: .returnPartiallyParsedIfPossible
        )
        var result = (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
        for run in result.runs where run.link != nil {
            result[run.range].foregroundColor = Theme.accent
        }
        return result
    }

    private static func strip(_ line: String, prefixes: [String]) -> String? {
        prefixes.first(where: line.hasPrefix).map { String(line.dropFirst($0.count)) }
    }
}
