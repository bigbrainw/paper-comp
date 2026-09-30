import Foundation

/// Sampler chain for llama.cpp b11174. Penalties use the five-argument signature
/// `(n_vocab, last_n, repeat, freq, present)`.
struct LlamaSamplerSpec: Equatable, Sendable {
    var temperature: Float
    var topP: Float
    var minP: Float?
    var penaltyLastN: Int32
    var penaltyRepeat: Float
    var penaltyFreq: Float
    var penaltyPresent: Float
    var maxTokens: Int

    /// Step A: short term list.
    static let detect = LlamaSamplerSpec(
        temperature: 0.2, topP: 0.9, minP: nil,
        penaltyLastN: 0, penaltyRepeat: 1.0, penaltyFreq: 0, penaltyPresent: 0,
        maxTokens: 60
    )

    /// Step B: teach, with repetition penalty and min_p.
    static let teach = LlamaSamplerSpec(
        temperature: 0.6, topP: 0.9, minP: 0.05,
        penaltyLastN: 64, penaltyRepeat: 1.15, penaltyFreq: 0, penaltyPresent: 0,
        maxTokens: 400
    )

    /// One term in breakdown mode.
    static let breakdown = LlamaSamplerSpec(
        temperature: 0.6, topP: 0.9, minP: 0.05,
        penaltyLastN: 64, penaltyRepeat: 1.15, penaltyFreq: 0, penaltyPresent: 0,
        maxTokens: BreakdownMode.maxTokensPerTerm
    )

    /// Paper brief and other short non-teaching calls.
    static let brief = LlamaSamplerSpec(
        temperature: 0.3, topP: 0.9, minP: nil,
        penaltyLastN: 0, penaltyRepeat: 1.0, penaltyFreq: 0, penaltyPresent: 0,
        maxTokens: 220
    )

    /// "How they fit together" after per-term sections.
    static let fitTogether = LlamaSamplerSpec(
        temperature: 0.5, topP: 0.9, minP: 0.05,
        penaltyLastN: 64, penaltyRepeat: 1.1, penaltyFreq: 0, penaltyPresent: 0,
        maxTokens: BreakdownMode.fitTogetherMaxTokens
    )

    /// Order applied in `LlamaRunner.makeSampler`.
    var chainSteps: [String] {
        var steps: [String] = []
        if penaltyLastN > 0 { steps.append("penalties") }
        if minP != nil { steps.append("min_p") }
        steps.append("temp")
        steps.append("top_p")
        steps.append("dist")
        return steps
    }
}
