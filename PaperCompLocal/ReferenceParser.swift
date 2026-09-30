import Foundation

struct PaperReference: Codable, Equatable, Sendable {
    var marker: String
    var raw: String
    var title: String?
    var authors: String?
    var year: String?
    var arxivID: String?
    var doi: String?
}

enum ReferenceParser {
    static func parse(pages: [String]) -> [PaperReference] {
        let body = referencesBody(from: pages)
        guard !body.isEmpty else { return [] }
        if body.contains("[1]") || body.contains("[01]") {
            return numbered(body, pattern: #"\[(\d+)\]"#)
        }
        if body.range(of: #"(?m)^\d{1,3}\.\s"#, options: .regularExpression) != nil {
            return numbered(body, pattern: #"(?m)^(\d{1,3})\."#)
        }
        return authorYear(body)
    }

    static func referencesBody(from pages: [String]) -> String {
        let joined = pages.map(PaperText.dehyphenate).joined(separator: "\n")
        let pattern = #"(?is)(?:^|\n)\s*(?:\d+(?:\.\d+)*\s+)?(?:references|bibliography)\b[^\n]*\n(.+)"#
        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(in: joined, range: NSRange(joined.startIndex..., in: joined)),
           let range = Range(match.range(at: 1), in: joined) {
            return String(joined[range])
        }
        let tailStart = max(0, pages.count * 2 / 3)
        return pages.dropFirst(tailStart).map(PaperText.dehyphenate).joined(separator: "\n")
    }

    static func matching(selection: String, in references: [PaperReference]) -> [PaperReference] {
        var hits: [PaperReference] = []
        let numbers = selection.matches(of: #/\[(\d+)\]/#).map { String($0.1) }
        for number in numbers {
            if let found = references.first(where: { $0.marker == number }) { hits.append(found) }
        }
        let years = selection.matches(of: #/\(([A-Za-z][A-Za-z\-]+(?:\s+et al\.)?)[,\s]+(\d{4})\)/#)
        for match in years {
            let author = String(match.1).lowercased()
            let year = String(match.2)
            if let found = references.first(where: {
                $0.year == year && ($0.authors?.lowercased().contains(author) == true || $0.marker.lowercased().contains(author))
            }) {
                hits.append(found)
            }
        }
        return hits
    }

    private static func numbered(_ body: String, pattern: String) -> [PaperReference] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines]) else { return [] }
        let ns = body as NSString
        let matches = regex.matches(in: body, range: NSRange(location: 0, length: ns.length))
        var refs: [PaperReference] = []
        for (index, match) in matches.enumerated() {
            let marker = ns.substring(with: match.range(at: 1))
            let start = match.range.location
            let end = index + 1 < matches.count ? matches[index + 1].range.location : ns.length
            let raw = ns.substring(with: NSRange(location: start, length: end - start))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            refs.append(enrich(marker: marker, raw: raw))
        }
        return refs
    }

    private static func authorYear(_ body: String) -> [PaperReference] {
        let lines = body.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var blocks: [String] = []
        var current = ""
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let starts = trimmed.range(of: #"^[A-Z][A-Za-z\-]+.*,?\s*\(\d{4}"#, options: .regularExpression) != nil
            if starts, !current.isEmpty {
                blocks.append(current.trimmingCharacters(in: .whitespacesAndNewlines))
                current = trimmed
            } else if !trimmed.isEmpty {
                current = current.isEmpty ? trimmed : current + " " + trimmed
            }
        }
        if !current.isEmpty { blocks.append(current.trimmingCharacters(in: .whitespacesAndNewlines)) }
        return blocks.compactMap { block in
            guard let yearMatch = block.firstMatch(of: #/\((\d{4}[a-z]?)\)/#) else { return nil }
            let year = String(yearMatch.1)
            let author = block.split(separator: "(").first.map { $0.trimmingCharacters(in: .whitespaces.union(.punctuationCharacters)) } ?? ""
            return enrich(marker: "\(author.split(separator: ",").first ?? "") \(year)", raw: block, year: year, authors: author)
        }
    }

    private static func enrich(marker: String, raw: String, year: String? = nil, authors: String? = nil) -> PaperReference {
        var year = year
        if year == nil, let match = raw.firstMatch(of: #/\b(19|20)\d{2}\b/#) {
            year = String(match.0)
        }
        var doi: String?
        if let match = raw.firstMatch(of: #/10\.\d{4,9}\/[^\s,]+/#) {
            doi = String(match.0).trimmingCharacters(in: CharacterSet(charactersIn: ".,;)"))
        }
        var arxiv: String?
        if let match = raw.firstMatch(of: #/(?i)arXiv[:\s]+(\d{4}\.\d{4,5})/#) {
            arxiv = String(match.1)
        }
        let title = inferredTitle(from: raw)
        return PaperReference(
            marker: marker,
            raw: raw,
            title: title,
            authors: authors ?? inferredAuthors(from: raw),
            year: year,
            arxivID: arxiv,
            doi: doi
        )
    }

    private static func inferredTitle(from raw: String) -> String? {
        if let quoted = raw.firstMatch(of: #/[“"]([^”"]{8,})[”"]/#) {
            return String(quoted.1)
        }
        let stripped = raw.replacingOccurrences(of: #"^\[\d+\]\s*"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"^\d+\.\s*"#, with: "", options: .regularExpression)
        let parts = stripped.split(separator: ".", maxSplits: 3, omittingEmptySubsequences: true).map {
            $0.trimmingCharacters(in: .whitespaces)
        }
        if parts.count >= 2, parts[1].count > 8 { return parts[1] }
        return parts.last(where: { $0.count > 12 })
    }

    private static func inferredAuthors(from raw: String) -> String? {
        let stripped = raw.replacingOccurrences(of: #"^\[\d+\]\s*"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"^\d+\.\s*"#, with: "", options: .regularExpression)
        guard let first = stripped.split(separator: ".", maxSplits: 1).first else { return nil }
        let authors = first.trimmingCharacters(in: .whitespaces)
        return authors.count > 2 ? authors : nil
    }
}
