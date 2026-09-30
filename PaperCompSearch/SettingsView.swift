import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SearchSettings.modelKey) private var model = SearchSettings.defaultModel
    @AppStorage(OpenAIReasoningEffort.storageKey) private var reasoningEffort = OpenAIReasoningEffort.default.rawValue
    @AppStorage("allowFingerDrawing") private var allowFingerDrawing: Bool = {
        #if targetEnvironment(simulator)
        true
        #else
        false
        #endif
    }()
    @AppStorage("showSearchMarkers") private var showSearchMarkers = true
    @AppStorage("eraserMode") private var eraserMode = "pixel"
    @AppStorage("toolbarPosition") private var toolbarPosition = "top"
    @AppStorage(SearchEnginePreference.storageKey) private var searchEngine = SearchEnginePreference.onDevice.rawValue
    @AppStorage(OpenAISpend.capKey) private var spendCap = OpenAISpend.defaultCapDollars
    @AppStorage(OpenAISpend.usedKey) private var spendUsed = 0.0
    @AppStorage(OpenAISpend.monthKey) private var spendMonth = ""
    @AppStorage("selectionShape") private var selectionShape = "box"
    @AppStorage(SearchCardStyle.storageKey) private var searchCardStyle = SearchCardStyle.defaultValue.rawValue
    @AppStorage(ConsensusSettings.enabledKey) private var useConsensus = true
    @State private var consensusBusy = false
    @State private var consensusMessage: String?
    @State private var consensusConnected = false
    @AppStorage(OpenAIConsent.storageKey) private var openAIConsent = false
    @State private var keyDraft = ""
    @State private var keyStatus: KeyStatus?
    @State private var keyBusy = false
    private var keyStore: OpenAIKeyStore { OpenAIKeyStore.shared }
    private var hasKey: Bool { keyStore.hasKey }

    private struct KeyStatus: Equatable {
        var text: String
        var isError: Bool
    }

    #if DEBUG
    @State private var screenshotShowsLocalModels = ScreenshotMode.modelReady
    #endif

    init() {}

    private var spendDisplayUsed: Double {
        OpenAISpend.ledger().used
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SearchSegmentedToggle(
                        options: SearchEnginePreference.visibleCases.map { ($0.rawValue, $0.label) },
                        selection: $searchEngine
                    )
                    if hasKey {
                        Text("Used this month: \(OpenAISpend.usdString(spendDisplayUsed)) of \(OpenAISpend.usdString(spendCap))")
                            .font(.footnote)
                            .foregroundStyle(Theme.ink)
                        HStack {
                            Text("Monthly GPT limit")
                            Spacer()
                            TextField("5", value: $spendCap, format: .number.precision(.fractionLength(0...2)))
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 72)
                                .modifier(FieldCard())
                        }
                    }
                } header: {
                    header("Search engine")
                } footer: {
                    footer(hasKey
                        ? "Local model is free and private. Auto uses it when a model is ready, otherwise GPT. You can re-run any answer with GPT from the card. The monthly limit is an estimate that stops GPT requests once reached."
                        : "Local model runs a downloaded GGUF on this iPad. Add your own OpenAI key below to also use GPT.")
                }
                .listRowBackground(Theme.riceSurface)

                Section {
                    Toggle("Use Consensus for paper search", isOn: $useConsensus)
                        .tint(Theme.accent)
                    if consensusConnected {
                        if let email = ConsensusAuth.shared.connectedEmail {
                            Text(email).font(.footnote).foregroundStyle(Theme.ink)
                        } else {
                            Text("Connected (free account)").font(.footnote).foregroundStyle(Theme.inkSoft)
                        }
                        Button("Disconnect") {
                            Task { await toggleConsensus() }
                        }
                        .buttonStyle(SearchCapsuleButtonStyle())
                        .disabled(consensusBusy)
                    } else {
                        Button("Connect") {
                            Task { await toggleConsensus() }
                        }
                        .buttonStyle(SearchCapsuleButtonStyle(prominent: true))
                        .disabled(consensusBusy)
                    }
                    if consensusBusy { ProgressView().controlSize(.mini).tint(Theme.accent) }
                    if let consensusMessage {
                        Text(consensusMessage).font(.footnote).foregroundStyle(Theme.inkSoft)
                    }
                } header: {
                    header("Consensus (free account)")
                } footer: {
                    footer("Sign in with a free Consensus account to search papers there. Without a connection, PaperComp uses Semantic Scholar, OpenAlex, and arXiv. Limits fall back to those sources.")
                }
                .listRowBackground(Theme.riceSurface)

                Section {
                    NavigationLink("Local models") { LocalModelsView() }
                    #if DEBUG
                        .navigationDestination(isPresented: $screenshotShowsLocalModels) { LocalModelsView() }
                    #endif
                } header: {
                    header("On-device models")
                } footer: {
                    footer("Download and manage GGUF models for offline search.")
                }
                .listRowBackground(Theme.riceSurface)

                Section {
                    openAIKeyRows
                    if hasKey {
                        Toggle("Allow sending selections to OpenAI", isOn: $openAIConsent)
                            .tint(Theme.accent)
                            .accessibilityIdentifier("settings.openai.consent")
                        TextField("Model", text: $model)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .modifier(FieldCard())
                        Button("Reset to \(SearchSettings.defaultModel)") { model = SearchSettings.defaultModel }
                            .buttonStyle(SearchCapsuleButtonStyle())
                            .disabled(model == SearchSettings.defaultModel)
                        Text("Effort")
                            .font(.subheadline)
                            .foregroundStyle(Theme.ink)
                        SearchSegmentedToggle(
                            options: OpenAIReasoningEffort.allCases.map { ($0.rawValue, $0.pillLabel) },
                            selection: $reasoningEffort
                        )
                        .onAppear {
                            reasoningEffort = OpenAIReasoningEffort.resolved(reasoningEffort).rawValue
                        }
                        Text("Higher effort = better reasoning, slower and costs more")
                            .font(.footnote)
                            .foregroundStyle(Theme.inkSoft)
                    }
                } header: {
                    header("GPT (your own OpenAI key)")
                } footer: {
                    openAIFooter
                }
                .listRowBackground(Theme.riceSurface)

                Section {
                    Toggle("Draw with finger", isOn: $allowFingerDrawing)
                        .tint(Theme.accent)
                } header: {
                    header("Apple Pencil")
                } footer: {
                    footer("Off: only Apple Pencil draws; your finger scrolls and zooms. On: your finger draws too; scroll with two fingers. Search works either way: drag one finger or the Pencil to box, and scroll with two fingers.")
                }
                .listRowBackground(Theme.riceSurface)

                Section {
                    LabeledContent("Default eraser") {
                        SearchSegmentedToggle(options: [("pixel", "Pixel"), ("stroke", "Stroke")],
                                              selection: $eraserMode)
                            .frame(width: 200)
                    }
                } header: {
                    header("Eraser")
                } footer: {
                    footer("Pixel erases only what you touch. Stroke removes whole strokes. The toolbar remembers your last choice.")
                }
                .listRowBackground(Theme.riceSurface)

                Section {
                    LabeledContent("Toolbar position") {
                        SearchSegmentedToggle(options: [("top", "Top"), ("left", "Left")],
                                              selection: $toolbarPosition)
                            .frame(width: 200)
                    }
                    Toggle("Show search markers", isOn: $showSearchMarkers)
                        .tint(Theme.accent)
                    LabeledContent("Selection shape") {
                        SearchSegmentedToggle(options: [("box", "Box"), ("freeform", "Freeform")],
                                              selection: $selectionShape)
                            .frame(width: 220)
                    }
                    LabeledContent("Search card style") {
                        SearchSegmentedToggle(options: [("dark", "Dark"), ("light", "Light")],
                                              selection: $searchCardStyle)
                            .frame(width: 200)
                    }
                } header: {
                    header("Reader")
                } footer: {
                    footer("Box draws a rectangle for search; freeform uses a lasso. Dark card is espresso so it sits above the paper; Light keeps rice paper with an accent border.")
                }
                .listRowBackground(Theme.riceSurface)

                aboutSection
            }
            .buttonStyle(.plain)
            .toggleStyle(.switch)
            .listSectionSpacing(20)
            .scrollContentBackground(.hidden)
            .background(Theme.rice)
            .foregroundStyle(Theme.ink)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.rice, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Settings").font(.headline).foregroundStyle(Theme.ink)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                        .foregroundStyle(Theme.accent)
                }
            }
            .onAppear {
                if !hasKey {
                    searchEngine = SearchEnginePreference.onDevice.rawValue
                }
                let ledger = OpenAISpend.ledger()
                spendMonth = ledger.month
                spendUsed = ledger.used
                if spendCap <= 0 { spendCap = OpenAISpend.defaultCapDollars }
                consensusConnected = ConsensusAuth.shared.isConnected
            }
        }
        .tint(Theme.accent)
        .fontDesign(.rounded)
    }

    private var aboutSection: some View {
        Section {
            NavigationLink("Privacy Policy") {
                AppPageView(title: "Privacy Policy", resource: AppLinks.privacyResource, hostedURL: AppLinks.privacyURL)
            }
            .accessibilityIdentifier("settings.about.privacy")
            NavigationLink("Support") {
                AppPageView(title: "Support", resource: AppLinks.supportResource, hostedURL: AppLinks.supportURL)
            }
            .accessibilityIdentifier("settings.about.support")
            LabeledContent("Version") {
                Text(AppLinks.versionString).foregroundStyle(Theme.inkSoft)
            }
        } header: {
            header("About")
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                Text(SamplePaper.attribution)
                HStack(spacing: 14) {
                    Link("arXiv:\(SamplePaper.arXivID)", destination: SamplePaper.abstractURL)
                    Link("License (\(SamplePaper.licenseName))", destination: SamplePaper.licenseURL)
                }
                .foregroundStyle(Theme.accent)
            }
            .foregroundStyle(Theme.inkSoft)
        }
        .listRowBackground(Theme.riceSurface)
    }

    private func header(_ text: String) -> some View {
        Text(text).foregroundStyle(Theme.inkSoft)
    }

    private func footer(_ text: String) -> some View {
        Text(text).foregroundStyle(Theme.inkSoft)
    }

    @ViewBuilder
    private var openAIKeyRows: some View {
        VStack(alignment: .leading, spacing: 10) {
            SecureField(hasKey ? "Saved. Paste a new key to replace it" : "OpenAI API key", text: $keyDraft)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .textContentType(.password)
                .submitLabel(.done)
                .onSubmit(saveKey)
                .modifier(FieldCard())
                .accessibilityLabel("OpenAI API key")
                .accessibilityIdentifier("settings.openai.key")
            HStack(spacing: 10) {
                Button("Save", action: saveKey)
                    .buttonStyle(SearchCapsuleButtonStyle(prominent: true))
                    .disabled(OpenAIKeyStore.normalized(keyDraft) == nil || keyBusy)
                    .accessibilityIdentifier("settings.openai.save")
                Button("Test key") { Task { await testKey() } }
                    .buttonStyle(SearchCapsuleButtonStyle())
                    .disabled((OpenAIKeyStore.normalized(keyDraft) == nil && !hasKey) || keyBusy)
                    .accessibilityIdentifier("settings.openai.test")
                if hasKey {
                    Button("Remove", role: .destructive, action: removeKey)
                        .buttonStyle(SearchCapsuleButtonStyle(role: .destructive))
                        .disabled(keyBusy)
                        .accessibilityIdentifier("settings.openai.remove")
                }
                if keyBusy { ProgressView().controlSize(.mini).tint(Theme.accent) }
                Spacer(minLength: 0)
                if hasKey {
                    Label("Key saved", systemImage: "checkmark.seal")
                        .font(.footnote)
                        .foregroundStyle(Theme.inkSoft)
                }
            }
            if let keyStatus {
                Text(keyStatus.text)
                    .font(.footnote)
                    .foregroundStyle(keyStatus.isError ? Theme.danger : Theme.inkSoft)
                    .accessibilityIdentifier("settings.openai.status")
            }
        }
        .environment(\.searchCardPalette, .light)
        .padding(.vertical, 4)
    }

    private var openAIFooter: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Optional. Without a key, every search uses the local model. Your key stays on this iPad in the Keychain and is never synced. Requests go straight from this iPad to OpenAI and are billed to your OpenAI account.")
            if hasKey {
                Text("Model must support vision and the web_search tool in the Responses API.")
            }
            Link("Get a key at platform.openai.com/api-keys",
                 destination: URL(string: "https://platform.openai.com/api-keys")!)
                .foregroundStyle(Theme.accent)
        }
        .foregroundStyle(Theme.inkSoft)
    }

    private func saveKey() {
        guard let value = OpenAIKeyStore.normalized(keyDraft) else { return }
        do {
            try keyStore.save(value)
            keyDraft = ""
            keyStatus = KeyStatus(text: "Saved to this iPad's Keychain.", isError: false)
        } catch {
            keyStatus = KeyStatus(text: "Couldn't save the key: \(error.localizedDescription)", isError: true)
        }
    }

    private func removeKey() {
        do {
            try keyStore.remove()
            keyDraft = ""
            searchEngine = SearchEnginePreference.onDevice.rawValue
            keyStatus = KeyStatus(text: "Key removed. Searches use the local model.", isError: false)
        } catch {
            keyStatus = KeyStatus(text: "Couldn't remove the key: \(error.localizedDescription)", isError: true)
        }
    }

    private func testKey() async {
        guard let candidate = OpenAIKeyStore.normalized(keyDraft) ?? keyStore.key else { return }
        keyBusy = true
        defer { keyBusy = false }
        let result = await OpenAIKeyTester.test(key: candidate)
        keyStatus = KeyStatus(text: result.message, isError: result != .ok)
    }

    private func toggleConsensus() async {
        consensusBusy = true
        defer { consensusBusy = false }
        if consensusConnected {
            ConsensusAuth.shared.disconnect()
            consensusConnected = false
            consensusMessage = "Disconnected."
            return
        }
        do {
            try await ConsensusAuth.shared.connect()
            consensusConnected = ConsensusAuth.shared.isConnected
            let email = ConsensusAuth.shared.connectedEmail
            consensusMessage = email.map { "Signed in as \($0)." } ?? "Signed in with a free Consensus account."
        } catch {
            consensusMessage = error.localizedDescription
        }
    }

}

/// Text field inset in a `riceDeep` rounded card inside a Settings row.
private struct FieldCard: ViewModifier {
    func body(content: Content) -> some View {
        content
            .tint(Theme.accent)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(Theme.riceDeep, in: .rect(cornerRadius: 10, style: .continuous))
    }
}
