import SwiftUI

/// Content for the floating search card (chrome lives in `FloatingSearchCard`).
struct SearchPanel: View {
    private let capture: CircleCapture
    private let onClose: () -> Void
    private let onAnswered: ((String, String, SearchAnswerProvenance) -> Void)?
    @State private var agent: SearchAgent
    @State private var draft = ""
    @State private var selectedChip: QuickAction?
    private var hasOpenAIKey: Bool { OpenAIKeyStore.shared.hasKey }
    @State private var showLocalModels = false
    @State private var showSettings = false
    @AppStorage(SearchEnginePreference.storageKey) private var searchEngine = SearchEnginePreference.onDevice.rawValue
    @Bindable private var models = ModelManager.shared
    @FocusState private var fieldFocused: Bool
    @Environment(\.searchCardPalette) private var palette
    @Environment(\.searchCardWidth) private var cardWidth

    init(capture: CircleCapture,
         onClose: @escaping () -> Void,
         onAnswered: ((String, String, SearchAnswerProvenance) -> Void)? = nil) {
        self.capture = capture
        self.onClose = onClose
        self.onAnswered = onAnswered
        _agent = State(initialValue: Self.makeAgent(capture, onAnswered))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            CapturePreview(capture: agent.capture)
                .padding(.bottom, 12)
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if models.shouldOfferGemmaUpgrade && agent.question == nil { gemmaUpgradeBanner }
                        else if models.shouldOfferVisionPack && agent.question == nil { visionPackBanner }
                        else if agent.needsLocalModelDownload && agent.question == nil { downloadModelNotice }
                    if !agent.detectedTerms.isEmpty { termChips }
                    if agent.question == nil { chips; questionField(prompt: "Ask about this…") }
                    conversation
                        if agent.question != nil && !agent.status.isBusy {
                            chips
                            questionField(prompt: "Ask a follow-up…")
                        }
                    }
                }
                .scrollContentBackground(.hidden)
                .background(palette.surface)
                .onChange(of: agent.status) { _, status in
                    if status == .done {
                        withAnimation {
                            proxy.scrollTo("search.answer.start", anchor: .top)
                        }
                    }
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(width: cardWidth, alignment: .topLeading)
        .background(palette.surface)
        .background { SearchCardWidthProbe() }
        .accessibilityIdentifier("search.card.content")
        .foregroundStyle(palette.ink)
        .tint(Theme.accent)
        .fontDesign(.rounded)
        .searchCardBusy(agent.status.isBusy)
        .task {
            guard !Self.isUITest, !Self.isScreenshot else { return }
            try? await Task.sleep(for: .milliseconds(250))
            fieldFocused = true
        }
        #if DEBUG
        .task {
            guard let scenario = ScreenshotMode.answerScenario, agent.question == nil else { return }
            try? await Task.sleep(for: .milliseconds(400))
            if let typed = scenario.typedQuestion {
                submit(typed)
            } else {
                let action: QuickAction = scenario == .cited ? .citedPaper : .explain
                selectedChip = action
                submit(action.prompt(selection: capture.selectedText, terms: agent.detectedTerms))
            }
        }
        #endif
        .onChange(of: capture.id) {
            agent.cancel()
            agent = Self.makeAgent(capture, onAnswered)
            draft = ""
            selectedChip = nil
            if !Self.isUITest {
                fieldFocused = true
            }
        }
        .onDisappear { agent.cancel() }
        .sheet(isPresented: $showLocalModels) { LocalModelsView() }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .sheet(isPresented: consentSheetShown) {
            OpenAIConsentSheet(
                onAllow: {
                    OpenAIConsent.grant()
                    agent.resolveOpenAIConsent(allowed: true)
                },
                onDecline: {
                    agent.resolveOpenAIConsent(allowed: false)
                }
            )
        }
        .safariLinkHost()
        .task {
            guard Self.isTeachDemo else { return }
            try? await Task.sleep(for: .milliseconds(400))
            if agent.question == nil {
                submit(TeachChipPrompt.explain(terms: []))
            }
        }
    }

    private var consentSheetShown: Binding<Bool> {
        Binding(
            get: { agent.pendingOpenAIConsent != nil },
            set: { shown in
                if !shown { agent.resolveOpenAIConsent(allowed: false) }
            }
        )
    }

    /// Only offered when the local model can't run and no key is saved, so nobody is stuck.
    private var ownKeyLink: some View {
        Button("Use your own OpenAI key") { showSettings = true }
            .buttonStyle(.plain)
            .font(.caption)
            .foregroundStyle(palette.inkSoft)
            .underline()
            .accessibilityIdentifier("search.byok.link")
    }

    private static func makeAgent(_ capture: CircleCapture,
                                  _ onAnswered: ((String, String, SearchAnswerProvenance) -> Void)?) -> SearchAgent {
        let agent = SearchAgent(capture: capture)
        agent.onAnswered = onAnswered
        return agent
    }

    #if DEBUG
    private static var isUITest: Bool { ProcessInfo.processInfo.arguments.contains("-PCUITest") }
    private static var isTeachDemo: Bool { ProcessInfo.processInfo.arguments.contains("-PCTeachDemo") }
    private static var isScreenshot: Bool { ScreenshotMode.isActive }
    #else
    private static var isUITest: Bool { false }
    private static var isTeachDemo: Bool { false }
    private static var isScreenshot: Bool { false }
    #endif

    private var visibleQuickActions: [QuickAction] {
        QuickAction.allCases.filter { action in
            if action == .readLink {
                return LinkDetector.urlOrDOI(in: capture.selectedText) != nil
            }
            return true
        }
    }

    private var chips: some View {
        SearchFlowLayout(spacing: 8, lineSpacing: 8) {
            ForEach(visibleQuickActions) { action in
                Button(action.title) {
                    selectedChip = action
                    submit(action.prompt(selection: capture.selectedText, terms: agent.detectedTerms))
                }
                .buttonStyle(SearchChipStyle(isSelected: selectedChip == action))
                .fixedSize()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func questionField(prompt: String) -> some View {
        let isEmpty = draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return HStack(spacing: 8) {
            TextField(text: $draft, prompt: Text(prompt).foregroundStyle(palette.inkSoft), axis: .vertical) { Text(prompt) }
                .lineLimit(1...4)
                .focused($fieldFocused)
                .submitLabel(.search)
                .onSubmit(submitDraft)
                .tint(Theme.accent)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(palette.deep, in: .rect(cornerRadius: Theme.cornerRadius, style: .continuous))
            Button(action: submitDraft) {
                Image(systemName: "arrow.up.circle.fill").font(.title2)
            }
            .buttonStyle(.plain)
            .foregroundStyle(isEmpty ? palette.inkSoft : Theme.accent)
            .disabled(isEmpty)
            .accessibilityLabel("Ask")
        }
    }

    @ViewBuilder
    private var conversation: some View {
        ForEach(agent.turns) { turn in
            AnswerBlock(question: turn.question, answer: turn.answer, sources: turn.sources,
                        passages: turn.passages, references: paperReferences,
                        engineTag: turn.engineTag ?? turn.engineKind.tag, tokensPerSecond: nil,
                        showAskGPT: false, onAskGPT: {}, onAskAbout: askAbout)
            Rectangle().fill(palette.deep).frame(height: 0.5)
        }
        if let question = agent.question {
            LiveAnswerChrome(
                question: question,
                sources: agent.sources,
                passages: agent.passages,
                references: paperReferences,
                engineTag: agent.engineDisplayTag ?? agent.engineKind?.tag,
                tokensPerSecond: agent.tokensPerSecond,
                showAskGPT: agent.engineKind == .onDevice && agent.status == .done && hasOpenAIKey,
                onAskGPT: { Task { await agent.askGPTInstead() } },
                onAskAbout: askAbout
            ) {
                if !agent.breakdownSections.isEmpty {
                    BreakdownSectionsView(
                        sections: agent.breakdownSections,
                        references: paperReferences,
                        sources: agent.sources,
                        onAskAbout: askAbout
                    )
                } else {
                    StreamingAnswerText(agent: agent, references: paperReferences, sources: agent.sources,
                                        onAskAbout: askAbout)
                }
            }
            .id("search.answer.start")
            if agent.copiedPassage {
                Text("This answer still follows the passage too closely.")
                    .font(.footnote)
                    .foregroundStyle(palette.inkSoft)
            }
            if let note = agent.retrievalNote {
                Text(note)
                    .font(.footnote)
                    .foregroundStyle(palette.inkSoft)
                    .accessibilityIdentifier(
                        note == VisionFallback.note || note == VisionFallback.memorySkipNote
                            ? "search.vision.note" : "search.consensus.note"
                    )
            }
            if agent.status == .done, ModelManager.shared.activeEntry?.isSmallModel == true, !Self.isScreenshot {
                Button("For deeper explanations try Gemma 4 E4B or GPT") {
                    showLocalModels = true
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(Theme.accent)
                .accessibilityIdentifier("teach.upgrade.hint")
            }
            statusRow
        }
    }

    private var termChips: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(TeachChipPrompt.explain(terms: agent.detectedTerms))
                .font(.caption.weight(.semibold))
                .foregroundStyle(palette.inkSoft)
            SearchFlowLayout(spacing: 8, lineSpacing: 8) {
                ForEach(agent.detectedTerms, id: \.self) { term in
                    Button(term) {
                        submit(TeachChipPrompt.termOnly(term))
                    }
                    .buttonStyle(SearchChipStyle(isSelected: false))
                    .fixedSize()
                }
            }
        }
    }

    @ViewBuilder
    private var statusRow: some View {
        switch agent.status {
        case .thinking, .searching, .streaming:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small).tint(Theme.accent)
                Text(statusText).font(.footnote).foregroundStyle(palette.inkSoft)
                Spacer()
                Button("Stop", systemImage: "stop.fill") { agent.cancel() }
                    .buttonStyle(SearchCapsuleButtonStyle())
            }
        case .failed(let message):
            ErrorBanner(message: message, canRetry: agent.canRetry) { Task { await agent.retry() } }
            if agent.needsLocalModelDownload && !hasOpenAIKey {
                ownKeyLink
            }
        case .idle, .done:
            if agent.canRetry {
                Button("Retry", systemImage: "arrow.clockwise") { Task { await agent.retry() } }
                    .buttonStyle(SearchCapsuleButtonStyle())
            }
        }
    }

    private var statusText: String {
        if let detail = agent.statusDetail { return detail }
        switch agent.status {
        case .searching: return "Searching…"
        case .streaming: return "Writing…"
        default: return "Thinking…"
        }
    }

    private var gemmaUpgradeBanner: some View {
        let gemma = models.catalog.entry(id: ModelCatalogEntry.gemmaE2BId)
        return VStack(alignment: .leading, spacing: 10) {
            Text("Qwen3 1.7B is fast but weak. Gemma 4 E2B is the recommended local model.")
                .font(.footnote)
                .foregroundStyle(palette.ink)
            switch gemma.map(models.state(for:)) {
            case .downloading(let progress):
                ProgressView(value: progress)
                Text("Downloading Gemma 4 E2B… \(Int(progress * 100))%")
                    .font(.caption)
                    .foregroundStyle(palette.inkSoft)
            default:
                Button {
                    models.startGemmaE2BUpgrade()
                } label: {
                    Label("Upgrade to Gemma 4 E2B (\(gemma?.formattedSize ?? "4.1 GB"))", systemImage: "arrow.down.circle")
                        .font(.footnote.weight(.medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.accent)
                .accessibilityIdentifier("upgrade.gemma.e2b")
            }
        }
        .padding(12)
        .frame(maxWidth: cardWidth, alignment: .leading)
        .background(palette.deep, in: .rect(cornerRadius: Theme.cornerRadius, style: .continuous))
    }

    private var visionPackBanner: some View {
        let size = models.activeEntry?.formattedProjectorSize ?? "941 MB"
        return VStack(alignment: .leading, spacing: 10) {
            Text("Download the vision pack so Gemma can see figures, tables, and equations.")
                .font(.footnote)
                .foregroundStyle(palette.ink)
            switch models.activeEntry.map(models.state(for:)) {
            case .downloading(let progress):
                ProgressView(value: progress)
                Text("Downloading vision pack… \(Int(progress * 100))%")
                    .font(.caption)
                    .foregroundStyle(palette.inkSoft)
            default:
                Button {
                    if let entry = models.activeEntry { models.startDownload(entry) }
                } label: {
                    Label("Download vision (\(size))", systemImage: "eye")
                        .font(.footnote.weight(.medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.accent)
                .accessibilityIdentifier("download.vision.pack")
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.deep, in: .rect(cornerRadius: Theme.cornerRadius, style: .continuous))
    }

    private var downloadModelNotice: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                showLocalModels = true
            } label: {
                Label(ModelManager.shared.defaultDownloadCTA, systemImage: "arrow.down.circle")
                    .font(.footnote.weight(.medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.accent)
            if hasOpenAIKey {
                Button("Use GPT") { searchEngine = SearchEnginePreference.openAI.rawValue }
                    .buttonStyle(SearchCapsuleButtonStyle())
            } else {
                ownKeyLink
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.deep, in: .rect(cornerRadius: Theme.cornerRadius, style: .continuous))
    }

    private func submitDraft() {
        guard !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        selectedChip = nil
        submit(draft)
    }

    private func submit(_ text: String) {
        let question = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else { return }
        draft = ""
        fieldFocused = false
        Task { await agent.ask(question) }
    }

    private var paperReferences: [PaperReference] {
        PaperIndexControllerCache.record(for: capture.documentID)?.references ?? []
    }

    private func askAbout(_ reference: PaperReference) {
        let title = reference.title ?? reference.raw
        submit("What is this paper and why does it matter here: \(title)")
    }
}

private enum QuickAction: String, CaseIterable, Identifiable {
    case explain, define, citedPaper, simpler, related, readLink

    var id: Self { self }

    var title: String {
        switch self {
        case .explain: "Explain"
        case .define: "Define"
        case .citedPaper: "Find cited paper"
        case .simpler: "Simpler"
        case .related: "Related work"
        case .readLink: "Read this link"
        }
    }

    func prompt(selection: String, terms: [String] = []) -> String {
        switch self {
        case .explain: return TeachChipPrompt.explain(terms: terms)
        case .define: return TeachChipPrompt.define(terms: terms)
        case .citedPaper: return "Identify the paper cited here and find it on the web: title, authors, year, and a link."
        case .simpler: return TeachChipPrompt.simpler()
        case .related: return "Find related work on this topic, with links."
        case .readLink: return "Read this link and answer from the page content."
        }
    }
}

private struct CapturePreview: View {
    let capture: CircleCapture
    @Environment(\.searchCardPalette) private var palette

    private var isFigureLike: Bool {
        let text = capture.selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return true }
        if text.count < 48 { return true }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true)
        if lines.count >= 3, lines.allSatisfy({ $0.count <= 10 }) { return true }
        return false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Page \(capture.pageIndex + 1) · \(capture.paperTitle)")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(palette.ink)
                .lineLimit(1)
            Image(uiImage: capture.image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity)
                .frame(maxHeight: isFigureLike ? 160 : 140)
                .clipShape(.rect(cornerRadius: 10, style: .continuous))
                .accessibilityLabel("Selected region preview")
            if !capture.selectedText.isEmpty, !isFigureLike {
                Text(capture.selectedText)
                    .font(.callout)
                    .fontDesign(.default)
                    .foregroundStyle(palette.inkSoft)
                    .lineLimit(4)
                    .textSelection(.enabled)
            } else if isFigureLike, !capture.selectedText.isEmpty {
                Text(capture.selectedText)
                    .font(.caption)
                    .fontDesign(.default)
                    .foregroundStyle(palette.inkSoft)
                    .lineLimit(2)
                    .textSelection(.enabled)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.deep, in: .rect(cornerRadius: Theme.cornerRadius, style: .continuous))
    }
}

private struct BreakdownSectionsView: View {
    let sections: [SearchAgent.BreakdownSection]
    var references: [PaperReference] = []
    var sources: [WebSource] = []
    var onAskAbout: ((PaperReference) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(sections) { section in
                BreakdownSectionBlock(
                    section: section,
                    references: references,
                    sources: sources,
                    onAskAbout: onAskAbout
                )
            }
        }
    }
}

private struct BreakdownSectionBlock: View {
    let section: SearchAgent.BreakdownSection
    var references: [PaperReference] = []
    var sources: [WebSource] = []
    var onAskAbout: ((PaperReference) -> Void)?
    @State private var expanded = true
    @Environment(\.searchCardPalette) private var palette

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            if section.text.isEmpty, section.isStreaming {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small).tint(Theme.accent)
                    Text("Writing…").font(.footnote).foregroundStyle(palette.inkSoft)
                }
                .padding(.top, 4)
            } else if !section.text.isEmpty {
                AnswerCitationText(
                    text: section.text,
                    references: references,
                    sources: sources,
                    onAskAbout: onAskAbout
                )
                .padding(.top, 4)
            }
        } label: {
            Text(section.term)
                .font(.headline)
                .foregroundStyle(palette.ink)
        }
        .tint(Theme.accent)
    }
}

/// Reads only `agent.answer` so token streaming does not rebuild the card chrome.
private struct StreamingAnswerText: View {
    let agent: SearchAgent
    var references: [PaperReference] = []
    var sources: [WebSource] = []
    var onAskAbout: ((PaperReference) -> Void)?

    var body: some View {
        if !agent.answer.isEmpty {
            AnswerCitationText(text: agent.answer, references: references, sources: sources, onAskAbout: onAskAbout)
        }
    }
}

private struct LiveAnswerChrome<Answer: View>: View {
    let question: String
    let sources: [WebSource]
    var passages: [PaperPassage] = []
    var references: [PaperReference] = []
    let engineTag: String?
    let tokensPerSecond: Double?
    let showAskGPT: Bool
    let onAskGPT: () -> Void
    var onAskAbout: ((PaperReference) -> Void)?
    @ViewBuilder var answer: () -> Answer
    @Environment(\.searchCardPalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(question)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(palette.ink)
                Spacer(minLength: 0)
                if let engineTag {
                    Text(engineTag)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Theme.accent.opacity(0.12), in: .capsule)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.accent.opacity(0.12), in: .rect(cornerRadius: Theme.cornerRadius, style: .continuous))
            answer()
            if let tokensPerSecond {
                Text(String(format: "%.1f tok/s", tokensPerSecond))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(palette.inkSoft)
            }
            if showAskGPT {
                Button("Ask GPT instead", action: onAskGPT)
                    .buttonStyle(SearchCapsuleButtonStyle())
            }
            AnswerSourcesBlock(passages: passages, sources: sources)
        }
    }
}

private struct AnswerBlock: View {
    let question: String
    let answer: String
    let sources: [WebSource]
    var passages: [PaperPassage] = []
    var references: [PaperReference] = []
    let engineTag: String?
    let tokensPerSecond: Double?
    let showAskGPT: Bool
    let onAskGPT: () -> Void
    var onAskAbout: ((PaperReference) -> Void)?
    @Environment(\.searchCardPalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(question)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(palette.ink)
                Spacer(minLength: 0)
                if let engineTag {
                    Text(engineTag)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Theme.accent.opacity(0.12), in: .capsule)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.accent.opacity(0.12), in: .rect(cornerRadius: Theme.cornerRadius, style: .continuous))
            if !answer.isEmpty {
                AnswerCitationText(text: answer, references: references, sources: sources, onAskAbout: onAskAbout)
            }
            if let tokensPerSecond {
                Text(String(format: "%.1f tok/s", tokensPerSecond))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(palette.inkSoft)
            }
            if showAskGPT {
                Button("Ask GPT instead", action: onAskGPT)
                    .buttonStyle(SearchCapsuleButtonStyle())
            }
            AnswerSourcesBlock(passages: passages, sources: sources)
        }
    }
}

private struct ErrorBanner: View {
    let message: String
    let canRetry: Bool
    let retry: () -> Void
    @Environment(\.searchCardPalette) private var palette

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.danger)
            Text(message).font(.footnote).foregroundStyle(palette.ink)
            Spacer(minLength: 0)
            if canRetry {
                Button("Retry", systemImage: "arrow.clockwise", action: retry)
                    .buttonStyle(SearchCapsuleButtonStyle())
            }
        }
        .padding(12)
        .background(Theme.danger.opacity(0.12), in: .rect(cornerRadius: Theme.cornerRadius, style: .continuous))
    }
}
