import Foundation

enum PaperText {
    static func dehyphenate(_ raw: String) -> String {
        var text = raw.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        text = text.replacingOccurrences(of: #"(\p{L})-\n(\p{L})"#, with: "$1$2", options: .regularExpression)
        text = text.replacingOccurrences(of: #"[ \t]+\n"#, with: "\n", options: .regularExpression)
        return text
    }

    static func clean(_ raw: String) -> String {
        var text = dehyphenate(raw)
        text = text.replacingOccurrences(of: #"(?<!\n)\n(?!\n)"#, with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: #"[ \t]{2,}"#, with: " ", options: .regularExpression)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func sentences(in text: String) -> [String] {
        let cleaned = clean(text)
        guard !cleaned.isEmpty else { return [] }
        let parts = cleaned.split(omittingEmptySubsequences: true, whereSeparator: { ".\n!?".contains($0) })
        return parts.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { $0.count > 2 }
    }

    static func extractiveBrief(abstract: String, introduction: String, sentences: Int = 5) -> String {
        let pool = self.sentences(in: abstract) + self.sentences(in: introduction)
        return pool.prefix(sentences).joined(separator: ". ").appending(pool.isEmpty ? "" : ".")
    }
}

struct PaperStructure: Equatable, Sendable {
    var title: String
    var abstract: String
    var introduction: String
    var headings: [String]
}

enum PaperStructureDetector {
    static func detect(titleHint: String, pages: [String]) -> PaperStructure {
        let joined = pages.map(PaperText.dehyphenate).joined(separator: "\n\n")
        let lines = joined.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let title = titleHint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? (lines.first(where: { $0.count > 8 && $0.count < 180 && !$0.lowercased().hasPrefix("arxiv") }) ?? "Untitled")
            : titleHint
        let headings = lines.filter(isHeading)
        return PaperStructure(
            title: title,
            abstract: section(named: "abstract", in: lines),
            introduction: section(named: "introduction", in: lines),
            headings: headings
        )
    }

    static func isHeading(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.count < 3 || trimmed.count > 80 { return false }
        if trimmed.lowercased().hasPrefix("arxiv") { return false }
        if trimmed.range(of: #"^\d+(\.\d+)*\s+\S"#, options: .regularExpression) != nil { return true }
        let known = ["abstract", "introduction", "references", "bibliography", "conclusion", "related work", "acknowledg"]
        let lower = trimmed.lowercased()
        if known.contains(where: { lower == $0 || lower.hasPrefix($0) }) { return true }
        let letters = trimmed.filter(\.isLetter)
        return !letters.isEmpty && letters.allSatisfy(\.isUppercase) && trimmed.split(separator: " ").count <= 10
    }

    private static func section(named name: String, in lines: [String]) -> String {
        guard let start = lines.firstIndex(where: { isSectionHeader($0, name: name) }) else { return "" }
        var body: [String] = []
        for line in lines.dropFirst(start + 1) {
            if isHeading(line) { break }
            if !line.isEmpty { body.append(line) }
        }
        return PaperText.clean(body.joined(separator: " "))
    }

    private static func isSectionHeader(_ line: String, name: String) -> Bool {
        let lower = line.lowercased()
        if lower == name || lower.hasPrefix(name + " ") { return true }
        return lower.range(of: #"^\d+(\.\d+)*\s+"# + name + #"\b"#, options: .regularExpression) != nil
    }
}

struct PaperChunk: Codable, Equatable, Sendable {
    var pageIndex: Int
    var text: String
}

enum PaperChunker {
    static let targetLength = 700

    static func chunk(pages: [String]) -> [PaperChunk] {
        var chunks: [PaperChunk] = []
        for (index, raw) in pages.enumerated() {
            let cleaned = PaperText.clean(raw)
            guard !cleaned.isEmpty else { continue }
            var current = ""
            for sentence in PaperText.sentences(in: cleaned) {
                if !current.isEmpty, current.count + sentence.count + 2 > targetLength {
                    chunks.append(PaperChunk(pageIndex: index, text: current))
                    current = sentence
                } else {
                    current = current.isEmpty ? sentence : current + ". " + sentence
                }
            }
            if !current.isEmpty { chunks.append(PaperChunk(pageIndex: index, text: current)) }
        }
        return chunks
    }
}
