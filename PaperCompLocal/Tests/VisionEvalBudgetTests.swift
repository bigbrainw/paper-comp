import XCTest
@testable import PaperComp

final class VisionEvalBudgetTests: XCTestCase {
    func testOverflowsWhenImagePlusGenerationExceedsContext() {
        XCTAssertTrue(VisionEvalBudget.overflows(chunkTokens: 7_800, nCtx: 8_192, maxTokens: 400))
        XCTAssertFalse(VisionEvalBudget.overflows(chunkTokens: 7_000, nCtx: 8_192, maxTokens: 400))
        XCTAssertTrue(VisionEvalBudget.overflows(chunkTokens: 513, nCtx: 512, maxTokens: 400))
    }

    func testNextMaxSideWalks896To672To448() {
        XCTAssertEqual(VisionEvalBudget.nextMaxSide(after: 896), 672)
        XCTAssertEqual(VisionEvalBudget.nextMaxSide(after: 672), 448)
        XCTAssertNil(VisionEvalBudget.nextMaxSide(after: 448))
        XCTAssertEqual(VisionEvalBudget.nextMaxSide(after: 900), 672)
        XCTAssertNil(VisionEvalBudget.nextMaxSide(after: 200))
    }

    func testAfterTokenizeShrinksThenFallsBack() {
        XCTAssertEqual(
            VisionEvalBudget.afterTokenize(chunkTokens: 600, currentMaxSide: 896, nCtx: 8_192, maxTokens: 400),
            .proceed
        )
        XCTAssertEqual(
            VisionEvalBudget.afterTokenize(chunkTokens: 8_000, currentMaxSide: 896, nCtx: 8_192, maxTokens: 400),
            .retrySmallerImage(maxSide: 672)
        )
        XCTAssertEqual(
            VisionEvalBudget.afterTokenize(chunkTokens: 8_000, currentMaxSide: 672, nCtx: 8_192, maxTokens: 400),
            .retrySmallerImage(maxSide: 448)
        )
        XCTAssertEqual(
            VisionEvalBudget.afterTokenize(chunkTokens: 8_200, currentMaxSide: 448, nCtx: 8_192, maxTokens: 400),
            .textOnlyFallback
        )
        XCTAssertEqual(
            VisionEvalBudget.afterTokenize(chunkTokens: 8_000, currentMaxSide: 448, nCtx: 8_192, maxTokens: 400),
            .proceed
        )
    }

    func testAfterEvalFailurePrefersShrinkThenTextFallback() {
        XCTAssertEqual(
            VisionEvalBudget.afterEvalFailure(currentMaxSide: 896, canShrink: true),
            .retrySmallerImage(maxSide: 672)
        )
        XCTAssertEqual(
            VisionEvalBudget.afterEvalFailure(currentMaxSide: 448, canShrink: true),
            .textOnlyFallback
        )
        XCTAssertEqual(
            VisionEvalBudget.afterEvalFailure(currentMaxSide: 896, canShrink: false),
            .textOnlyFallback
        )
    }

    func testTrimUserSourcesDropsLongestUnprotectedBlock() {
        let user = """
            Paper: Signal integrity

            Sources:
            [S1] Master Quality Authenticated
            A long unrelated Wikipedia extract that should be dropped when the image is oversized.

            Selected passage (do not repeat it):
            \"\"\"
            1/f noise
            \"\"\"

            Question: Explain what this means.
            """
        let trimmed = VisionEvalBudget.trimUserSources(user)
        XCTAssertFalse(trimmed.contains("Master Quality Authenticated"))
        XCTAssertTrue(trimmed.contains("Question: Explain what this means."))
        XCTAssertTrue(trimmed.contains("Selected passage"))
        XCTAssertTrue(trimmed.contains("Paper: Signal integrity"))
    }

    func testSimulatedEvalFailureTakesTextFallback() throws {
        let result = try VisionFallback.recover(
            vision: { throw LlamaRunnerError.visionFailed("mtmd eval failed (-1)") },
            textOnly: { "answer from OCR" }
        )
        XCTAssertTrue(result.usedFallback)
        XCTAssertEqual(result.value, "answer from OCR")
        XCTAssertEqual(VisionFallback.note, "Image couldn't be processed; answered from text")
    }

    func testSimulatedEvalFailureViaGenerationFailedMessage() throws {
        let result = try VisionFallback.recover(
            vision: { throw LlamaRunnerError.generationFailed("mtmd eval failed (-1)") },
            textOnly: { "text-only" }
        )
        XCTAssertTrue(result.usedFallback)
        XCTAssertEqual(result.value, "text-only")
    }

    func testSuccessfulVisionDoesNotFallback() throws {
        let result = try VisionFallback.recover(
            vision: { "from image" },
            textOnly: { XCTFail("text-only should not run"); return "nope" }
        )
        XCTAssertFalse(result.usedFallback)
        XCTAssertEqual(result.value, "from image")
    }

    func testNonVisionErrorsAreNotSwallowed() {
        XCTAssertFalse(VisionFallback.shouldRetryTextOnly(LlamaRunnerError.cancelled))
        XCTAssertFalse(VisionFallback.shouldRetryTextOnly(LlamaRunnerError.outOfMemory))
        XCTAssertThrowsError(
            try VisionFallback.recover(
                vision: { throw LlamaRunnerError.cancelled },
                textOnly: { "should not run" }
            )
        )
    }

    func testVisionUsesSmallUBatchAndCappedContext() {
        XCTAssertEqual(VisionEvalBudget.preferredUBatch, 512)
        XCTAssertEqual(VisionEvalBudget.maxUBatch, 768)
        XCTAssertEqual(VisionEvalBudget.imageMaxTokens, 256)
        XCTAssertEqual(VisionEvalBudget.visionNCtx, 4096)
        XCTAssertEqual(VisionEvalBudget.effectiveNCtx(requested: 8192, hasProjector: true), 4096)
        XCTAssertEqual(VisionEvalBudget.effectiveNCtx(requested: 8192, hasProjector: false), 8192)
        XCTAssertFalse(VisionEvalBudget.overflows(chunkTokens: 256, nCtx: 4096, maxTokens: 400))
    }

    func testProjectorPreflightRequiresFileTimes1_5Plus400MB() {
        let file: UInt64 = 1_000_000_000
        let need = MemoryPreflight.projectorNeed(fileBytes: file)
        XCTAssertEqual(need, UInt64(Double(file) * 1.5) + 400 * 1024 * 1024)
        XCTAssertFalse(MemoryPreflight.canLoadProjector(available: need - 1, fileBytes: file))
        XCTAssertTrue(MemoryPreflight.canLoadProjector(available: need, fileBytes: file))
    }

    func testModelPreflightIncludesKVEstimate() {
        let file: UInt64 = 3_106_738_272
        let nCtx = 4096
        let need = MemoryPreflight.modelNeed(fileBytes: file, nCtx: nCtx)
        XCTAssertEqual(need, UInt64(Double(file) * 1.2) + MemoryPreflight.kvEstimateBytes(nCtx: nCtx))
        XCTAssertFalse(MemoryPreflight.canLoadModel(available: 500_000_000, fileBytes: file, nCtx: nCtx))
        XCTAssertTrue(MemoryPreflight.canLoadModel(available: need + 1, fileBytes: file, nCtx: nCtx))
    }

    func testMemorySkipNoteAndFallback() throws {
        XCTAssertEqual(VisionEvalBudget.memorySkipNote, "Image skipped: not enough memory on this iPad")
        let result = try VisionFallback.recover(
            vision: { throw LlamaRunnerError.visionFailed(VisionEvalBudget.memorySkipNote) },
            textOnly: { "from text" }
        )
        XCTAssertTrue(result.usedFallback)
        XCTAssertEqual(VisionFallback.displayNote(for: LlamaRunnerError.visionFailed(VisionEvalBudget.memorySkipNote)),
                       VisionEvalBudget.memorySkipNote)
        XCTAssertEqual(VisionFallback.displayNote(for: LlamaRunnerError.visionFailed("mtmd eval failed (-1)")),
                       VisionEvalBudget.fallbackNote)
    }
}

final class GpuBudgetTests: XCTestCase {
    let e2b: UInt64 = 3_106_738_272
    let e4b: UInt64 = 4_977_171_584
    let e2bProj: UInt64 = 985_654_080
    let e4bProj: UInt64 = 990_372_672
    let gpuBudget = GpuBudget.ipadWorkingSetBytes
    let cpuPlenty: UInt64 = 6_700 * 1_048_576
    let cpuTight: UInt64 = 10 * 1_048_576
    let nCtx = 4096

    private var ipadAllocated: UInt64 {
        gpuBudget - GpuBudget.ipadFreeAtLaunchMiB * 1_048_576
    }

    func testE2BOnIpadProjectorGPUFullOffload() {
        let plan = GpuBudget.plan(
            gpuBudget: gpuBudget, gpuAllocated: ipadAllocated,
            modelBytes: e2b, projectorBytes: e2bProj,
            nCtx: nCtx, layerCount: 26, cpuAvailable: cpuPlenty
        )
        XCTAssertEqual(plan.nGpuLayers, GpuBudget.allLayers)
        XCTAssertTrue(plan.modelFitsGPU)
        XCTAssertEqual(plan.projector, .gpu)
    }

    func testE2BProjectorCPUWhenGPURemainderTooSmall() {
        let plan = GpuBudget.plan(
            gpuBudget: gpuBudget, gpuAllocated: gpuBudget - 50 * 1_048_576,
            modelBytes: e2b, projectorBytes: e2bProj,
            nCtx: nCtx, layerCount: 26, cpuAvailable: cpuPlenty
        )
        XCTAssertEqual(plan.projector, .cpu)
        XCTAssertFalse(plan.modelFitsGPU)
    }

    func testE2BProjectorSkipWhenCPUAlsoTight() {
        let plan = GpuBudget.plan(
            gpuBudget: gpuBudget, gpuAllocated: gpuBudget - 50 * 1_048_576,
            modelBytes: e2b, projectorBytes: e2bProj,
            nCtx: nCtx, layerCount: 26, cpuAvailable: cpuTight
        )
        XCTAssertEqual(plan.projector, .skip)
    }

    func testE4BOnIpadPartialOffloadProjectorCPU() {
        let plan = GpuBudget.plan(
            gpuBudget: gpuBudget, gpuAllocated: ipadAllocated,
            modelBytes: e4b, projectorBytes: e4bProj,
            nCtx: nCtx, layerCount: 34, cpuAvailable: cpuPlenty
        )
        XCTAssertFalse(plan.modelFitsGPU)
        XCTAssertGreaterThan(plan.nGpuLayers, 0)
        XCTAssertLessThan(plan.nGpuLayers, GpuBudget.allLayers)
        XCTAssertEqual(plan.projector, .cpu)
    }

    func testE4BPlentyGPUProjectorGPU() {
        let plan = GpuBudget.plan(
            gpuBudget: 16_000 * 1_048_576, gpuAllocated: 0,
            modelBytes: e4b, projectorBytes: e4bProj,
            nCtx: nCtx, layerCount: 34, cpuAvailable: cpuPlenty
        )
        XCTAssertTrue(plan.modelFitsGPU)
        XCTAssertEqual(plan.nGpuLayers, GpuBudget.allLayers)
        XCTAssertEqual(plan.projector, .gpu)
    }

    func testE4BProjectorSkipWhenCPUTight() {
        let plan = GpuBudget.plan(
            gpuBudget: gpuBudget, gpuAllocated: ipadAllocated,
            modelBytes: e4b, projectorBytes: e4bProj,
            nCtx: nCtx, layerCount: 34, cpuAvailable: cpuTight
        )
        XCTAssertEqual(plan.projector, .skip)
    }

    func testMemoryWarningUnloadsModelOnlyWhenIdle() {
        XCTAssertFalse(GpuBudget.unloadModelOnPressure(requestInFlight: true))
        XCTAssertTrue(GpuBudget.unloadModelOnPressure(requestInFlight: false))
    }

    func testLogLineNamesWorkingSetFields() {
        let snap = GpuBudget.Snapshot(budgetBytes: 5_726 * 1_048_576, allocatedBytes: 298 * 1_048_576)
        XCTAssertEqual(GpuBudget.logLine(snap), "PCVision gpuBudgetMB=5726 gpuAllocatedMB=298")
    }
}
