#if DEBUG
import Foundation

/// DEBUG-only launch arguments for App Store screenshots (`Scripts/appstore-screenshots.sh`).
/// The simulator has no llama.cpp, so `-PCScreenshotAnswer` streams a canned answer through the
/// normal `SearchAgent` → `SearchEvent` path instead of a real engine.
enum ScreenshotMode {
    private static var arguments: [String] { ProcessInfo.processInfo.arguments }

    /// Any `-PCScreenshot…` argument.
    static var isActive: Bool { arguments.contains { $0.hasPrefix("-PCScreenshot") } }

    /// `-PCScreenshotAnswer <explain|figure|cited>`.
    static var answerScenario: ScreenshotAnswerScenario? {
        guard let index = arguments.firstIndex(of: "-PCScreenshotAnswer"),
              arguments.indices.contains(index + 1) else { return nil }
        return ScreenshotAnswerScenario(rawValue: arguments[index + 1])
    }

    /// `-PCScreenshotInk`, `-PCScreenshotNote`, or `-PCScreenshotOverview` (same seed, page list open).
    static var ink: Bool { arguments.contains("-PCScreenshotInk") || overview || notePage }
    /// `-PCScreenshotNote`: same seed, opened on the inserted note page.
    static var notePage: Bool { arguments.contains("-PCScreenshotNote") }
    static var overview: Bool { arguments.contains("-PCScreenshotOverview") }
    static var library: Bool { arguments.contains("-PCScreenshotLibrary") }
    /// `-PCScreenshotModelReady`: Settings → Local models with the default model shown as downloaded.
    static var modelReady: Bool { arguments.contains("-PCScreenshotModelReady") }

    /// Every screenshot pretends the default Gemma model is on disk, so no "Download a local model"
    /// notices appear and on-device answers carry the real engine tag.
    static var pretendsDefaultModelReady: Bool { isActive }
}

enum ScreenshotAnswerScenario: String, Sendable {
    case explain, figure, cited

    /// Page (0-based) the selection is on.
    var pageIndex: Int {
        switch self {
        case .explain, .cited: 0
        case .figure: 1
        }
    }

    /// The boxed region in PDF page space (bottom-left origin), measured from the bundled PDF:
    /// "grouped-query attention (GQA)" in the abstract, Figure 2 above its caption,
    /// and "multi-query attention (Shazeer, 2019)" in the introduction.
    var pageRect: CGRect {
        switch self {
        case .explain: CGRect(x: 106, y: 487, width: 134, height: 14)
        case .figure: CGRect(x: 96, y: 634, width: 412, height: 138)
        case .cited: CGRect(x: 67, y: 279.5, width: 172, height: 15.5)
        }
    }

    /// Typed question for scenarios that don't use a chip.
    var typedQuestion: String? {
        self == .figure ? "What does this figure show?" : nil
    }

    private static let gqaPaper = WebSource(
        title: "GQA: Training Generalized Multi-Query Transformer Models from Multi-Head Checkpoints",
        url: URL(string: "https://arxiv.org/abs/2305.13245")!,
        site: "arxiv.org",
        year: "2023"
    )
    private static let wikiAttention = WebSource(
        title: "Attention (machine learning) — Wikipedia",
        url: URL(string: "https://en.wikipedia.org/wiki/Attention_(machine_learning)")!
    )
    private static let shazeer = WebSource(
        title: "Fast Transformer Decoding: One Write-Head is All You Need",
        url: URL(string: "https://arxiv.org/abs/1911.02150")!,
        site: "arxiv.org",
        year: "2019"
    )

    static let explainTerm = "grouped-query attention"

    static let explainSection = """
        What it is: Grouped-query attention (GQA) sits between multi-head attention (MHA) and multi-query attention (MQA). The query heads are split into G groups, and each group shares a single key head and value head [S1]. With one group it is MQA; with one group per query head it is ordinary MHA.

        Analogy: Instead of every student owning a textbook (MHA) or the whole class sharing one copy (MQA), each table shares a copy.

        Why it's here: Fewer key/value heads shrink the KV cache and the memory bandwidth needed at every decoding step, so GQA reaches quality close to MHA at a speed close to MQA [S1]. The paper also uptrains existing T5 multi-head checkpoints into GQA with about 5% of the original pre-training compute, building each group's key and value head by mean-pooling the original heads.
        """

    static let figureAnswer = """
        Figure 2 compares how the three attention variants share key and value heads across query heads.

        • Multi-head (left): every query head has its own key head and value head, so there are H of each.

        • Grouped-query (middle): the query heads are split into groups, and each group shares a single key and value head. Here 8 query heads form 4 groups of 2.

        • Multi-query (right): all query heads share one key head and one value head.

        GQA interpolates between the two extremes: fewer key/value heads than MHA means a smaller KV cache and faster decoding, while keeping more capacity than MQA's single head [S1].
        """

    static let citedAnswer = """
        This cites “Fast Transformer Decoding: One Write-Head is All You Need” by Noam Shazeer (2019), arXiv:1911.02150 [S1].

        It introduced multi-query attention, where all query heads share one key and value head, which makes incremental decoding much faster with only minor quality loss [S1]. GQA generalizes this idea: MQA is grouped-query attention with a single group.

        Link: https://arxiv.org/abs/1911.02150
        """

    /// The events a real on-device run would stream, ending in `.completed`.
    var events: [SearchEvent] {
        switch self {
        case .explain:
            return [
                .lookingUp("Finding the hard terms…"),
                .detectedTerms([Self.explainTerm]),
                .lookingUp("Fetching sources…"),
                .source(Self.gqaPaper),
                .source(Self.wikiAttention),
                .searchFinished,
                .paperPassages([
                    PaperPassage(pageIndex: 0, text: "Second, we propose grouped-query attention (GQA), an interpolation between multi-head and multi-query attention with single key and value heads per subgroup of query heads."),
                    PaperPassage(pageIndex: 1, text: "Grouped-query attention divides query heads into G groups, each of which shares a single key head and value head."),
                ]),
            ]
        case .figure:
            return [
                .lookingUp("Reading the figure…"),
                .source(Self.gqaPaper),
                .searchFinished,
                .paperPassages([
                    PaperPassage(pageIndex: 1, text: "Figure 2: Overview of grouped-query method. Multi-head attention has H query, key, and value heads."),
                    PaperPassage(pageIndex: 1, text: "Grouped-query attention divides query heads into G groups, each of which shares a single key head and value head."),
                ]),
            ]
        case .cited:
            return [
                .lookingUp("Looking up the cited paper…"),
                .source(Self.shazeer),
                .searchFinished,
                .paperPassages([
                    PaperPassage(pageIndex: 0, text: "The memory bandwidth from loading keys and values can be sharply reduced through multi-query attention (Shazeer, 2019)."),
                    PaperPassage(pageIndex: 5, text: "Noam Shazeer. 2019. Fast transformer decoding: One write-head is all you need. arXiv preprint arXiv:1911.02150."),
                ]),
            ]
        }
    }
}

/// Canned on-device engine: same event stream shape as `LocalLlamaSearchEngine`, no model.
@MainActor
final class ScreenshotSearchEngine: SearchEngine {
    let kind: SearchEngineKind = .onDevice
    var displayTag: String {
        "\(ModelManager.shared.activeEntry?.shortName ?? "Gemma 4 E2B") · on-device"
    }
    private let scenario: ScreenshotAnswerScenario

    init(scenario: ScreenshotAnswerScenario) {
        self.scenario = scenario
    }

    static func makeIfRequested() -> ScreenshotSearchEngine? {
        ScreenshotMode.answerScenario.map(ScreenshotSearchEngine.init)
    }

    func stream(question: String) -> AsyncThrowingStream<SearchEvent, Error> {
        let scenario = scenario
        return AsyncThrowingStream { continuation in
            let task = Task { @MainActor in
                for event in scenario.events {
                    continuation.yield(event)
                    try? await Task.sleep(for: .milliseconds(120))
                }
                if scenario == .explain {
                    let term = ScreenshotAnswerScenario.explainTerm
                    continuation.yield(.breakdownSectionStart(term: term))
                    var shown = ""
                    for chunk in Self.chunks(ScreenshotAnswerScenario.explainSection) {
                        shown += chunk
                        continuation.yield(.breakdownSectionSnapshot(term: term, text: shown))
                        try? await Task.sleep(for: .milliseconds(60))
                    }
                    let full = BreakdownMode.assemble(terms: [term], sections: [shown], fitTogether: "")
                    continuation.yield(.completed(responseID: nil, text: full))
                } else {
                    let text = scenario == .figure
                        ? ScreenshotAnswerScenario.figureAnswer : ScreenshotAnswerScenario.citedAnswer
                    var shown = ""
                    for chunk in Self.chunks(text) {
                        shown += chunk
                        continuation.yield(.textSnapshot(shown))
                        try? await Task.sleep(for: .milliseconds(60))
                    }
                    continuation.yield(.completed(responseID: nil, text: text))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Splits into ~4-word pieces that keep every character, like streamed tokens.
    private static func chunks(_ text: String) -> [String] {
        var pieces: [String] = []
        var current = ""
        var words = 0
        for character in text {
            current.append(character)
            if character == " " || character == "\n" {
                words += 1
                if words == 4 {
                    pieces.append(current)
                    current = ""
                    words = 0
                }
            }
        }
        if !current.isEmpty { pieces.append(current) }
        return pieces
    }
}
#endif
