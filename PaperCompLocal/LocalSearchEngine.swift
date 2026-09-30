import Foundation
import OSLog
import UIKit

@MainActor
final class LocalLlamaSearchEngine: SearchEngine {
    let kind: SearchEngineKind = .onDevice
    var displayTag: String {
        let name = ModelManager.shared.activeEntry?.shortName ?? "Local model"
        return "\(name) · on-device"
    }

    private let capture: CircleCapture
    private let lookup = KeylessLookup()
    private var ocrText: String?
    private var lastTokensPerSecond: Double?
    private static let teachLog = Logger(subsystem: "com.elijah.papercomp", category: "teach")

    init(capture: CircleCapture) {
        self.capture = capture
    }

    func stream(question: String) -> AsyncThrowingStream<SearchEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task { @MainActor in
                do {
                    try await self.run(question, continuation)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
                LlamaRunner.shared.cancel()
            }
        }
    }

    private func run(_ question: String, _ continuation: AsyncThrowingStream<SearchEvent, Error>.Continuation) async throws {
        guard ModelManager.shared.activeModelURL != nil else {
            throw LlamaRunnerError.notLoaded
        }
        await LlamaRunner.shared.beginRequest()
        do {
            try await ensureRunnerLoaded()
            try await runLoaded(question, continuation)
            await LlamaRunner.shared.endRequest()
        } catch {
            await LlamaRunner.shared.endRequest()
            throw error
        }
    }

    private func ensureRunnerLoaded() async throws {
        if await LlamaRunner.shared.isLoaded {
            try await LlamaRunner.shared.reloadIfUnloaded()
            return
        }
        guard let modelURL = ModelManager.shared.activeModelURL else {
            throw LlamaRunnerError.loadFailed("The local model was unloaded. \(LlamaRunnerError.smallerModelHint)")
        }
        do {
            try await LlamaRunner.shared.load(
                modelURL: modelURL,
                nCtx: ModelManager.shared.activeEntry?.nCtx ?? 4096,
                projectorURL: ModelManager.shared.activeProjectorURL,
                promptFormat: ModelManager.shared.activeEntry?.promptFormat
            )
        } catch let error as LlamaRunnerError {
            throw error
        } catch {
            throw LlamaRunnerError.loadFailed(error.localizedDescription)
        }
    }

    private func runLoaded(_ question: String, _ continuation: AsyncThrowingStream<SearchEvent, Error>.Continuation) async throws {

        let projectorURL = ModelManager.shared.activeProjectorURL
        let circled = await circledText(continuation, hasProjector: projectorURL != nil)
        let sendImage = VisionSendPolicy.shouldSendImage(
            selectedText: circled,
            hasProjector: projectorURL != nil
        )
        let preparedImage = sendImage ? MtmdImagePrep.prepare(capture.image) : nil
        let paper = PaperIndexControllerCache.record(for: capture.documentID)
        let intent = SearchRetrievalIntent.from(question: question)
        let teach = intent == .defineExplain
        var terms: [String] = []
        if teach {
            terms = await detectTerms(passage: circled, continuation: continuation)
            continuation.yield(.detectedTerms(terms))
        }

        continuation.yield(.lookingUp("Fetching sources…"))
        var snippets: [LocalPromptBuilder.SourceSnippet] = []
        var passages: [PaperChunk] = []
        if teach {
            let retrieval = await LocalRetrieval.fetchTerms(
                terms,
                paper: paper,
                paperTitle: capture.paperTitle,
                selection: circled,
                lookup: lookup
            )
            snippets = retrieval.snippets
            passages = retrieval.passages
            for source in retrieval.sources { continuation.yield(.source(source)) }
            if let note = retrieval.note { continuation.yield(.retrievalNote(note)) }
        } else {
            let query: String
            switch intent {
            case .citedPaper:
                query = PaperIndexQuery.citedPaperQuery(selection: circled, record: paper)
            default:
                query = CitationQueryExtractor.keyPhrase(from: circled, fallback: question)
            }
            let retrieval = await LocalRetrieval.fetch(
                intent: intent,
                query: query,
                paper: paper,
                paperTitle: capture.paperTitle,
                selection: circled,
                lookup: lookup
            )
            snippets = retrieval.snippets
            passages = paper.map { PaperIndexQuery.passages(in: $0, selection: circled, question: question) } ?? []
            for source in retrieval.sources { continuation.yield(.source(source)) }
            if let note = retrieval.note { continuation.yield(.retrievalNote(note)) }
        }
        continuation.yield(.searchFinished)

        let cited = paper.map { PaperIndexQuery.citedReferences(in: $0, selection: circled) } ?? []
        let stepQuestion = teach ? rewrittenQuestion(question, terms: terms) : question
        let breakdown = teach && BreakdownMode.shouldRun(stepQuestion)
        let packed = await packRetrieval(
            passages: passages,
            snippets: snippets,
            paper: paper,
            circled: circled,
            question: stepQuestion,
            cited: cited,
            teach: teach,
            terms: terms,
            hasImage: preparedImage != nil,
            maxGenTokens: breakdown ? BreakdownMode.maxTokensPerTerm : 400,
            budgetScale: 1
        )
        passages = packed.passages
        snippets = packed.snippets
        continuation.yield(.paperPassages(passages.map(\.asPassage)))

        let usesThinking = ModelManager.shared.activeEntry?.usesThinking ?? false
        if breakdown {
            let answer = try await runBreakdown(
                question: stepQuestion,
                circled: circled,
                snippets: snippets,
                passages: passages,
                paper: paper,
                image: preparedImage,
                terms: terms,
                usesThinking: usesThinking,
                continuation: continuation
            )
            #if DEBUG
            Self.logTeachDemo(answer, terms: terms)
            #endif
            continuation.yield(.completed(responseID: nil, text: answer))
            return
        }
        var answer = try await generateAnswer(
            circled: circled,
            question: stepQuestion,
            snippets: snippets,
            passages: passages,
            cited: cited,
            paper: paper,
            image: preparedImage,
            teach: teach,
            terms: terms,
            retryCopied: false,
            usesThinking: usesThinking,
            continuation: continuation
        )
        let copySources = [circled, capture.surroundingText]
        if teach, CopyGuard.copies(answer, against: copySources) {
            continuation.yield(.lookingUp("Rewriting in our own words…"))
            answer = try await generateAnswer(
                circled: circled,
                question: stepQuestion,
                snippets: snippets,
                passages: passages,
                cited: cited,
                paper: paper,
                image: preparedImage,
                teach: teach,
                terms: terms,
                retryCopied: true,
                usesThinking: usesThinking,
                continuation: continuation
            )
            if CopyGuard.copies(answer, against: copySources) {
                continuation.yield(.copiedPassage)
            }
        }
        #if DEBUG
        Self.logTeachDemo(answer, terms: terms)
        #endif
        continuation.yield(.completed(responseID: nil, text: answer))
    }

    #if DEBUG
    /// `-PCTeachDemo`: log the answer and write it (with detected terms) to Documents/PCTeachDemo.txt.
    private static func logTeachDemo(_ answer: String, terms: [String]) {
        guard ProcessInfo.processInfo.arguments.contains("-PCTeachDemo") else { return }
        teachLog.notice("PCTeachDemo answer: \(answer, privacy: .public)")
        print("PCTeachDemo answer: \(answer)")
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appending(path: "PCTeachDemo.txt")
        try? "terms: \(terms.joined(separator: " | "))\n\n\(answer)".write(to: url, atomically: true, encoding: .utf8)
    }
    #endif

    private func detectTerms(
        passage: String,
        continuation: AsyncThrowingStream<SearchEvent, Error>.Continuation
    ) async -> [String] {
        continuation.yield(.lookingUp("Finding the hard terms…"))
        let user = HardTermDetector.userPrompt + "\n\nPassage:\n\"\"\"\n\(LookupFormat.trimmed(passage, to: 400))\n\"\"\""
        var output = ""
        do {
            for try await piece in await LlamaRunner.shared.generateChat(
                system: HardTermDetector.system,
                user: user,
                sampler: .detect
            ) {
                if case .text(let token) = piece { output += token }
            }
        } catch {
            return HardTermDetector.fallback(from: passage)
        }
        return HardTermDetector.terms(from: output, passage: passage)
    }

    private func runBreakdown(
        question: String,
        circled: String,
        snippets: [LocalPromptBuilder.SourceSnippet],
        passages: [PaperChunk],
        paper: PaperIndexRecord?,
        image: MtmdPreparedImage?,
        terms: [String],
        usesThinking: Bool,
        continuation: AsyncThrowingStream<SearchEvent, Error>.Continuation
    ) async throws -> String {
        let only = BreakdownMode.singleTerm(from: question)
        let focus = (only.map { [$0] } ?? terms).prefix(BreakdownMode.maxTerms).map { $0 }
        let usable = focus.isEmpty ? HardTermDetector.fallback(from: circled).prefix(BreakdownMode.maxTerms).map { $0 } : focus
        continuation.yield(.detectedTerms(usable))
        var sections: [String] = []
        for (index, term) in usable.enumerated() {
            continuation.yield(.breakdownSectionStart(term: term))
            continuation.yield(.lookingUp("Breaking down \(term)…"))
            let wiki = (index < snippets.count ? snippets[index].body : nil)
                ?? snippets.first(where: { $0.body.localizedCaseInsensitiveContains(term) })?.body
            let passage = passages.first(where: { $0.text.localizedCaseInsensitiveContains(term) })?.text
                ?? (index < passages.count ? passages[index].text : nil)
            let text = try await generateBreakdownSection(
                term: term,
                circled: circled,
                wiki: wiki,
                passage: passage,
                brief: paper?.brief,
                image: image,
                usesThinking: usesThinking,
                continuation: continuation
            )
            sections.append(text)
        }
        var fit = ""
        if only == nil, usable.count > 1 {
            continuation.yield(.breakdownSectionStart(term: BreakdownMode.fitTogetherHeading))
            continuation.yield(.lookingUp("How they fit together…"))
            fit = try await streamChat(
                system: BreakdownMode.fitTogetherSystem,
                user: BreakdownMode.fitTogetherUser(terms: usable, sections: sections),
                image: nil,
                sourceImage: nil,
                sampler: .fitTogether,
                usesThinking: usesThinking,
                onSnapshot: { visible in
                    continuation.yield(.breakdownSectionSnapshot(term: BreakdownMode.fitTogetherHeading, text: visible))
                }
            )
            if BreakdownMode.isMeta(fit) {
                fit = try await streamChat(
                    system: BreakdownMode.fitTogetherSystem,
                    user: BreakdownMode.fitTogetherUser(terms: usable, sections: sections)
                        + "\n\nExplain the concept itself.",
                    image: nil,
                    sourceImage: nil,
                    sampler: .fitTogether,
                    usesThinking: usesThinking,
                    onSnapshot: { visible in
                        continuation.yield(.breakdownSectionSnapshot(term: BreakdownMode.fitTogetherHeading, text: visible))
                    },
                    onVisionNote: { continuation.yield(.retrievalNote(VisionFallback.displayNote(for: $0))) }
                )
            }
        }
        if let tps = lastTokensPerSecond {
            continuation.yield(.metrics(tokensPerSecond: tps))
        }
        return BreakdownMode.assemble(terms: usable, sections: sections, fitTogether: fit)
    }

    private func generateBreakdownSection(
        term: String,
        circled: String,
        wiki: String?,
        passage: String?,
        brief: String?,
        image: MtmdPreparedImage?,
        usesThinking: Bool,
        continuation: AsyncThrowingStream<SearchEvent, Error>.Continuation
    ) async throws -> String {
        let sentences = BreakdownMode.sentences(in: circled, mentioning: term)
        let fitted = await fitBreakdownSources(
            wiki: wiki, passage: passage, brief: brief,
            term: term, sentences: sentences,
            hasImage: image != nil
        )
        func once(retryMeta: Bool) async throws -> String {
            try await streamChat(
                system: BreakdownMode.system,
                user: BreakdownMode.user(
                    term: term,
                    sentences: sentences,
                    wiki: fitted.wiki,
                    passage: fitted.passage,
                    brief: fitted.brief,
                    includesImage: image != nil,
                    retryMeta: retryMeta
                ),
                image: image,
                sourceImage: image != nil ? capture.image : nil,
                sampler: .breakdown,
                usesThinking: usesThinking,
                onSnapshot: { visible in
                    continuation.yield(.breakdownSectionSnapshot(term: term, text: visible))
                },
                onVisionNote: { continuation.yield(.retrievalNote(VisionFallback.displayNote(for: $0))) }
            )
        }
        var text = try await once(retryMeta: false)
        if BreakdownMode.shouldRegenerate(text) {
            text = try await once(retryMeta: true)
        }
        return text
    }

    private func packRetrieval(
        passages: [PaperChunk],
        snippets: [LocalPromptBuilder.SourceSnippet],
        paper: PaperIndexRecord?,
        circled: String,
        question: String,
        cited: [PaperReference],
        teach: Bool,
        terms: [String],
        hasImage: Bool,
        maxGenTokens: Int,
        budgetScale: Double
    ) async -> (passages: [PaperChunk], snippets: [LocalPromptBuilder.SourceSnippet]) {
        let nCtx = await LlamaRunner.shared.nCtx
        let imageTokens = hasImage ? VisionEvalBudget.imageMaxTokens : 0
        let limit = max(
            PromptBudget.minPromptTokens,
            Int(Double(PromptBudget.promptLimit(nCtx: nCtx, maxGenTokens: maxGenTokens, imageTokens: imageTokens)) * budgetScale)
        )
        let skeleton = LocalPromptBuilder.build(
            paperTitle: capture.paperTitle,
            circledText: circled,
            surroundingText: capture.surroundingText,
            question: question,
            snippets: [],
            includesImage: hasImage,
            paperBrief: paper?.brief,
            passages: [],
            references: cited,
            kind: teach ? .teach : .lookup,
            terms: terms,
            retryCopied: false
        )
        let reserved = await LlamaRunner.shared.formattedPromptTokenCount(
            system: skeleton.system,
            user: skeleton.user
        )
        let budgetParts = passages.enumerated().map { PromptBudget.Part(rank: 10 + $0.offset, text: $0.element.text) }
            + snippets.enumerated().map { PromptBudget.Part(rank: 20 + $0.offset, text: $0.element.body) }
        let kept = await PromptBudget.trim(budgetParts, limit: max(64, limit - reserved)) { text in
            await LlamaRunner.shared.tokenCount(text)
        }
        let keptTexts = Set(kept.map(\.text))
        return (
            passages.filter { keptTexts.contains($0.text) },
            snippets.filter { keptTexts.contains($0.body) }
        )
    }

    private func fitBreakdownSources(
        wiki: String?,
        passage: String?,
        brief: String?,
        term: String,
        sentences: String,
        hasImage: Bool
    ) async -> (wiki: String?, passage: String?, brief: String?) {
        let nCtx = await LlamaRunner.shared.nCtx
        let imageTokens = hasImage ? VisionEvalBudget.imageMaxTokens : 0
        let limit = PromptBudget.promptLimit(
            nCtx: nCtx,
            maxGenTokens: BreakdownMode.maxTokensPerTerm,
            imageTokens: imageTokens
        )
        let reservedUser = BreakdownMode.user(
            term: term, sentences: sentences, wiki: nil, passage: nil, brief: nil,
            includesImage: hasImage, retryMeta: false
        )
        let reserved = await LlamaRunner.shared.formattedPromptTokenCount(
            system: BreakdownMode.system,
            user: reservedUser
        )
        var parts: [PromptBudget.Part] = []
        if let brief, !brief.isEmpty { parts.append(.init(rank: 5, text: brief)) }
        if let passage, !passage.isEmpty { parts.append(.init(rank: 10, text: passage)) }
        if let wiki, !wiki.isEmpty { parts.append(.init(rank: 20, text: wiki)) }
        let kept = await PromptBudget.trim(parts, limit: max(64, limit - reserved)) { text in
            await LlamaRunner.shared.tokenCount(text)
        }
        let texts = Set(kept.map(\.text))
        return (
            wiki.flatMap { texts.contains($0) ? $0 : nil },
            passage.flatMap { texts.contains($0) ? $0 : nil },
            brief.flatMap { texts.contains($0) ? $0 : nil }
        )
    }

    private func streamChat(
        system: String,
        user: String,
        image: MtmdPreparedImage?,
        sourceImage: UIImage?,
        sampler: LlamaSamplerSpec,
        usesThinking: Bool,
        onSnapshot: (String) -> Void,
        onVisionNote: ((Error) -> Void)? = nil,
        allowReload: Bool = true
    ) async throws -> String {
        let userMessage = user + ThinkingStrip.userSuffix(disableThinking: true, usesThinking: usesThinking)
        var fullText = ""
        do {
            try await LlamaRunner.shared.reloadIfUnloaded()
            for try await piece in await LlamaRunner.shared.generateChat(
                system: system,
                user: userMessage,
                image: image,
                sourceImage: sourceImage,
                sampler: sampler
            ) {
                try Task.checkCancellation()
                if await LlamaRunner.shared.consumeMemoryPressure(), image != nil {
                    throw LlamaRunnerError.visionFailed(VisionEvalBudget.memorySkipNote)
                }
                switch piece {
                case .text(let token):
                    fullText += token
                    onSnapshot(ThinkingStrip.strip(fullText, usesThinking: usesThinking))
                case .finished(let metrics):
                    lastTokensPerSecond = metrics.tokensPerSecond
                }
            }
        } catch {
            if case .notLoaded = error as? LlamaRunnerError {
                if allowReload {
                    try await ensureRunnerLoaded()
                    return try await streamChat(
                        system: system, user: user, image: nil, sourceImage: nil,
                        sampler: sampler, usesThinking: usesThinking, onSnapshot: onSnapshot,
                        onVisionNote: onVisionNote,
                        allowReload: false
                    )
                }
                throw LlamaRunnerError.loadFailed(
                    "The local model was unloaded. \(LlamaRunnerError.smallerModelHint)"
                )
            }
            guard VisionFallback.shouldRetryTextOnly(error), image != nil else { throw error }
            onVisionNote?(error)
            try await LlamaRunner.shared.reloadIfUnloaded()
            return try await streamChat(
                system: system, user: user, image: nil, sourceImage: nil,
                sampler: sampler, usesThinking: usesThinking, onSnapshot: onSnapshot,
                onVisionNote: onVisionNote
            )
        }
        return ThinkingStrip.strip(fullText, usesThinking: usesThinking)
    }

    private func rewrittenQuestion(_ question: String, terms: [String]) -> String {
        let cleaned = TeachChipPrompt.displayed(question)
        let lower = cleaned.lowercased()
        if BreakdownMode.singleTerm(from: cleaned) != nil { return cleaned }
        if lower.contains("first-year") || lower.contains("undergraduate") {
            return TeachChipPrompt.simpler()
        }
        if lower.hasPrefix("define") {
            return TeachChipPrompt.define(terms: terms)
        }
        if lower.contains("explain") || lower.contains("especially") || lower.contains("breaking down") {
            return TeachChipPrompt.explain(terms: terms)
        }
        return cleaned
    }

    private func generateAnswer(
        circled: String,
        question: String,
        snippets: [LocalPromptBuilder.SourceSnippet],
        passages: [PaperChunk],
        cited: [PaperReference],
        paper: PaperIndexRecord?,
        image: MtmdPreparedImage?,
        teach: Bool,
        terms: [String],
        retryCopied: Bool,
        usesThinking: Bool,
        continuation: AsyncThrowingStream<SearchEvent, Error>.Continuation
    ) async throws -> String {
        do {
            return try await streamAnswer(
                circled: circled,
                question: question,
                snippets: snippets,
                passages: passages,
                cited: cited,
                paper: paper,
                image: image,
                sourceImage: image != nil ? capture.image : nil,
                teach: teach,
                terms: terms,
                retryCopied: retryCopied,
                usesThinking: usesThinking,
                continuation: continuation
            )
        } catch {
            if case .notLoaded = error as? LlamaRunnerError {
                try await ensureRunnerLoaded()
            } else {
                guard VisionFallback.shouldRetryTextOnly(error) else { throw error }
            }
            continuation.yield(.retrievalNote(VisionFallback.displayNote(for: error)))
            try await LlamaRunner.shared.reloadIfUnloaded()
            let text = await textForVisionFallback(circled, continuation)
            return try await streamAnswer(
                circled: text,
                question: question,
                snippets: snippets,
                passages: passages,
                cited: cited,
                paper: paper,
                image: nil,
                sourceImage: nil,
                teach: teach,
                terms: terms,
                retryCopied: retryCopied,
                usesThinking: usesThinking,
                continuation: continuation
            )
        }
    }

    private func streamAnswer(
        circled: String,
        question: String,
        snippets: [LocalPromptBuilder.SourceSnippet],
        passages: [PaperChunk],
        cited: [PaperReference],
        paper: PaperIndexRecord?,
        image: MtmdPreparedImage?,
        sourceImage: UIImage?,
        teach: Bool,
        terms: [String],
        retryCopied: Bool,
        usesThinking: Bool,
        continuation: AsyncThrowingStream<SearchEvent, Error>.Continuation
    ) async throws -> String {
        let built = LocalPromptBuilder.build(
            paperTitle: capture.paperTitle,
            circledText: circled,
            surroundingText: capture.surroundingText,
            question: question,
            snippets: snippets,
            includesImage: image != nil,
            paperBrief: paper?.brief,
            passages: passages,
            references: cited,
            kind: teach ? .teach : .lookup,
            terms: terms,
            retryCopied: retryCopied
        )
        let userMessage = built.user + ThinkingStrip.userSuffix(disableThinking: true, usesThinking: usesThinking)
        var fullText = ""
        do {
            try await LlamaRunner.shared.reloadIfUnloaded()
            for try await piece in await LlamaRunner.shared.generateChat(
                system: built.system,
                user: userMessage,
                image: image,
                sourceImage: sourceImage,
                sampler: teach ? .teach : .brief
            ) {
                try Task.checkCancellation()
                if await LlamaRunner.shared.consumeMemoryPressure(), image != nil {
                    throw LlamaRunnerError.visionFailed(VisionEvalBudget.memorySkipNote)
                }
                switch piece {
                case .text(let token):
                    fullText += token
                    let visible = ThinkingStrip.strip(fullText, usesThinking: usesThinking)
                    continuation.yield(.textSnapshot(visible))
                case .finished(let metrics):
                    lastTokensPerSecond = metrics.tokensPerSecond
                    continuation.yield(.metrics(tokensPerSecond: metrics.tokensPerSecond))
                }
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as LlamaRunnerError {
            if case .notLoaded = error {
                try await ensureRunnerLoaded()
                throw LlamaRunnerError.visionFailed(VisionEvalBudget.memorySkipNote)
            }
            throw error
        } catch {
            throw error
        }
        return ThinkingStrip.strip(fullText, usesThinking: usesThinking)
    }

    private func textForVisionFallback(
        _ circled: String,
        _ continuation: AsyncThrowingStream<SearchEvent, Error>.Continuation
    ) async -> String {
        let trimmed = circled.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        let handwriting = capture.handwritingText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !handwriting.isEmpty { return handwriting }
        if let ocrText, !ocrText.isEmpty { return ocrText }
        continuation.yield(.lookingUp("Reading the selected region…"))
        let recognized = await CaptureOCR.text(in: capture.image)
        ocrText = recognized
        return recognized
    }

    private func circledText(
        _ continuation: AsyncThrowingStream<SearchEvent, Error>.Continuation,
        hasProjector: Bool
    ) async -> String {
        let resolved = CapturePromptText.resolve(
            selectedText: capture.selectedText,
            handwritingText: capture.handwritingText,
            containsInk: capture.containsInk,
            hasProjector: hasProjector
        )
        if resolved.needsVisionCapableModel {
            continuation.yield(.retrievalNote(CapturePromptText.visionRequiredNote))
            return ""
        }
        if !resolved.text.isEmpty { return resolved.text }
        if hasProjector { return "" }
        if let ocrText { return ocrText }
        continuation.yield(.lookingUp("Reading the selected region…"))
        let recognized = await CaptureOCR.text(in: capture.image)
        ocrText = recognized
        return recognized
    }
}

enum LocalModelStatus {
    static let downloadReason = "Download a local model in Settings → Local models to search on-device."

    /// Pure read of cached `ModelManager` state. Never touches disk or mutates observables.
    @MainActor
    static func availability() -> LocalModelAvailability {
        if ModelManager.shared.hasReadyModel {
            if ModelManager.shared.activeModelURL != nil {
                return .available
            }
            return .unavailable(reason: "Choose a downloaded model in Settings → Local models.")
        }
        return .unavailable(reason: downloadReason)
    }

    @MainActor
    static func makeEngine(capture: CircleCapture) -> (any SearchEngine)? {
        guard case .available = availability() else { return nil }
        return LocalLlamaSearchEngine(capture: capture)
    }
}
