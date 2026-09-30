import Foundation
import UIKit

enum LlamaRunnerError: LocalizedError {
    case frameworkMissing
    case notLoaded
    case loadFailed(String)
    case generationFailed(String)
    /// mtmd tokenize/eval failed after shrink retries. Engine should answer text-only.
    case visionFailed(String)
    case cancelled
    case outOfMemory
    case promptDecodeFailed(rc: Int32, promptTokens: Int, nCtx: Int)

    static let smallerModelHint = "Try a smaller model in Settings → Local models."

    var errorDescription: String? {
        switch self {
        case .frameworkMissing:
            "Link Vendor/llama.xcframework in the app target (see LOCAL_LLM.md)."
        case .notLoaded:
            "No local model is loaded."
        case .loadFailed(let message):
            message.contains("memory") || message.contains("Memory")
                ? message
                : "Could not load the local model (it may need more memory). \(Self.smallerModelHint)"
        case .generationFailed(let message):
            message
        case .visionFailed(let message):
            message
        case .cancelled:
            "Generation was cancelled."
        case .outOfMemory:
            "The model ran out of memory. \(Self.smallerModelHint)"
        case .promptDecodeFailed(let rc, let promptTokens, let nCtx):
            "Prompt decode failed (rc=\(rc) promptTokens=\(promptTokens) nCtx=\(nCtx))."
        }
    }

    static func isPromptDecodeFailure(_ error: Error) -> Bool {
        if case .promptDecodeFailed = error as? LlamaRunnerError { return true }
        if case .generationFailed(let message) = error as? LlamaRunnerError {
            return message.contains("Prompt decode failed")
        }
        return false
    }

    var prefersCardError: Bool {
        switch self {
        case .loadFailed, .outOfMemory: true
        default: false
        }
    }
}

extension Notification.Name {
    static let llamaMemoryPressure = Notification.Name("llamaMemoryPressure")
}

struct LlamaGenerationMetrics: Sendable, Equatable {
    var tokensPerSecond: Double
    var tokenCount: Int
    var stopReason: GenerationStopReason = .maxTokens
}

enum LlamaStreamPiece: Sendable {
    case text(String)
    case finished(LlamaGenerationMetrics)
}

/// Checked from the decode loop without hopping onto the actor (so cancel can't deadlock).
final class LlamaCancelFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }

    func reset() {
        lock.lock()
        cancelled = false
        lock.unlock()
    }
}

#if canImport(llama)
import llama

actor LlamaRunner {
    static let shared = LlamaRunner()

    private var model: OpaquePointer?
    private var context: OpaquePointer?
    private var mtmd: OpaquePointer?
    private var loadedPath: String?
    private var loadedProjectorPath: String?
    private var loadedNCtx: Int = 0
    private var loadedNBatch: Int = VisionEvalBudget.preferredUBatch
    private var loadedNUbatch: Int = VisionEvalBudget.preferredUBatch
    private var loadedPromptFormat: PromptFormat?
    private var pendingProjectorPath: String?
    private var lastModelURL: URL?
    private var lastNCtx: Int = 4096
    private var lastProjectorURL: URL?
    private var lastPromptFormat: PromptFormat?
    private var loadedNGpuLayers: Int = GpuBudget.allLayers
    private var requestDepth = 0
    private var visionAborted = false
    private let cancelFlag = LlamaCancelFlag()
    private var memoryPressure = false
    private nonisolated(unsafe) static var backendStarted = false

    private init() {}

    var isLoaded: Bool { context != nil }

    var nCtx: Int { loadedNCtx > 0 ? loadedNCtx : 4096 }

    func tokenCount(_ text: String) -> Int {
        tokenizeCount(text, addSpecial: false)
    }

    /// Tokens of the chat-templated system+user string, matching decode (`add_special`).
    func formattedPromptTokenCount(system: String, user: String) -> Int {
        guard let modelPtr = model else {
            return PromptBudget.estimateTokens(system) + PromptBudget.estimateTokens(user)
                + PromptBudget.chatTemplateOverhead
        }
        return tokenizeCount(formatChat(system: system, user: user, model: modelPtr), addSpecial: true)
    }

    func beginRequest() {
        requestDepth += 1
    }

    func endRequest() {
        requestDepth = max(0, requestDepth - 1)
    }

    func reloadIfUnloaded() async throws {
        guard model == nil, let url = lastModelURL else { return }
        try await load(
            modelURL: url,
            nCtx: lastNCtx,
            projectorURL: lastProjectorURL,
            promptFormat: lastPromptFormat
        )
    }

    func load(modelURL: URL, nCtx: Int = 4096, projectorURL: URL? = nil, promptFormat: PromptFormat? = nil) async throws {
        try ensureBackend()
        lastModelURL = modelURL
        lastNCtx = nCtx
        lastProjectorURL = projectorURL
        lastPromptFormat = promptFormat
        loadedPromptFormat = promptFormat
        pendingProjectorPath = projectorURL?.path
        let effectiveCtx = VisionEvalBudget.effectiveNCtx(requested: nCtx, hasProjector: projectorURL != nil)
        if loadedPath == modelURL.path, context != nil, loadedNCtx == effectiveCtx {
            return
        }
        let modelBytes = MemoryPreflight.fileBytes(at: modelURL)
        let projectorBytes = projectorURL.map { MemoryPreflight.fileBytes(at: $0) } ?? 0
        let avail = MemoryPreflight.availableBytes()
        let gpuBefore = GpuBudget.snapshot()
        let plan = GpuBudget.plan(
            gpuBudget: gpuBefore.budgetBytes > 0 ? gpuBefore.budgetBytes : GpuBudget.ipadWorkingSetBytes,
            gpuAllocated: gpuBefore.allocatedBytes,
            modelBytes: modelBytes,
            projectorBytes: projectorBytes,
            nCtx: effectiveCtx,
            cpuAvailable: avail
        )
        #if DEBUG
        print(GpuBudget.logLine(gpuBefore))
        print("PCVision plan n_gpu_layers=\(plan.nGpuLayers) projector=\(plan.projector.rawValue) modelFitsGPU=\(plan.modelFitsGPU)")
        #endif
        if avail > 0, avail < modelBytes {
            throw LlamaRunnerError.loadFailed(
                "Not enough memory to load this model (\(modelBytes / 1_048_576) MB file, \(avail / 1_048_576) MB free). \(LlamaRunnerError.smallerModelHint)"
            )
        }
        unloadPreservingLastLoad()
        cancelFlag.reset()
        pendingProjectorPath = projectorURL?.path
        var modelParams = llama_model_default_params()
        modelParams.n_gpu_layers = Int32(plan.nGpuLayers)
        let path = modelURL.path
        guard let loadedModel = llama_model_load_from_file(path, modelParams) else {
            throw LlamaRunnerError.loadFailed("load returned nil")
        }
        model = loadedModel
        loadedNGpuLayers = plan.nGpuLayers
        var ctxParams = llama_context_default_params()
        ctxParams.n_ctx = UInt32(max(512, effectiveCtx))
        ctxParams.n_batch = UInt32(max(512, min(effectiveCtx, VisionEvalBudget.preferredUBatch)))
        ctxParams.n_ubatch = UInt32(VisionEvalBudget.preferredUBatch)
        ctxParams.n_threads = Int32(Self.threadCount)
        ctxParams.n_threads_batch = Int32(Self.threadCount)
        // 512 ubatch (768 max). image_max_tokens=256 keeps one image inside that ubatch.
        let ctx: OpaquePointer?
        let ubatch: Int
        if let loaded = llama_init_from_model(loadedModel, ctxParams) {
            ctx = loaded
            ubatch = VisionEvalBudget.preferredUBatch
        } else {
            ctxParams.n_ubatch = UInt32(VisionEvalBudget.maxUBatch)
            ctx = llama_init_from_model(loadedModel, ctxParams)
            ubatch = VisionEvalBudget.maxUBatch
        }
        guard let ctx else {
            llama_model_free(loadedModel)
            model = nil
            throw LlamaRunnerError.loadFailed("context init returned nil")
        }
        context = ctx
        loadedPath = path
        loadedNCtx = effectiveCtx
        loadedNBatch = Int(llama_n_batch(ctx))
        loadedNUbatch = ubatch
        let gpuAfter = GpuBudget.snapshot()
        #if DEBUG
        print(GpuBudget.logLine(gpuAfter))
        print("PCVision n_ctx=\(effectiveCtx) n_ubatch=\(ubatch) n_gpu_layers=\(plan.nGpuLayers)")
        #endif
    }

    func handleMemoryPressure() {
        memoryPressure = true
        visionAborted = true
        let inFlight = requestDepth > 0
        #if DEBUG
        print("PCVision memory warning: freeing projector; model \(inFlight ? "stays (in-flight)" : "unloads (idle)")")
        #endif
        freeMtmd()
        if GpuBudget.unloadModelOnPressure(requestInFlight: inFlight) {
            unloadPreservingLastLoad()
        }
    }

    func consumeMemoryPressure() -> Bool {
        let flagged = memoryPressure
        memoryPressure = false
        return flagged
    }

    func unload() {
        unloadPreservingLastLoad()
    }

    private func unloadPreservingLastLoad() {
        cancelFlag.cancel()
        freeMtmd()
        if let ctx = context {
            llama_free(ctx)
            context = nil
        }
        if let m = model {
            llama_model_free(m)
            model = nil
        }
        loadedPath = nil
        loadedNCtx = 0
        loadedNBatch = VisionEvalBudget.preferredUBatch
        loadedNUbatch = VisionEvalBudget.preferredUBatch
        loadedNGpuLayers = GpuBudget.allLayers
        loadedPromptFormat = lastPromptFormat
        pendingProjectorPath = lastProjectorURL?.path
    }

    nonisolated func cancel() {
        cancelFlag.cancel()
    }

    func generateChat(
        system: String,
        user: String,
        image: MtmdPreparedImage? = nil,
        sourceImage: UIImage? = nil,
        maxTokens: Int? = nil,
        sampler: LlamaSamplerSpec = .teach,
        stop: [String] = []
    ) -> AsyncThrowingStream<LlamaStreamPiece, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await self.runChat(
                        system: system,
                        user: user,
                        image: image,
                        sourceImage: sourceImage,
                        maxTokens: maxTokens ?? sampler.maxTokens,
                        sampler: sampler,
                        stop: stop,
                        continuation: continuation
                    )
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
                self.cancel()
            }
        }
    }

    private func runChat(
        system: String,
        user: String,
        image: MtmdPreparedImage?,
        sourceImage: UIImage?,
        maxTokens: Int,
        sampler spec: LlamaSamplerSpec,
        stop: [String],
        continuation: AsyncThrowingStream<LlamaStreamPiece, Error>.Continuation
    ) async throws {
        if model == nil || context == nil {
            try await reloadIfUnloaded()
        }
        guard let ctx = context, let modelPtr = model else { throw LlamaRunnerError.notLoaded }
        cancelFlag.reset()
        visionAborted = false
        guard let vocab = llama_model_get_vocab(modelPtr) else {
            throw LlamaRunnerError.generationFailed("Missing vocabulary.")
        }
        clearMemory(ctx)
        var usedVision = false
        if let image {
            if visionAborted {
                throw LlamaRunnerError.visionFailed(VisionEvalBudget.memorySkipNote)
            }
            try ensureProjector()
            if visionAborted {
                freeMtmd()
                throw LlamaRunnerError.visionFailed(VisionEvalBudget.memorySkipNote)
            }
            if let mtmdCtx = mtmd {
                usedVision = true
                try evalMultimodal(
                    system: system,
                    user: user,
                    image: image,
                    sourceImage: sourceImage,
                    maxTokens: maxTokens,
                    model: modelPtr,
                    mtmd: mtmdCtx,
                    ctx: ctx
                )
            } else {
                throw LlamaRunnerError.visionFailed(VisionEvalBudget.memorySkipNote)
            }
        } else {
            do {
                try decodeTextPrompt(
                    formatChat(system: system, user: user, model: modelPtr),
                    vocab: vocab,
                    ctx: ctx,
                    maxGenTokens: maxTokens
                )
            } catch {
                guard LlamaRunnerError.isPromptDecodeFailure(error) else { throw error }
                try decodeTextPrompt(
                    formatChat(
                        system: system,
                        user: PromptBudget.shrinkKeepingTail(user, scale: 0.5),
                        model: modelPtr
                    ),
                    vocab: vocab,
                    ctx: ctx,
                    maxGenTokens: maxTokens
                )
            }
        }

        let sampler = makeSampler(spec, vocab: vocab)
        defer { llama_sampler_free(sampler) }

        var generated = 0
        var output = ""
        var stopReason = GenerationStopReason.maxTokens
        let start = CFAbsoluteTimeGetCurrent()

        while generated < maxTokens {
            try Task.checkCancellation()
            if cancelFlag.isCancelled { throw LlamaRunnerError.cancelled }
            let token = llama_sampler_sample(sampler, ctx, -1)
            if llama_vocab_is_eog(vocab, token) {
                let piece = tokenToPiece(token, vocab: vocab)
                stopReason = .eog(id: token, piece: piece)
                break
            }
            llama_sampler_accept(sampler, token)
            let piece = tokenToPiece(token, vocab: vocab)
            output += piece
            if output.contains(PromptFormat.gemmaTurnClose) {
                stopReason = .turnClose
                break
            }
            if let matched = GenerationStopPolicy.firstHonoredStop(in: output, stops: stop) {
                stopReason = .stopString(matched)
                break
            }
            continuation.yield(.text(piece))
            generated += 1
            var next = token
            let nextBatch = llama_batch_get_one(&next, 1)
            if llama_decode(ctx, nextBatch) != 0 {
                throw LlamaRunnerError.generationFailed("Token decode failed.")
            }
        }

        #if DEBUG
        print("PCGen stop=\(stopReason.logLabel) generated=\(generated) maxTokens=\(maxTokens)")
        #endif
        let elapsed = max(CFAbsoluteTimeGetCurrent() - start, 0.001)
        let metrics = LlamaGenerationMetrics(
            tokensPerSecond: Double(generated) / elapsed,
            tokenCount: generated,
            stopReason: stopReason
        )
        continuation.yield(.finished(metrics))
        if usedVision { releaseProjectorIfMemoryLow() }
    }

    private func formatChat(system: String, user: String, model: OpaquePointer) -> String {
        let bufSize = 32_768
        var buffer = [CChar](repeating: 0, count: bufSize)
        let template = llama_model_chat_template(model, nil)
        let templateString = template.map { String(cString: $0) }
        let format = PromptFormat.resolve(catalog: loadedPromptFormat, template: templateString)
        // libllama has no Gemma 4 template; ours pre-fills the empty thought channel.
        if format == .gemma4 { return format.render(system: system, user: user) }
        let written: Int32
        if template != nil {
            written = system.withCString { systemPtr in
                user.withCString { userPtr in
                    "system".withCString { systemRole in
                        "user".withCString { userRole in
                            let messages = [
                                llama_chat_message(role: systemRole, content: systemPtr),
                                llama_chat_message(role: userRole, content: userPtr),
                            ]
                            return llama_chat_apply_template(template, messages, messages.count, true, &buffer, Int32(bufSize))
                        }
                    }
                }
            }
        } else {
            written = -1
        }
        if written > 0, written < bufSize {
            return String(cString: buffer)
        }
        return format.render(system: system, user: user)
    }

    private func ensureProjector() throws {
        if mtmd != nil { return }
        guard let path = pendingProjectorPath ?? loadedProjectorPath ?? lastProjectorURL?.path else {
            throw LlamaRunnerError.visionFailed(VisionEvalBudget.memorySkipNote)
        }
        let url = URL(fileURLWithPath: path)
        let fileBytes = MemoryPreflight.fileBytes(at: url)
        let gpu = GpuBudget.snapshot()
        let cpu = MemoryPreflight.availableBytes()
        let placement = GpuBudget.projectorPlacement(
            projectorBytes: fileBytes,
            gpuFreeAfterModel: gpu.freeBytes,
            cpuAvailable: cpu
        )
        #if DEBUG
        print(GpuBudget.logLine(gpu))
        print("PCVision projector placement=\(placement.rawValue) fileMB=\(fileBytes / 1_048_576)")
        #endif
        switch placement {
        case .skip:
            throw LlamaRunnerError.visionFailed(VisionEvalBudget.memorySkipNote)
        case .gpu:
            try loadProjector(url, useGPU: true)
            if mtmd == nil {
                try loadProjector(url, useGPU: false)
            }
        case .cpu:
            try loadProjector(url, useGPU: false)
        }
        if mtmd == nil {
            throw LlamaRunnerError.visionFailed(VisionEvalBudget.memorySkipNote)
        }
    }

    private func loadProjector(_ projectorURL: URL, useGPU: Bool) throws {
        freeMtmd()
        guard let modelPtr = model else { return }
        let gpuBefore = GpuBudget.snapshot()
        #if DEBUG
        print(GpuBudget.logLine(gpuBefore))
        #endif
        var params = mtmd_context_params_default()
        params.use_gpu = useGPU
        params.warmup = false
        params.image_max_tokens = Int32(VisionEvalBudget.imageMaxTokens)
        params.n_threads = Int32(Self.threadCount)
        params.media_marker = mtmd_default_marker()
        guard let loaded = mtmd_init_from_file(projectorURL.path, modelPtr, params) else {
            loadedProjectorPath = nil
            return
        }
        mtmd = loaded
        loadedProjectorPath = projectorURL.path
        pendingProjectorPath = projectorURL.path
        let gpuAfter = GpuBudget.snapshot()
        #if DEBUG
        print(GpuBudget.logLine(gpuAfter))
        print("PCVision projector loaded use_gpu=\(useGPU) image_max_tokens=\(VisionEvalBudget.imageMaxTokens)")
        #endif
    }

    private func releaseProjectorIfMemoryLow() {
        guard mtmd != nil else { return }
        let gpu = GpuBudget.snapshot()
        if gpu.budgetBytes > 0, gpu.freeBytes >= MemoryPreflight.keepProjectorFloor { return }
        let avail = MemoryPreflight.availableBytes()
        if gpu.budgetBytes == 0, avail > 0, avail >= MemoryPreflight.keepProjectorFloor { return }
        #if DEBUG
        print("PCVision free projector after answer \(GpuBudget.logLine(gpu))")
        #endif
        freeMtmd()
    }

    private func freeMtmd() {
        if let existing = mtmd {
            mtmd_free(existing)
            mtmd = nil
        }
        loadedProjectorPath = nil
    }

    private func decodeTextPrompt(
        _ prompt: String,
        vocab: OpaquePointer,
        ctx: OpaquePointer,
        maxGenTokens: Int
    ) throws {
        clearMemory(ctx)
        var tokens = try tokenize(prompt, vocab: vocab)
        guard !tokens.isEmpty else { throw LlamaRunnerError.generationFailed("Empty prompt.") }
        let cap = PromptBudget.decodeCap(nCtx: loadedNCtx, maxGenTokens: maxGenTokens)
        if tokens.count > cap {
            tokens = Array(tokens.prefix(cap))
        }
        precondition(
            tokens.count <= PromptBudget.decodeCap(nCtx: loadedNCtx, maxGenTokens: maxGenTokens),
            "PCGen prompt \(tokens.count) exceeds nCtx \(loadedNCtx) - maxGen \(maxGenTokens)"
        )
        let rc = decodeTokenChunks(tokens, ctx: ctx)
        #if DEBUG
        print("PCGen promptTokens=\(tokens.count) nCtx=\(loadedNCtx) rc=\(rc)")
        #endif
        if rc != 0 {
            throw LlamaRunnerError.promptDecodeFailed(rc: rc, promptTokens: tokens.count, nCtx: loadedNCtx)
        }
    }

    @discardableResult
    private func decodeTokenChunks(_ tokens: [llama_token], ctx: OpaquePointer) -> Int32 {
        let nBatch = max(1, loadedNBatch > 0 ? loadedNBatch : Int(llama_n_batch(ctx)))
        var offset = 0
        var lastRC: Int32 = 0
        while offset < tokens.count {
            let end = min(offset + nBatch, tokens.count)
            var slice = Array(tokens[offset..<end])
            let batch = llama_batch_get_one(&slice, Int32(slice.count))
            lastRC = llama_decode(ctx, batch)
            if lastRC != 0 { return lastRC }
            offset = end
        }
        return lastRC
    }

    private func clearMemory(_ ctx: OpaquePointer) {
        llama_memory_clear(llama_get_memory(ctx), true)
    }

    private func evalMultimodal(
        system: String,
        user: String,
        image: MtmdPreparedImage,
        sourceImage: UIImage?,
        maxTokens: Int,
        model: OpaquePointer,
        mtmd mtmdCtx: OpaquePointer,
        ctx: OpaquePointer
    ) throws {
        var prepared = image
        var currentUser = user
        var maxSide = max(prepared.width, prepared.height)
        for _ in 0..<VisionEvalBudget.imageMaxSides.count {
            if visionAborted {
                clearMemory(ctx)
                throw LlamaRunnerError.visionFailed(VisionEvalBudget.memorySkipNote)
            }
            let outcome = try tokenizeAndEval(
                system: system,
                user: currentUser,
                image: prepared,
                maxTokens: maxTokens,
                model: model,
                mtmd: mtmdCtx,
                ctx: ctx,
                currentMaxSide: maxSide,
                canShrinkImage: sourceImage != nil
            )
            switch outcome {
            case .proceed:
                return
            case .retrySmallerImage(let next):
                maxSide = next
                if let sourceImage, let smaller = MtmdImagePrep.prepare(sourceImage, maxSide: next) {
                    prepared = smaller
                }
                currentUser = VisionEvalBudget.trimUserSources(currentUser)
                clearMemory(ctx)
            case .textOnlyFallback:
                clearMemory(ctx)
                throw LlamaRunnerError.visionFailed("mtmd tokenize or eval failed")
            }
        }
        clearMemory(ctx)
        throw LlamaRunnerError.visionFailed("mtmd eval failed after shrink retries")
    }

    private func tokenizeAndEval(
        system: String,
        user: String,
        image: MtmdPreparedImage,
        maxTokens: Int,
        model: OpaquePointer,
        mtmd mtmdCtx: OpaquePointer,
        ctx: OpaquePointer,
        currentMaxSide: Int,
        canShrinkImage: Bool
    ) throws -> VisionEvalBudget.Outcome {
        guard let chunks = mtmd_input_chunks_init() else {
            throw LlamaRunnerError.visionFailed("mtmd chunks init failed.")
        }
        defer { mtmd_input_chunks_free(chunks) }

        let rgb = [UInt8](image.rgb)
        guard rgb.count == image.byteCount else {
            throw LlamaRunnerError.visionFailed("Image RGB size mismatch.")
        }
        let bitmap = rgb.withUnsafeBufferPointer { buf -> OpaquePointer? in
            mtmd_bitmap_init(UInt32(image.width), UInt32(image.height), buf.baseAddress)
        }
        guard let bitmap else { throw LlamaRunnerError.visionFailed("mtmd bitmap init failed.") }
        defer { mtmd_bitmap_free(bitmap) }

        var userText = user
        if let marker = Self.mediaMarker() {
            userText = "\(marker)\n\(user)"
        }
        let prompt = formatChat(system: system, user: userText, model: model)

        let tokenized: Int32 = prompt.withCString { cString in
            var text = mtmd_input_text(
                text: cString,
                text_len: strlen(cString),
                add_special: true,
                parse_special: true
            )
            return withUnsafePointer(to: &text) { textPtr in
                var bitmapRef: OpaquePointer? = bitmap
                return withUnsafePointer(to: &bitmapRef) { list in
                    mtmd_tokenize(mtmdCtx, chunks, textPtr, list, 1)
                }
            }
        }
        if tokenized != 0 {
            return VisionEvalBudget.afterEvalFailure(
                currentMaxSide: currentMaxSide,
                canShrink: canShrinkImage
            )
        }

        let nTokens = Int(mtmd_helper_get_n_tokens(chunks))
        #if DEBUG
        print("PCVision tokens=\(nTokens) n_ctx=\(loadedNCtx) n_ubatch=\(loadedNUbatch) availMB=\(MemoryPreflight.availableBytes() / 1_048_576)")
        #endif

        let budget = VisionEvalBudget.afterTokenize(
            chunkTokens: nTokens,
            currentMaxSide: currentMaxSide,
            nCtx: loadedNCtx,
            maxTokens: maxTokens
        )
        if budget != .proceed { return budget }

        clearMemory(ctx)
        var nPast: llama_pos = 0
        let evaluated = mtmd_helper_eval_chunks(
            mtmdCtx, ctx, chunks, 0, 0, Int32(loadedNUbatch), true, &nPast
        )
        guard evaluated == 0 else {
            return VisionEvalBudget.afterEvalFailure(
                currentMaxSide: currentMaxSide,
                canShrink: canShrinkImage
            )
        }
        return .proceed
    }

    private static func mediaMarker() -> String? {
        guard let cStr = mtmd_default_marker() else { return nil }
        return String(cString: cStr)
    }

    private func tokenizeCount(_ text: String, addSpecial: Bool) -> Int {
        guard let modelPtr = model, let vocab = llama_model_get_vocab(modelPtr) else {
            return PromptBudget.estimateTokens(text)
        }
        var probe = [llama_token](repeating: 0, count: 1)
        let probed = text.withCString { cString in
            llama_tokenize(vocab, cString, Int32(strlen(cString)), &probe, 1, addSpecial, true)
        }
        if probed < 0 { return Int(-probed) }
        if probed > 0 { return Int(probed) }
        return PromptBudget.estimateTokens(text)
    }

    private func tokenize(_ text: String, vocab: OpaquePointer) throws -> [llama_token] {
        var probe = [llama_token](repeating: 0, count: 1)
        let probed = text.withCString { cString in
            llama_tokenize(vocab, cString, Int32(strlen(cString)), &probe, 1, true, true)
        }
        let cap = probed < 0 ? Int(-probed) : max(Int(probed), 1)
        guard cap > 0 else { throw LlamaRunnerError.generationFailed("Tokenization failed.") }
        var tokens = [llama_token](repeating: 0, count: cap)
        let count = text.withCString { cString in
            llama_tokenize(vocab, cString, Int32(strlen(cString)), &tokens, Int32(cap), true, true)
        }
        guard count > 0 else { throw LlamaRunnerError.generationFailed("Tokenization failed.") }
        return Array(tokens.prefix(Int(count)))
    }

    private func tokenToPiece(_ token: llama_token, vocab: OpaquePointer) -> String {
        var buffer = [CChar](repeating: 0, count: 256)
        let n = llama_token_to_piece(vocab, token, &buffer, 256, 0, true)
        guard n > 0 else { return "" }
        return String(cString: buffer)
    }

    private func makeSampler(_ spec: LlamaSamplerSpec, vocab: OpaquePointer) -> UnsafeMutablePointer<llama_sampler> {
        let chainParams = llama_sampler_chain_default_params()
        let chain = llama_sampler_chain_init(chainParams)!
        if spec.penaltyLastN > 0 {
            let nVocab = llama_vocab_n_tokens(vocab)
            llama_sampler_chain_add(chain, llama_sampler_init_penalties(
                nVocab, spec.penaltyLastN, spec.penaltyRepeat, spec.penaltyFreq, spec.penaltyPresent
            ))
        }
        if let minP = spec.minP {
            llama_sampler_chain_add(chain, llama_sampler_init_min_p(minP, 1))
        }
        llama_sampler_chain_add(chain, llama_sampler_init_temp(spec.temperature))
        llama_sampler_chain_add(chain, llama_sampler_init_top_p(spec.topP, 1))
        llama_sampler_chain_add(chain, llama_sampler_init_dist(UInt32.random(in: 0...UInt32.max)))
        return chain
    }

    private func ensureBackend() throws {
        if !Self.backendStarted {
            llama_backend_init()
            Self.backendStarted = true
        }
    }

    private static var threadCount: Int {
        max(2, ProcessInfo.processInfo.activeProcessorCount)
    }
}

#else

actor LlamaRunner {
    static let shared = LlamaRunner()

    var isLoaded: Bool { false }

    var nCtx: Int { 4096 }

    func tokenCount(_ text: String) -> Int { PromptBudget.estimateTokens(text) }

    func formattedPromptTokenCount(system: String, user: String) -> Int {
        PromptBudget.estimateTokens(system) + PromptBudget.estimateTokens(user) + PromptBudget.chatTemplateOverhead
    }

    func load(modelURL: URL, nCtx: Int = 4096, projectorURL: URL? = nil, promptFormat: PromptFormat? = nil) async throws {
        throw LlamaRunnerError.frameworkMissing
    }

    func unload() {}

    func beginRequest() {}

    func endRequest() {}

    func reloadIfUnloaded() async throws {}

    func handleMemoryPressure() {}

    func consumeMemoryPressure() -> Bool { false }

    nonisolated func cancel() {}

    func generateChat(
        system: String,
        user: String,
        image: MtmdPreparedImage? = nil,
        sourceImage: UIImage? = nil,
        maxTokens: Int? = nil,
        sampler: LlamaSamplerSpec = .teach,
        stop: [String] = []
    ) -> AsyncThrowingStream<LlamaStreamPiece, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish(throwing: LlamaRunnerError.frameworkMissing)
        }
    }
}

#endif
