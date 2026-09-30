import Foundation
import Observation
import UIKit

enum SearchSettings {
    static let modelKey = "openai.model"
    static let defaultModel = "gpt-5.6-luna"

    static var model: String {
        let stored = UserDefaults.standard.string(forKey: modelKey)?.trimmingCharacters(in: .whitespaces)
        return stored?.isEmpty == false ? stored! : defaultModel
    }

    /// Card tag, e.g. "GPT-5.6 Luna".
    static func displayName(for model: String) -> String {
        model == defaultModel ? "GPT-5.6 Luna" : model
    }

    static var displayName: String { displayName(for: model) }

    static let instructions = """
        You are a research assistant helping someone read a paper. \
        Answer the user's question directly, with the answer in the first sentence. \
        Explain the concept itself, using the sources and the paper. \
        Never describe or summarize 'the surrounding text' or 'the circled text'. \
        If the selection is a term, define it and say why it matters in this paper. \
        Use plain text, and write math in Unicode rather than LaTeX. \
        Use web search when the question needs facts beyond the provided snippet, such as cited papers, \
        definitions, or related work. \
        Cite fetched web or paper sources as [S1], [S2] matching the numbered Sources. \
        Cite this paper's own references as [22] or (Author Year). Never use [1] for a web source.
        """
}

/// gpt-5.6-luna `reasoning.effort`. `minimal` is rejected by the API.
enum OpenAIReasoningEffort: String, CaseIterable, Sendable {
    case none, low, medium, high, xhigh

    static let storageKey = "openAIReasoningEffort"
    static let `default` = OpenAIReasoningEffort.medium

    static var current: OpenAIReasoningEffort {
        resolved(UserDefaults.standard.string(forKey: storageKey))
    }

    static func resolved(_ raw: String?) -> OpenAIReasoningEffort {
        raw.flatMap(Self.init(rawValue:)) ?? .medium
    }

    var apiValue: String { rawValue }

    var pillLabel: String {
        switch self {
        case .none: "None"
        case .low: "Low"
        case .medium: "Medium"
        case .high: "High"
        case .xhigh: "X-High"
        }
    }
}

@Observable @MainActor
final class SearchAgent {
    enum Status: Equatable {
        case idle, thinking, searching, streaming, done
        case failed(String)

        var isBusy: Bool { self == .thinking || self == .searching || self == .streaming }
    }

    struct Turn: Identifiable, Equatable {
        let id = UUID()
        let question: String
        let answer: String
        let sources: [WebSource]
        let passages: [PaperPassage]
        let engineKind: SearchEngineKind
        let responseID: String?
        var engineTag: String? = nil
    }

    struct BreakdownSection: Identifiable, Equatable {
        var id: String { term }
        var term: String
        var text: String
        var isStreaming: Bool
    }

    let capture: CircleCapture
    private(set) var question: String?
    private(set) var answer = ""
    private(set) var sources: [WebSource] = []
    private(set) var passages: [PaperPassage] = []
    private(set) var detectedTerms: [String] = []
    private(set) var breakdownSections: [BreakdownSection] = []
    private(set) var copiedPassage = false
    private(set) var retrievalNote: String?
    private(set) var status: Status = .idle
    private(set) var statusDetail: String?
    private(set) var engineKind: SearchEngineKind?
    private(set) var engineDisplayTag: String?
    private(set) var tokensPerSecond: Double?
    private(set) var error: OpenAIError?
    private(set) var turns: [Turn] = []
    /// Set when a request would go to OpenAI before the user has consented; the card shows the sheet.
    private(set) var pendingOpenAIConsent: PendingConsent?

    enum PendingConsent: Equatable {
        /// Routed to OpenAI by the engine setting.
        case route
        /// "Ask GPT instead" on a finished local answer.
        case askGPT
        /// Local model failed in Auto; `message` is the local error to show on "Not now".
        case fallback(message: String)
    }

    @ObservationIgnored var onAnswered: ((String, String, SearchAnswerProvenance) -> Void)?
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var responseID: String?
    @ObservationIgnored private var completed = false
    @ObservationIgnored private let hasOpenAIKey: () -> Bool
    @ObservationIgnored private let hasOpenAIConsent: () -> Bool
    @ObservationIgnored private let preference: () -> SearchEnginePreference
    @ObservationIgnored private var activeEngine: (any SearchEngine)?
    @ObservationIgnored private var openAIEngine: OpenAISearchEngine?
    @ObservationIgnored private var onDeviceFallbackToOpenAI = false
    /// "Not now" on the consent sheet: keep this card on the local model.
    @ObservationIgnored private var declinedOpenAI = false

    init(capture: CircleCapture,
         hasOpenAIKey: @escaping () -> Bool = { OpenAIKeyStore.shared.hasKey },
         hasOpenAIConsent: @escaping () -> Bool = { OpenAIConsent.isGranted() },
         preference: @escaping () -> SearchEnginePreference = { SearchEnginePreference.current }) {
        self.capture = capture
        self.hasOpenAIKey = hasOpenAIKey
        self.hasOpenAIConsent = hasOpenAIConsent
        self.preference = preference
    }

    var canRetry: Bool { question != nil && !status.isBusy && !completed }

    /// No GGUF ready while settings prefer local or auto.
    var needsLocalModelDownload: Bool {
        switch preference() {
        case .openAI: return false
        case .onDevice, .auto: return LocalModelStatus.availability() != .available
        }
    }

    func ask(_ rawQuestion: String) async {
        let text = rawQuestion.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        cancel()
        if let question, completed {
            turns.append(Turn(question: question, answer: answer, sources: sources, passages: passages,
                              engineKind: engineKind ?? .openAI, responseID: responseID,
                              engineTag: engineDisplayTag ?? engineKind?.tag))
        }
        question = TeachChipPrompt.displayed(text)
        await run(mode: .routed)
    }

    func askGPTInstead() async {
        guard question != nil, !status.isBusy else { return }
        guard hasOpenAIKey() else {
            error = .missingKey
            status = .failed(OpenAIError.missingKey.localizedDescription)
            return
        }
        guard hasOpenAIConsent() else {
            pendingOpenAIConsent = .askGPT
            return
        }
        if OpenAISpend.isAtCap() {
            error = .monthlyCapReached
            status = .failed(OpenAIError.monthlyCapReached.localizedDescription)
            return
        }
        openAIEngine = OpenAISearchEngine(capture: capture)
        activeEngine = openAIEngine
        engineKind = .openAI
        await run(mode: .forceOpenAI)
    }

    /// Answer from the consent sheet. The caller stores the consent itself when `allowed`.
    /// Clears the pending state synchronously so the sheet can't answer twice.
    @discardableResult
    func resolveOpenAIConsent(allowed: Bool) -> Task<Void, Never>? {
        guard let pending = pendingOpenAIConsent else { return nil }
        pendingOpenAIConsent = nil
        return Task { await continueAfterConsent(pending, allowed: allowed) }
    }

    private func continueAfterConsent(_ pending: PendingConsent, allowed: Bool) async {
        switch (pending, allowed) {
        case (.route, true):
            await run(mode: .routed)
        case (.route, false):
            declinedOpenAI = true
            await run(mode: .forceLocal)
        case (.askGPT, true):
            await askGPTInstead()
        case (.askGPT, false):
            break
        case (.fallback, true):
            await fallbackToOpenAI()
        case (.fallback(let message), false):
            status = .failed(message)
        }
    }

    func retry() async {
        guard canRetry else { return }
        await run(mode: activeEngine?.kind == .openAI ? .forceOpenAI : .routed)
    }

    func cancel() {
        guard let task else { return }
        task.cancel()
        self.task = nil
        if status.isBusy { status = answer.isEmpty ? .idle : .done }
        statusDetail = nil
    }

    private enum RunMode { case routed, forceOpenAI, forceLocal }

    private func run(mode requested: RunMode) async {
        guard let question else { return }
        let mode: RunMode = requested == .routed && declinedOpenAI ? .forceLocal : requested
        answer = ""
        sources = []
        passages = []
        detectedTerms = []
        if BreakdownMode.singleTerm(from: question) == nil {
            breakdownSections = []
        }
        copiedPassage = false
        retrievalNote = nil
        error = nil
        responseID = nil
        completed = false
        statusDetail = nil
        tokensPerSecond = nil
        engineDisplayTag = nil
        status = .thinking

        do {
            try prepareEngine(mode: mode)
        } catch OpenAIError.consentRequired {
            status = .idle
            pendingOpenAIConsent = .route
            return
        } catch {
            self.error = error as? OpenAIError
            status = .failed(error.localizedDescription)
            return
        }

        guard let engine = activeEngine else {
            status = .failed("No search engine is available.")
            return
        }
        engineKind = engine.kind
        engineDisplayTag = engine.displayTag

        let current = Task { await consume(engine.stream(question: question), allowFallback: onDeviceFallbackToOpenAI) }
        task = current
        await current.value
        if task == current { task = nil }
    }

    private func prepareEngine(mode: RunMode) throws {
        #if DEBUG
        if let canned = ScreenshotSearchEngine.makeIfRequested() {
            activeEngine = canned
            onDeviceFallbackToOpenAI = false
            return
        }
        #endif
        if mode == .forceLocal {
            if activeEngine?.kind == .onDevice { return }
            guard let local = LocalModelStatus.makeEngine(capture: capture) else {
                if case .unavailable(let reason) = LocalModelStatus.availability() {
                    throw OpenAIError.api(reason)
                }
                throw OpenAIError.api("On-device search isn't available on this device.")
            }
            activeEngine = local
            onDeviceFallbackToOpenAI = false
            return
        }
        if mode == .forceOpenAI {
            try requireOpenAI()
            if openAIEngine == nil {
                openAIEngine = OpenAISearchEngine(capture: capture)
            }
            activeEngine = openAIEngine
            onDeviceFallbackToOpenAI = false
            return
        }

        if let activeEngine {
            if activeEngine.kind == .openAI { try requireOpenAI() }
            return
        }

        let route = SearchRouter.route(
            preference: preference(),
            local: LocalModelStatus.availability(),
            hasOpenAIKey: hasOpenAIKey()
        )
        switch route {
        case .openAI:
            try requireOpenAI()
            if openAIEngine == nil {
                openAIEngine = OpenAISearchEngine(capture: capture)
            }
            activeEngine = openAIEngine
            onDeviceFallbackToOpenAI = false
        case .onDevice(let fallback):
            guard let local = LocalModelStatus.makeEngine(capture: capture) else {
                if fallback {
                    try requireOpenAI()
                    if openAIEngine == nil {
                        openAIEngine = OpenAISearchEngine(capture: capture)
                    }
                    activeEngine = openAIEngine
                    onDeviceFallbackToOpenAI = false
                } else {
                    throw OpenAIError.api("On-device search isn't available on this device.")
                }
                return
            }
            activeEngine = local
            onDeviceFallbackToOpenAI = fallback
        case .onDeviceUnavailable(let reason):
            throw OpenAIError.api(reason)
        }
    }

    private func requireOpenAI() throws {
        guard hasOpenAIKey() else { throw OpenAIError.missingKey }
        guard hasOpenAIConsent() else { throw OpenAIError.consentRequired }
        if OpenAISpend.isAtCap() { throw OpenAIError.monthlyCapReached }
    }

    private func consume(_ stream: AsyncThrowingStream<SearchEvent, Error>, allowFallback: Bool) async {
        do {
            for try await event in stream {
                try Task.checkCancellation()
                apply(event)
            }
            try Task.checkCancellation()
            if status.isBusy { status = .done }
            if let question, completed {
                onAnswered?(question, answer, SearchAnswerProvenance(sources: sources, passages: passages))
            }
        } catch is CancellationError {
        } catch let urlError as URLError where urlError.code == .cancelled {
        } catch {
            guard !Task.isCancelled else { return }
            if allowFallback, activeEngine?.kind == .onDevice,
               (error as? LlamaRunnerError)?.prefersCardError != true {
                if hasOpenAIKey(), !hasOpenAIConsent() {
                    status = .idle
                    pendingOpenAIConsent = .fallback(message: error.localizedDescription)
                    return
                }
                await fallbackToOpenAI()
                return
            }
            self.error = error as? OpenAIError
            status = .failed(error.localizedDescription)
        }
    }

    private func fallbackToOpenAI() async {
        guard let question else { return }
        guard hasOpenAIKey() else {
            error = .missingKey
            status = .failed(OpenAIError.missingKey.localizedDescription)
            return
        }
        guard hasOpenAIConsent() else {
            error = .consentRequired
            status = .failed(OpenAIError.consentRequired.localizedDescription)
            return
        }
        if OpenAISpend.isAtCap() {
            error = .monthlyCapReached
            status = .failed(OpenAIError.monthlyCapReached.localizedDescription)
            return
        }
        answer = ""
        sources = []
        passages = []
        detectedTerms = []
        breakdownSections = []
        copiedPassage = false
        retrievalNote = nil
        statusDetail = nil
        status = .thinking
        openAIEngine = OpenAISearchEngine(capture: capture)
        activeEngine = openAIEngine
        engineKind = .openAI
        onDeviceFallbackToOpenAI = false
        await consume(openAIEngine!.stream(question: question), allowFallback: false)
    }

    private func apply(_ event: SearchEvent) {
        switch event {
        case .created(let id):
            if !id.isEmpty { responseID = id }
        case .searching:
            status = .searching
            statusDetail = nil
        case .lookingUp(let message):
            status = .searching
            statusDetail = message
        case .searchFinished:
            if status == .searching { status = .thinking }
            statusDetail = nil
        case .textDelta(let delta):
            answer += delta
            status = .streaming
        case .textSnapshot(let text):
            answer = text
            status = .streaming
        case .source(let source):
            if !sources.contains(where: { $0.url == source.url }) { sources.append(source) }
        case .paperPassages(let value):
            passages = value
        case .detectedTerms(let terms):
            detectedTerms = terms
            if let question {
                let lower = question.lowercased()
                if lower.contains("especially") || lower.contains("hard concepts")
                    || lower.contains("breaking down") {
                    self.question = TeachChipPrompt.explain(terms: terms)
                }
            }
        case .breakdownSectionStart(let term):
            if let index = breakdownSections.firstIndex(where: { $0.term == term }) {
                breakdownSections[index].text = ""
                breakdownSections[index].isStreaming = true
            } else {
                breakdownSections.append(BreakdownSection(term: term, text: "", isStreaming: true))
            }
            status = .streaming
        case .breakdownSectionSnapshot(let term, let text):
            if let index = breakdownSections.firstIndex(where: { $0.term == term }) {
                breakdownSections[index].text = text
                breakdownSections[index].isStreaming = term != BreakdownMode.fitTogetherHeading
            } else {
                breakdownSections.append(BreakdownSection(term: term, text: text, isStreaming: true))
            }
            status = .streaming
        case .copiedPassage:
            copiedPassage = true
        case .retrievalNote(let note):
            retrievalNote = note
        case .metrics(let tokensPerSecond):
            self.tokensPerSecond = tokensPerSecond
        case .usage(let usage):
            OpenAISpend.record(usage)
        case .completed(let id, let text):
            if answer.isEmpty { answer = text }
            if let id, !id.isEmpty { responseID = id }
            for index in breakdownSections.indices {
                breakdownSections[index].isStreaming = false
            }
            completed = true
            status = .done
            statusDetail = nil
        case .failed(let message):
            status = .failed(message)
            statusDetail = nil
        }
    }

    static func prompt(for capture: CircleCapture, question: String) -> String {
        let selected = capture.selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
        let handwriting = capture.handwritingText.trimmingCharacters(in: .whitespacesAndNewlines)
        let context = capture.surroundingText.trimmingCharacters(in: .whitespacesAndNewlines)
        var parts = ["Paper: \(capture.paperTitle.isEmpty ? "Unknown title" : capture.paperTitle)",
                     "Page: \(capture.pageIndex + 1)"]
        if !selected.isEmpty {
            parts.append("Selected passage:\n\"\"\"\n\(selected)\n\"\"\"")
        } else if !handwriting.isEmpty {
            parts.append("Handwriting (OCR):\n\"\"\"\n\(handwriting)\n\"\"\"")
        } else {
            parts.append("Selected passage: a figure or image with no readable text.")
        }
        if !handwriting.isEmpty, !selected.isEmpty {
            parts.append("Handwriting (OCR):\n\"\"\"\n\(handwriting)\n\"\"\"")
        }
        if !context.isEmpty {
            parts.append("Paper context:\n\"\"\"\n\(context)\n\"\"\"")
        }
        parts.append("Question: \(question)")
        return parts.joined(separator: "\n\n")
    }
}

extension UIImage {
    /// JPEG with the longest side at most `maxPixels`, for the vision input.
    func searchJPEG(maxPixels: CGFloat = 1024, quality: CGFloat = 0.8) -> Data? {
        let pixelSize = CGSize(width: size.width * scale, height: size.height * scale)
        guard pixelSize.width > 0, pixelSize.height > 0 else { return nil }
        let ratio = min(1, maxPixels / max(pixelSize.width, pixelSize.height))
        let target = CGSize(width: (pixelSize.width * ratio).rounded(), height: (pixelSize.height * ratio).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: target, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: target))
            draw(in: CGRect(origin: .zero, size: target))
        }
        return image.jpegData(compressionQuality: quality)
    }
}
