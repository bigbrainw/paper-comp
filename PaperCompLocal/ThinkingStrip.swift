import Foundation

/// Removes reasoning blocks from model output. Always on: Gemma 4 can emit `<think>` or a thought
/// channel even with thinking disabled. `usesThinking` only gates Qwen's `/no_think` suffix.
enum ThinkingStrip {
    private static let tagPairs: [(String, String)] = [
        ("<\("think")>", "</\("think")>"),
        ("<\("redacted_thinking")>", "</\("redacted_thinking")>"),
        ("<|channel>", "<channel|>"),
    ]

    static func strip(_ text: String, usesThinking: Bool = false) -> String {
        var result = text
        for (open, close) in tagPairs {
            // A close tag with no opener (template pre-opened the block): drop everything before it.
            if let end = result.range(of: close),
               result.range(of: open, range: result.startIndex..<end.lowerBound) == nil {
                result.removeSubrange(result.startIndex..<end.upperBound)
            }
            while let start = result.range(of: open) {
                if let end = result.range(of: close, range: start.upperBound..<result.endIndex) {
                    result.removeSubrange(start.lowerBound..<end.upperBound)
                } else {
                    // Unterminated (still streaming): hide everything after the opener.
                    result.removeSubrange(start.lowerBound...)
                    break
                }
            }
        }
        // Mid-stream partial opener such as "<thi": hide until it resolves.
        for (open, _) in tagPairs {
            if let partial = (2..<open.count).reversed().first(where: { result.hasSuffix(open.prefix($0)) }) {
                result.removeLast(partial)
                break
            }
        }
        let collapsed = result.replacingOccurrences(
            of: #"[ \t]{2,}"#,
            with: " ",
            options: .regularExpression
        )
        return collapsed.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// `/no_think` is Qwen-only, gated by the catalog `usesThinking` flag.
    static func userSuffix(disableThinking: Bool, usesThinking: Bool) -> String {
        guard disableThinking, usesThinking else { return "" }
        return " /no_think"
    }

    static func userSuffixForQwen(disableThinking: Bool, modelID: String) -> String {
        userSuffix(disableThinking: disableThinking, usesThinking: modelID.lowercased().contains("qwen"))
    }
}
