import Foundation
#if canImport(os)
import os
#endif

/// Pure policy for Gemma 4 / mtmd: small image token cap, 512 ubatch, memory preflight.
/// An 8 GB iPad cannot hold 8192 ctx + 2048 ubatch + 3.1 GB weights + 1 GB F16 mmproj.
enum VisionEvalBudget {
    static let imageMaxSides = [896, 672, 448]
    static let reservedMaxTokens = 400
    static let imageMaxTokens = 256
    /// Default ubatch; image tokens are capped at `imageMaxTokens` so they fit one ubatch.
    static let preferredUBatch = 512
    static let maxUBatch = 768
    static let fallbackUBatch = 768
    /// Context size while a projector may be used (KV + mmproj must coexist).
    static let visionNCtx = 4096
    static let fallbackNote = "Image couldn't be processed; answered from text"
    static let memorySkipNote = "Image skipped: not enough memory on this iPad"

    enum Outcome: Equatable, Sendable {
        case proceed
        case retrySmallerImage(maxSide: Int)
        case textOnlyFallback
    }

    static func effectiveNCtx(requested: Int, hasProjector: Bool) -> Int {
        hasProjector ? min(requested, visionNCtx) : requested
    }

    static func overflows(chunkTokens: Int, nCtx: Int, maxTokens: Int = reservedMaxTokens) -> Bool {
        chunkTokens + maxTokens > nCtx
    }

    /// Next catalog long-side below `current`, or nil when already at 448 (or smaller).
    static func nextMaxSide(after current: Int) -> Int? {
        guard let index = imageMaxSides.firstIndex(where: { $0 <= current }),
              index + 1 < imageMaxSides.count
        else { return nil }
        return imageMaxSides[index + 1]
    }

    /// After tokenize / `mtmd_helper_get_n_tokens`. Shrink before eval when gen room won't fit.
    static func afterTokenize(
        chunkTokens: Int,
        currentMaxSide: Int,
        nCtx: Int,
        maxTokens: Int = reservedMaxTokens
    ) -> Outcome {
        if !overflows(chunkTokens: chunkTokens, nCtx: nCtx, maxTokens: maxTokens) {
            return .proceed
        }
        if let next = nextMaxSide(after: currentMaxSide) {
            return .retrySmallerImage(maxSide: next)
        }
        return chunkTokens >= nCtx ? .textOnlyFallback : .proceed
    }

    /// After mtmd tokenize or eval returns non-zero. Prefer another shrink, then text-only.
    static func afterEvalFailure(currentMaxSide: Int, canShrink: Bool) -> Outcome {
        if canShrink, let next = nextMaxSide(after: currentMaxSide) {
            return .retrySmallerImage(maxSide: next)
        }
        return .textOnlyFallback
    }

    /// Drop the longest unprotected block (sources / paper passages / brief) once.
    static func trimUserSources(_ user: String) -> String {
        var blocks = user.components(separatedBy: "\n\n")
        let droppable = blocks.indices.filter { !isProtectedSourceBlock(blocks[$0]) }
        guard let idx = droppable.max(by: { blocks[$0].count < blocks[$1].count }) else {
            return user
        }
        blocks.remove(at: idx)
        return blocks.joined(separator: "\n\n")
    }

    private static func isProtectedSourceBlock(_ block: String) -> Bool {
        let head = block.trimmingCharacters(in: .whitespacesAndNewlines)
        return head.hasPrefix("Question:")
            || head.hasPrefix("Selected passage")
            || head.hasPrefix("Hard terms:")
            || head.hasPrefix("Paper:")
    }
}

/// CPU-side estimates. GPU decisions live in `GpuBudget` (Metal working set).
enum MemoryPreflight {
    static let projectorMultiplier = 1.5
    static let projectorOverheadBytes: UInt64 = 400 * 1024 * 1024
    static let modelMultiplier = 1.2
    /// Free projector after an answer when remaining headroom is below this.
    static let keepProjectorFloor: UInt64 = 300 * 1024 * 1024

    /// 2 (K+V) × layers × n_ctx × hidden × 2 bytes (fp16). Defaults match a Gemma-class 2B.
    static func kvEstimateBytes(nCtx: Int, layers: Int = 26, hidden: Int = 2304) -> UInt64 {
        UInt64(2 * layers * max(nCtx, 0) * hidden * 2)
    }

    static func projectorNeed(fileBytes: UInt64) -> UInt64 {
        UInt64(Double(fileBytes) * projectorMultiplier) + projectorOverheadBytes
    }

    static func modelNeed(fileBytes: UInt64, nCtx: Int) -> UInt64 {
        UInt64(Double(fileBytes) * modelMultiplier) + kvEstimateBytes(nCtx: nCtx)
    }

    static func canLoadProjector(available: UInt64, fileBytes: UInt64) -> Bool {
        available >= projectorNeed(fileBytes: fileBytes)
    }

    static func canLoadModel(available: UInt64, fileBytes: UInt64, nCtx: Int) -> Bool {
        available >= modelNeed(fileBytes: fileBytes, nCtx: nCtx)
    }

    /// `os_proc_available_memory()`; 0 means the platform did not report a value.
    static func availableBytes() -> UInt64 {
        #if os(iOS)
        return UInt64(os_proc_available_memory())
        #else
        return 2_000_000_000
        #endif
    }

    static func fileBytes(at url: URL) -> UInt64 {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey])
        if let size = values?.fileSize, size > 0 { return UInt64(size) }
        return 0
    }
}

enum VisionFallback {
    static let note = VisionEvalBudget.fallbackNote
    static let memorySkipNote = VisionEvalBudget.memorySkipNote

    static func displayNote(for error: Error) -> String {
        if case .visionFailed(let message) = error as? LlamaRunnerError,
           message == memorySkipNote {
            return memorySkipNote
        }
        return note
    }

    static func shouldRetryTextOnly(_ error: Error) -> Bool {
        guard let error = error as? LlamaRunnerError else { return false }
        switch error {
        case .visionFailed:
            return true
        case .generationFailed(let message):
            return message.contains("mtmd")
        default:
            return false
        }
    }

    /// Engine catch path. Tests inject a simulated eval failure here — no model required.
    static func recover<T>(
        vision: () throws -> T,
        textOnly: () throws -> T
    ) throws -> (value: T, usedFallback: Bool) {
        do {
            return (try vision(), false)
        } catch {
            guard shouldRetryTextOnly(error) else { throw error }
            return (try textOnly(), true)
        }
    }
}
