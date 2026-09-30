import SwiftUI

struct LocalModelsView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable private var manager = ModelManager.shared
    @State private var huggingFaceURL = ""
    @State private var addError: String?
    #if DEBUG
    @State private var testOutput = ""
    @State private var testTPS: Double?
    @State private var isTestRunning = false
    #endif

    var body: some View {
        NavigationStack {
            List {
                ForEach(manager.allEntries) { entry in
                    modelRow(entry)
                }
                Section {
                    TextField("https://…/model.gguf", text: $huggingFaceURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("Add from Hugging Face URL") { addCustom() }
                    if let addError {
                        Text(addError).font(.footnote).foregroundStyle(Theme.danger)
                    }
                } header: {
                    Text("Custom model")
                }
                #if DEBUG
                if !ScreenshotMode.isActive {
                Section {
                    Button(isTestRunning ? "Running…" : "Run test prompt") {
                        Task { await runTestPrompt() }
                    }
                    .disabled(isTestRunning || manager.activeModelURL == nil)
                    if let testTPS {
                        Text(String(format: "%.1f tok/s", testTPS))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(Theme.inkSoft)
                    }
                    if !testOutput.isEmpty {
                        Text(testOutput)
                            .font(.caption)
                            .textSelection(.enabled)
                    }
                } header: {
                    Text("Debug")
                }
                }
                #endif
            }
            .navigationTitle("Local models")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task { manager.refreshStates() }
            .onAppear { manager.refreshStates() }
        }
    }

    @ViewBuilder
    private func modelRow(_ entry: ModelCatalogEntry) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(entry.name).font(.headline)
                Spacer()
                if manager.isActive(entry) {
                    Text("Active")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Theme.accent.opacity(0.15), in: .capsule)
                }
            }
            HStack {
                Text(entry.formattedSize).font(.caption).foregroundStyle(Theme.inkSoft)
                if entry.hasVision {
                    Text("· vision").font(.caption).foregroundStyle(Theme.inkSoft)
                }
                if let note = entry.note {
                    Text("· \(note)").font(.caption).foregroundStyle(Theme.inkSoft)
                }
            }
            if entry.mayExceedMemoryOn8GB {
                Label("May exceed memory on 8 GB iPads", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(Theme.danger)
            } else if manager.warnsAboutRAM(for: entry) {
                Label("Large for this iPad’s memory", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(Theme.danger)
            }
            Text(stateLabel(for: manager.state(for: entry)))
                .font(.footnote)
                .foregroundStyle(Theme.inkSoft)
            HStack {
                switch manager.state(for: entry) {
                case .notDownloaded, .failed:
                    Button("Download") { manager.startDownload(entry) }
                        .disabled(!manager.canStartDownload(for: entry))
                case .downloading(let progress):
                    Button("Cancel") { manager.cancelDownload(entry) }
                    ProgressView(value: progress)
                case .ready:
                    Button("Delete", role: .destructive) { manager.delete(entry) }
                    Button("Use") { manager.use(entry) }
                        .disabled(manager.isActive(entry))
                    if entry.hasVision, !manager.hasProjector(entry) {
                        Button("Download vision (\(entry.formattedProjectorSize))") {
                            manager.startDownload(entry)
                        }
                    }
                }
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 4)
    }

    private func stateLabel(for state: ModelDownloadState) -> String {
        switch state {
        case .notDownloaded: "Not downloaded"
        case .downloading(let progress): "Downloading \(Int(progress * 100))%"
        case .ready: "Ready"
        case .failed(let message): message
        }
    }

    private func addCustom() {
        addError = nil
        do {
            let entry = try manager.addFromHuggingFaceURL(huggingFaceURL)
            huggingFaceURL = ""
            manager.startDownload(entry)
        } catch {
            addError = error.localizedDescription
        }
    }

    #if DEBUG
    private func runTestPrompt() async {
        guard let url = manager.activeModelURL else { return }
        isTestRunning = true
        testOutput = ""
        testTPS = nil
        defer { isTestRunning = false }
        do {
            try await LlamaRunner.shared.load(
                modelURL: url,
                nCtx: manager.activeEntry?.nCtx ?? 4096,
                projectorURL: manager.activeProjectorURL,
                promptFormat: manager.activeEntry?.promptFormat
            )
            var text = ""
            for try await piece in await LlamaRunner.shared.generateChat(
                system: "You are a helpful assistant.",
                user: "Say hello in one short sentence."
            ) {
                switch piece {
                case .text(let token): text += token
                case .finished(let metrics): testTPS = metrics.tokensPerSecond
                }
            }
            testOutput = ThinkingStrip.strip(text, usesThinking: manager.activeEntry?.usesThinking ?? false)
        } catch {
            testOutput = error.localizedDescription
        }
    }
    #endif
}
