import Foundation
import Observation

enum ModelDownloadState: Equatable, Sendable {
    case notDownloaded
    case downloading(progress: Double)
    case ready(url: URL)
    case failed(String)
}

/// Counts disk work and observable writes so tests can prove body/availability stay pure.
enum ModelManagerIOProbe {
    nonisolated(unsafe) static var fileIOCount = 0
    nonisolated(unsafe) static var mutationCount = 0

    static func reset() {
        fileIOCount = 0
        mutationCount = 0
    }
}

@Observable @MainActor
final class ModelManager {
    static let shared = ModelManager()

    static let activeModelKey = "localModel.activeID"
    static let customModelsKey = "localModel.customEntries"
    static let modelsDirectory: URL = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Models", isDirectory: true)

    private(set) var catalog: ModelCatalog
    private(set) var states: [String: ModelDownloadState] = [:]
    private(set) var projectorURLs: [String: URL] = [:]
    private(set) var customEntries: [ModelCatalogEntry] = []
    var activeModelID: String? {
        get {
            #if DEBUG
            if ScreenshotMode.pretendsDefaultModelReady { return ModelCatalogEntry.gemmaE2BId }
            #endif
            return UserDefaults.standard.string(forKey: Self.activeModelKey)
        }
        set {
            let current = UserDefaults.standard.string(forKey: Self.activeModelKey)
            guard newValue != current else { return }
            UserDefaults.standard.set(newValue, forKey: Self.activeModelKey)
        }
    }

    private var activateOnFinish: String?
    private var downloadSession: URLSession!
    private var downloadTasks: [String: URLSessionDownloadTask] = [:]
    private var resumeData: [String: Data] = [:]
    private let delegate = DownloadDelegate()

    private init() {
        catalog = (try? ModelCatalog.loadBundled()) ?? ModelCatalog(models: [])
        customEntries = Self.loadCustomEntries()
        let config = URLSessionConfiguration.background(withIdentifier: "com.elijah.papercomp.model-download")
        config.isDiscretionary = false
        downloadSession = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
        delegate.owner = self
        prepareAtLaunch()
    }

    /// Create the models folder and scan files once — never from a view body.
    func prepareAtLaunch() {
        Self.prepareModelsDirectory()
        refreshStates()
        if activeModelID == nil {
            activeModelID = catalog.defaultModel?.id
        }
    }

    var allEntries: [ModelCatalogEntry] {
        catalog.models + customEntries
    }

    var hasReadyModel: Bool {
        allEntries.contains { entry in
            if case .ready = states[entry.id] { return true }
            return false
        }
    }

    var activeEntry: ModelCatalogEntry? {
        guard let id = activeModelID else { return nil }
        return allEntries.first { $0.id == id }
    }

    var activeModelURL: URL? {
        guard let id = activeModelID, case .ready(let url) = states[id] else { return nil }
        return url
    }

    var activeProjectorURL: URL? {
        guard let id = activeModelID else { return nil }
        return projectorURLs[id]
    }

    func hasProjector(_ entry: ModelCatalogEntry) -> Bool {
        projectorURLs[entry.id] != nil
    }

    func projectorFileURL(for entry: ModelCatalogEntry) -> URL? {
        projectorURLs[entry.id]
    }

    /// Weights are ready but the mmproj is still missing.
    var shouldOfferVisionPack: Bool {
        guard let entry = activeEntry, entry.hasVision else { return false }
        guard case .ready = states[entry.id] else { return false }
        return !hasProjector(entry)
    }

    var defaultDownloadCTA: String {
        let name = catalog.defaultModel?.shortName ?? "Gemma 4 E2B"
        let size = catalog.defaultModel?.formattedSize ?? "4.1 GB"
        return "Download \(name) (\(size))"
    }

    /// Active Qwen 1.7B while Gemma 4 E2B is not on disk.
    var shouldOfferGemmaUpgrade: Bool {
        Self.shouldOfferGemmaUpgrade(activeID: activeModelID, states: states)
    }

    static func shouldOfferGemmaUpgrade(activeID: String?, states: [String: ModelDownloadState]) -> Bool {
        guard activeID == ModelCatalogEntry.qwen17BId else { return false }
        if case .ready = states[ModelCatalogEntry.gemmaE2BId] { return false }
        return true
    }

    func startGemmaE2BUpgrade() {
        guard let gemma = catalog.entry(id: ModelCatalogEntry.gemmaE2BId) else { return }
        activateOnFinish = gemma.id
        startDownload(gemma)
    }

    func refreshStates() {
        ModelManagerIOProbe.fileIOCount += 1
        var next = states
        var nextProjectors = projectorURLs
        for entry in allEntries {
            let fileURL = Self.modelsDirectory.appendingPathComponent(entry.fileName)
            let weightsReady = FileManager.default.fileExists(atPath: fileURL.path)
            if let name = entry.projectorFileName {
                let projector = Self.modelsDirectory.appendingPathComponent(name)
                nextProjectors[entry.id] = FileManager.default.fileExists(atPath: projector.path) ? projector : nil
            } else {
                nextProjectors[entry.id] = nil
            }
            let projectorReady = nextProjectors[entry.id] != nil
            if case .downloading = next[entry.id] {
                if weightsReady, !entry.hasVision || projectorReady {
                    next[entry.id] = .ready(url: fileURL)
                }
                continue
            }
            if weightsReady {
                next[entry.id] = .ready(url: fileURL)
            } else if next[entry.id] == nil {
                next[entry.id] = .notDownloaded
            } else if case .ready = next[entry.id] {
                next[entry.id] = .notDownloaded
            }
        }
        #if DEBUG
        // Screenshots only: show the default model as downloaded (weights + vision) without files.
        if ScreenshotMode.pretendsDefaultModelReady, let gemma = catalog.entry(id: ModelCatalogEntry.gemmaE2BId) {
            next[gemma.id] = .ready(url: Self.modelsDirectory.appendingPathComponent(gemma.fileName))
            if let name = gemma.projectorFileName {
                nextProjectors[gemma.id] = Self.modelsDirectory.appendingPathComponent(name)
            }
        }
        #endif
        if next != states {
            states = next
            ModelManagerIOProbe.mutationCount += 1
        }
        if nextProjectors != projectorURLs {
            projectorURLs = nextProjectors
            ModelManagerIOProbe.mutationCount += 1
        }
    }

    func state(for entry: ModelCatalogEntry) -> ModelDownloadState {
        states[entry.id] ?? .notDownloaded
    }

    func isActive(_ entry: ModelCatalogEntry) -> Bool {
        activeModelID == entry.id
    }

    func use(_ entry: ModelCatalogEntry) {
        guard case .ready = state(for: entry) else { return }
        activeModelID = entry.id
    }

    func warnsAboutRAM(for entry: ModelCatalogEntry) -> Bool {
        if entry.mayExceedMemoryOn8GB { return true }
        let ram = ProcessInfo.processInfo.physicalMemory
        return Double(entry.totalByteSize) > Double(ram) * 0.4
    }

    func freeDiskBytes() -> Int64? {
        let path = Self.modelsDirectory.path
        guard let attrs = try? FileManager.default.attributesOfFileSystem(forPath: path),
              let free = attrs[.systemFreeSize] as? NSNumber else { return nil }
        return free.int64Value
    }

    func canStartDownload(for entry: ModelCatalogEntry) -> Bool {
        let needed = missingDownloadBytes(for: entry)
        if needed == 0 { return true }
        if let free = freeDiskBytes(), free < needed + 50_000_000 { return false }
        return true
    }

    func startDownload(_ entry: ModelCatalogEntry) {
        Self.prepareModelsDirectory()
        guard canStartDownload(for: entry) else {
            assign(entry.id, .failed("Not enough free disk space."))
            return
        }
        cancelDownload(entry)
        let needWeights = !FileManager.default.fileExists(
            atPath: Self.modelsDirectory.appendingPathComponent(entry.fileName).path
        )
        let needProjector = entry.hasVision && projectorFileURL(for: entry) == nil
        guard needWeights || needProjector else {
            refreshStates()
            return
        }
        assign(entry.id, .downloading(progress: 0))
        downloadBytes[entry.id] = [:]
        if needWeights {
            startFileDownload(entry, kind: .weights, url: entry.downloadURLValue)
        } else {
            downloadBytes[entry.id, default: [:]][.weights] = ByteProgress(written: entry.byteSize, expected: entry.byteSize)
        }
        if needProjector, let url = entry.projectorURLValue {
            startFileDownload(entry, kind: .projector, url: url)
        } else if entry.hasVision {
            downloadBytes[entry.id, default: [:]][.projector] = ByteProgress(
                written: entry.projectorByteSize ?? 0,
                expected: entry.projectorByteSize ?? 0
            )
        }
        refreshCombinedProgress(entry.id)
    }

    func cancelDownload(_ entry: ModelCatalogEntry) {
        for kind in DownloadFileKind.allCases {
            let key = Self.taskKey(entry.id, kind)
            if let task = downloadTasks[key] {
                task.cancel(byProducingResumeData: { data in
                    Task { @MainActor in
                        if let data { self.resumeData[key] = data }
                    }
                })
                downloadTasks[key] = nil
            }
        }
        downloadBytes[entry.id] = nil
        if case .downloading = states[entry.id] {
            assign(entry.id, .notDownloaded)
        }
    }

    func delete(_ entry: ModelCatalogEntry) {
        cancelDownload(entry)
        let fileURL = Self.modelsDirectory.appendingPathComponent(entry.fileName)
        ModelManagerIOProbe.fileIOCount += 1
        try? FileManager.default.removeItem(at: fileURL)
        if let name = entry.projectorFileName {
            ModelManagerIOProbe.fileIOCount += 1
            try? FileManager.default.removeItem(at: Self.modelsDirectory.appendingPathComponent(name))
        }
        if activeModelID == entry.id { activeModelID = catalog.defaultModel?.id }
        assign(entry.id, .notDownloaded)
        refreshStates()
        Task { await LlamaRunner.shared.unload() }
    }

    func addFromHuggingFaceURL(_ raw: String) throws -> ModelCatalogEntry {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), url.pathExtension.lowercased() == "gguf" else {
            throw ModelManagerError.invalidURL
        }
        let fileName = url.lastPathComponent
        let id = "custom-\(fileName)"
        let entry = ModelCatalogEntry(
            id: id,
            name: fileName,
            shortName: fileName.replacingOccurrences(of: ".gguf", with: ""),
            downloadURL: trimmed,
            fileName: fileName,
            byteSize: 0,
            isDefault: false
        )
        if !customEntries.contains(where: { $0.id == id }) {
            customEntries.append(entry)
            saveCustomEntries()
        }
        assign(entry.id, .notDownloaded)
        return entry
    }

    var modelsDirectoryURL: URL { Self.modelsDirectory }

    static func prepareModelsDirectory() {
        ModelManagerIOProbe.fileIOCount += 1
        let dir = modelsDirectory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutable = dir
        try? mutable.setResourceValues(values)
    }

    fileprivate func finishDownload(modelID: String, kind: DownloadFileKind, tempURL: URL) {
        guard let entry = allEntries.first(where: { $0.id == modelID }) else { return }
        Self.prepareModelsDirectory()
        let fileName = kind == .weights ? entry.fileName : (entry.projectorFileName ?? "")
        guard !fileName.isEmpty else { return }
        let dest = Self.modelsDirectory.appendingPathComponent(fileName)
        ModelManagerIOProbe.fileIOCount += 1
        try? FileManager.default.removeItem(at: dest)
        do {
            try FileManager.default.moveItem(at: tempURL, to: dest)
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            var mutable = dest
            try mutable.setResourceValues(values)
        } catch {
            assign(modelID, .failed(error.localizedDescription))
            downloadTasks[Self.taskKey(modelID, kind)] = nil
            return
        }
        downloadTasks[Self.taskKey(modelID, kind)] = nil
        let weightsURL = Self.modelsDirectory.appendingPathComponent(entry.fileName)
        let weightsReady = FileManager.default.fileExists(atPath: weightsURL.path)
        let projectorOnDisk: Bool = {
            guard entry.hasVision, let name = entry.projectorFileName else { return true }
            return FileManager.default.fileExists(atPath: Self.modelsDirectory.appendingPathComponent(name).path)
        }()
        let projectorReady = projectorOnDisk
        let stillDownloading = DownloadFileKind.allCases.contains {
            downloadTasks[Self.taskKey(modelID, $0)] != nil
        }
        if weightsReady && projectorReady && !stillDownloading {
            assign(modelID, .ready(url: weightsURL))
            if activateOnFinish == modelID || activeModelID == nil || !hasReadyModel {
                activeModelID = modelID
            }
            if activateOnFinish == modelID { activateOnFinish = nil }
            downloadBytes[modelID] = nil
        }
        refreshStates()
    }

    fileprivate func reportProgress(modelID: String, kind: DownloadFileKind, written: Int64, expected: Int64) {
        var bucket = downloadBytes[modelID] ?? [:]
        bucket[kind] = ByteProgress(written: written, expected: expected)
        downloadBytes[modelID] = bucket
        refreshCombinedProgress(modelID)
    }

    fileprivate func reportFailure(modelID: String, kind: DownloadFileKind, message: String) {
        assign(modelID, .failed(message))
        downloadTasks[Self.taskKey(modelID, kind)] = nil
    }

    private var downloadBytes: [String: [DownloadFileKind: ByteProgress]] = [:]

    private struct ByteProgress {
        var written: Int64
        var expected: Int64
    }

    private func startFileDownload(_ entry: ModelCatalogEntry, kind: DownloadFileKind, url: URL) {
        let key = Self.taskKey(entry.id, kind)
        let task = downloadSession.downloadTask(with: url)
        downloadTasks[key] = task
        delegate.taskToTarget[task.taskIdentifier] = DownloadTarget(modelID: entry.id, kind: kind)
        task.resume()
    }

    private func missingDownloadBytes(for entry: ModelCatalogEntry) -> Int64 {
        var needed: Int64 = 0
        let weights = Self.modelsDirectory.appendingPathComponent(entry.fileName)
        if !FileManager.default.fileExists(atPath: weights.path) { needed += entry.byteSize }
        if entry.hasVision, projectorFileURL(for: entry) == nil {
            needed += entry.projectorByteSize ?? 0
        }
        return needed
    }

    private func refreshCombinedProgress(_ modelID: String) {
        guard let entry = allEntries.first(where: { $0.id == modelID }) else { return }
        let bucket = downloadBytes[modelID] ?? [:]
        let weights = bucket[.weights]
        let projector = bucket[.projector]
        let written = (weights?.written ?? 0) + (projector?.written ?? 0)
        var expected = (weights?.expected ?? 0) + (projector?.expected ?? 0)
        if expected <= 0 { expected = entry.totalByteSize }
        let progress = expected > 0 ? min(1, Double(written) / Double(expected)) : 0
        if case .downloading(let current) = states[modelID], abs(current - progress) < 0.001 { return }
        assign(modelID, .downloading(progress: progress))
    }

    static func taskKey(_ modelID: String, _ kind: DownloadFileKind) -> String {
        kind == .weights ? modelID : "\(modelID)#mmproj"
    }

    private func assign(_ id: String, _ value: ModelDownloadState) {
        guard states[id] != value else { return }
        states[id] = value
        ModelManagerIOProbe.mutationCount += 1
    }

    private static func loadCustomEntries() -> [ModelCatalogEntry] {
        guard let data = UserDefaults.standard.data(forKey: customModelsKey) else { return [] }
        return (try? JSONDecoder().decode([ModelCatalogEntry].self, from: data)) ?? []
    }

    private func saveCustomEntries() {
        guard let data = try? JSONEncoder().encode(customEntries) else { return }
        UserDefaults.standard.set(data, forKey: Self.customModelsKey)
    }
}

enum ModelManagerError: LocalizedError {
    case invalidURL

    var errorDescription: String? {
        switch self {
        case .invalidURL: "Enter a direct HTTPS link to a .gguf file."
        }
    }
}

enum DownloadFileKind: String, CaseIterable {
    case weights
    case projector
}

private struct DownloadTarget {
    let modelID: String
    let kind: DownloadFileKind
}

private final class DownloadDelegate: NSObject, URLSessionDownloadDelegate {
    weak var owner: ModelManager?
    var taskToTarget: [Int: DownloadTarget] = [:]

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        guard let target = taskToTarget[downloadTask.taskIdentifier] else { return }
        taskToTarget[downloadTask.taskIdentifier] = nil
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("gguf")
        try? FileManager.default.removeItem(at: temp)
        do {
            try FileManager.default.copyItem(at: location, to: temp)
            Task { @MainActor in
                owner?.finishDownload(modelID: target.modelID, kind: target.kind, tempURL: temp)
            }
        } catch {
            Task { @MainActor in
                owner?.reportFailure(modelID: target.modelID, kind: target.kind, message: error.localizedDescription)
            }
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard let target = taskToTarget[downloadTask.taskIdentifier],
              totalBytesExpectedToWrite > 0 else { return }
        Task { @MainActor in
            owner?.reportProgress(
                modelID: target.modelID,
                kind: target.kind,
                written: totalBytesWritten,
                expected: totalBytesExpectedToWrite
            )
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error, let target = taskToTarget[task.taskIdentifier] else { return }
        taskToTarget[task.taskIdentifier] = nil
        if (error as NSError).code == NSURLErrorCancelled { return }
        Task { @MainActor in
            owner?.reportFailure(modelID: target.modelID, kind: target.kind, message: error.localizedDescription)
        }
    }
}
