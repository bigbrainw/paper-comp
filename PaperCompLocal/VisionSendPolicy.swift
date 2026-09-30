import Foundation

/// When the circled crop should go to Gemma via mtmd.
enum VisionSendPolicy {
    /// Plain-text selections still send the image unless the caller turns this off.
    static let sendImageForPlainTextByDefault = true

    static func isVisualSelection(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return true }
        if trimmed.count < 80 { return true }
        let lines = trimmed.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        if lines.count >= 3, lines.allSatisfy({ $0.count <= 12 }) { return true }
        let lower = trimmed.lowercased()
        if lower.contains("figure") || lower.contains("fig.") { return true }
        if lower.contains("table ") || lower.hasPrefix("table") { return true }
        if lower.contains("equation") || lower.contains("eq.") { return true }
        let math = trimmed.filter { "∑∫√≈≤≥±×÷∈⊂→←αβγθλσμωΔ^=_".contains($0) }
        return math.count >= 3
    }

    static func shouldSendImage(selectedText: String, hasProjector: Bool) -> Bool {
        guard hasProjector else { return false }
        if isVisualSelection(selectedText) { return true }
        return sendImageForPlainTextByDefault
    }
}
