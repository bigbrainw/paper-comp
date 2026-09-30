import UIKit

/// Markdown → attributed text with no leftover `**`. Citations stay tappable via ranges.
enum AnswerMarkdown {
    static func nsAttributed(_ markdown: String, ink: UIColor, fontSize: CGFloat = 16) -> NSAttributedString {
        let cleaned = AnswerMath.render(markdown)
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .full,
            failurePolicy: .returnPartiallyParsedIfPossible
        )
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 4.8
        let base: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: fontSize),
            .foregroundColor: ink,
            .paragraphStyle: paragraph,
        ]
        let result = NSMutableAttributedString()
        let blocks = cleaned
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let parts = blocks.isEmpty ? [cleaned] : blocks
        for (index, block) in parts.enumerated() {
            if index > 0 { result.append(NSAttributedString(string: "\n\n", attributes: base)) }
            if let parsed = try? AttributedString(markdown: block, options: options) {
                let chunk = NSMutableAttributedString(parsed)
                chunk.addAttributes(
                    [.foregroundColor: ink, .paragraphStyle: paragraph],
                    range: NSRange(location: 0, length: chunk.length)
                )
                result.append(chunk)
            } else {
                result.append(NSAttributedString(string: block, attributes: base))
            }
        }
        return result
    }

    static func applyingCitations(
        _ attributed: NSAttributedString,
        accent: UIColor,
        kinds: inout [URL: CitationKind]
    ) -> NSAttributedString {
        let tokens = CitationParser.tokenize(attributed.string)
        guard tokens.contains(where: {
            if case .citation = $0 { return true }
            return false
        }) else { return attributed }

        let result = NSMutableAttributedString(attributedString: attributed)
        var cursor = 0
        for (index, run) in tokens.enumerated() {
            switch run {
            case .text(let piece):
                cursor += (piece as NSString).length
            case .citation(let kind, let display):
                let length = (display as NSString).length
                let range = NSRange(location: cursor, length: length)
                guard range.location + range.length <= result.length else { continue }
                let url = URL(string: "papercomp://cite/\(index)")!
                kinds[url] = kind
                result.addAttributes([
                    .foregroundColor: accent,
                    .font: UIFont.systemFont(ofSize: 16, weight: .semibold),
                    .backgroundColor: accent.withAlphaComponent(0.18),
                    .link: url,
                ], range: range)
                cursor += length
            }
        }
        return result
    }
}
