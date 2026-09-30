import Foundation
import PDFKit
import UIKit

enum PaperTitle {
    /// PDF metadata title, else the largest-font line of page 1, else `fallback`.
    static func title(of document: PDFDocument, fallback: String) -> String {
        if let meta = document.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String {
            let trimmed = meta.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        guard let text = document.page(at: 0)?.attributedString else { return fallback }

        var best: (size: CGFloat, line: String)?
        text.enumerateAttribute(.font, in: NSRange(location: 0, length: text.length)) { value, range, _ in
            let size = (value as? UIFont)?.pointSize ?? 0
            let line = (text.string as NSString).substring(with: range)
                .split(whereSeparator: \.isNewline)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .first { !$0.isEmpty && !isArXivStamp($0) }
            if let line, size > (best?.size ?? -1) { best = (size, line) }
        }
        return best.map { String($0.line.prefix(200)) } ?? fallback
    }

    /// The rotated "arXiv:1706.03762v7 [cs.CL] 2 Aug 2023" margin stamp is often the largest text on page 1.
    private static func isArXivStamp(_ line: String) -> Bool {
        line.range(of: #"^arXiv:\d"#, options: .regularExpression) != nil
    }
}
