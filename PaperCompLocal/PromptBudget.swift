import Foundation

enum PromptBudget {
    /// Legacy default; real calls must use `promptLimit` from the loaded context.
    static let maxTokens = 6_500
    static let margin = 64
    static let minPromptTokens = 256
    /// Estimate when the real tokenizer is unavailable (tests / `#else` stub).
    static let chatTemplateOverhead = 48

    struct Part: Equatable, Sendable {
        var rank: Int
        var text: String
    }

    /// Room left for the formatted prompt: `nCtx − maxGen − imageTokens − margin`.
    static func promptLimit(
        nCtx: Int,
        maxGenTokens: Int,
        imageTokens: Int = 0,
        margin: Int = margin
    ) -> Int {
        max(minPromptTokens, nCtx - maxGenTokens - max(0, imageTokens) - margin)
    }

    /// Hard cap before `llama_decode`: prompt tokens must leave room for generation.
    static func decodeCap(nCtx: Int, maxGenTokens: Int) -> Int {
        max(1, nCtx - maxGenTokens)
    }

    static func estimateTokens(_ text: String) -> Int {
        max(1, (text.utf8.count + 3) / 4)
    }

    /// Drop the front (sources / passages) and keep the tail (question / instruction).
    static func shrinkKeepingTail(_ text: String, scale: Double) -> String {
        let keep = max(200, Int(Double(text.count) * min(1, max(0.1, scale))))
        guard text.count > keep, let start = text.index(text.endIndex, offsetBy: -keep, limitedBy: text.startIndex) else {
            return text
        }
        return "…" + String(text[start...])
    }

    static func trim(_ parts: [Part], limit: Int = maxTokens, countTokens: (String) -> Int = estimateTokens) -> [Part] {
        var kept = parts.sorted { $0.rank < $1.rank }
        func total() -> Int { kept.reduce(0) { $0 + countTokens($1.text) } }
        while total() > limit, kept.count > 1 {
            if let drop = kept.indices.max(by: { kept[$0].rank < kept[$1].rank }) {
                kept.remove(at: drop)
            } else {
                break
            }
        }
        if total() > limit, let last = kept.indices.max(by: { kept[$0].rank < kept[$1].rank }) {
            let budget = max(200, limit - (total() - countTokens(kept[last].text)))
            kept[last].text = LookupFormat.trimmed(kept[last].text, to: budget * 4)
        }
        return kept.sorted { $0.rank < $1.rank }
    }

    static func trim(
        _ parts: [Part],
        limit: Int = maxTokens,
        countTokens: @Sendable (String) async -> Int
    ) async -> [Part] {
        var kept = parts.sorted { $0.rank < $1.rank }
        func total() async -> Int {
            var sum = 0
            for part in kept { sum += await countTokens(part.text) }
            return sum
        }
        while await total() > limit, kept.count > 1 {
            if let drop = kept.indices.max(by: { kept[$0].rank < kept[$1].rank }) {
                kept.remove(at: drop)
            } else {
                break
            }
        }
        if await total() > limit, let last = kept.indices.max(by: { kept[$0].rank < kept[$1].rank }) {
            let lastCount = await countTokens(kept[last].text)
            let budget = max(200, limit - ((await total()) - lastCount))
            kept[last].text = LookupFormat.trimmed(kept[last].text, to: budget * 4)
        }
        return kept.sorted { $0.rank < $1.rank }
    }
}
