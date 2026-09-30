import Foundation

enum CitationKind: Equatable, Hashable, Sendable {
    /// This paper's reference list, e.g. `[22]`.
    case paper(marker: String)
    /// A fetched web/paper source, e.g. `[S1]`.
    case source(index: Int)
    /// Author-year, e.g. `(Smith 2020)`.
    case authorYear(author: String, year: String)
}

enum AnswerRun: Equatable, Sendable {
    case text(String)
    case citation(CitationKind, display: String)
}

/// Splits an answer into plain text and citation chips. Apply `AnswerMath.render` first.
enum CitationParser {
    static func tokenize(_ text: String) -> [AnswerRun] {
        guard !text.isEmpty else { return [] }
        let pattern = #"\[S(\d+)\]|\[(\d+)\]|\(([A-Za-z][A-Za-z\-]+(?:\s+et al\.)?)[,\s]+(\d{4})[a-z]?\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [.text(text)] }
        let ns = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
        var runs: [AnswerRun] = []
        var cursor = 0
        for match in matches {
            if match.range.location > cursor {
                let piece = ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
                if !piece.isEmpty { runs.append(.text(piece)) }
            }
            let display = ns.substring(with: match.range)
            if match.range(at: 1).location != NSNotFound {
                let index = Int(ns.substring(with: match.range(at: 1))) ?? 0
                runs.append(.citation(.source(index: index), display: display))
            } else if match.range(at: 2).location != NSNotFound {
                runs.append(.citation(.paper(marker: ns.substring(with: match.range(at: 2))), display: display))
            } else if match.range(at: 3).location != NSNotFound {
                let author = ns.substring(with: match.range(at: 3))
                let year = ns.substring(with: match.range(at: 4))
                runs.append(.citation(.authorYear(author: author, year: year), display: display))
            }
            cursor = match.range.location + match.range.length
        }
        if cursor < ns.length {
            let tail = ns.substring(from: cursor)
            if !tail.isEmpty { runs.append(.text(tail)) }
        }
        return runs
    }

    static func resolve(_ kind: CitationKind, in references: [PaperReference]) -> PaperReference? {
        switch kind {
        case .paper(let marker):
            return references.first { $0.marker == marker }
        case .authorYear(let author, let year):
            let needle = author.lowercased().replacingOccurrences(of: " et al.", with: "")
            return references.first {
                $0.year == year && (
                    $0.authors?.lowercased().contains(needle) == true
                    || $0.marker.lowercased().contains(needle)
                    || $0.raw.lowercased().contains(needle)
                )
            }
        case .source:
            return nil
        }
    }
}
