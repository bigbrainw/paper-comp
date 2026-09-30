import Foundation
#if canImport(Metal)
import Metal
#endif

/// GPU working-set planner. The iPad binding limit is Metal's
/// `recommendedMaxWorkingSetSize`, not `os_proc_available_memory`.
enum GpuBudget {
    static let computeBytes: UInt64 = 300 * 1_048_576
    static let modelMargin = 1.15
    static let allLayers = 99
    /// Gemma 4 E4B-class files.
    static let largeModelBytes: UInt64 = 4_000_000_000
    /// Console: `recommendedMaxWorkingSetSize = 5726 MB`.
    static let ipadWorkingSetBytes: UInt64 = 5_726 * 1_048_576
    /// Console: `5428 MiB free` at `ggml_metal_device_init`.
    static let ipadFreeAtLaunchMiB: UInt64 = 5_428

    enum ProjectorPlacement: String, Equatable, Sendable {
        case gpu
        case cpu
        case skip
    }

    struct Plan: Equatable, Sendable {
        var nGpuLayers: Int
        var projector: ProjectorPlacement
        var modelFitsGPU: Bool
    }

    struct Snapshot: Equatable, Sendable {
        var budgetBytes: UInt64
        var allocatedBytes: UInt64

        var freeBytes: UInt64 {
            budgetBytes > allocatedBytes ? budgetBytes - allocatedBytes : 0
        }

        var budgetMB: UInt64 { budgetBytes / 1_048_576 }
        var allocatedMB: UInt64 { allocatedBytes / 1_048_576 }
    }

    static func estimatedLayers(fileBytes: UInt64) -> Int {
        fileBytes >= largeModelBytes ? 34 : 26
    }

    static func freeBytes(budget: UInt64, allocated: UInt64) -> UInt64 {
        budget > allocated ? budget - allocated : 0
    }

    static func modelGpuNeed(fileBytes: UInt64, kvBytes: UInt64) -> UInt64 {
        fileBytes + kvBytes + computeBytes
    }

    static func modelFitsGPU(fileBytes: UInt64, kvBytes: UInt64, gpuFree: UInt64) -> Bool {
        Double(modelGpuNeed(fileBytes: fileBytes, kvBytes: kvBytes)) * modelMargin <= Double(gpuFree)
    }

    /// Layers that fit in `gpuFree` after reserving KV + compute. `99` means full offload.
    static func nGpuLayers(
        fileBytes: UInt64,
        kvBytes: UInt64,
        layerCount: Int,
        gpuFree: UInt64
    ) -> Int {
        let layers = max(layerCount, 1)
        if modelFitsGPU(fileBytes: fileBytes, kvBytes: kvBytes, gpuFree: gpuFree) {
            return allLayers
        }
        let reserved = kvBytes + computeBytes
        guard gpuFree > reserved else { return 0 }
        let perLayer = max(UInt64(1), fileBytes / UInt64(layers))
        let fit = Int((gpuFree - reserved) / perLayer)
        return max(0, min(layers, fit))
    }

    static func projectorPlacement(
        projectorBytes: UInt64,
        gpuFreeAfterModel: UInt64,
        cpuAvailable: UInt64
    ) -> ProjectorPlacement {
        guard projectorBytes > 0 else { return .skip }
        if gpuFreeAfterModel >= projectorBytes { return .gpu }
        let cpuNeed = MemoryPreflight.projectorNeed(fileBytes: projectorBytes)
        if cpuAvailable == 0 || cpuAvailable >= cpuNeed { return .cpu }
        return .skip
    }

    static func plan(
        gpuBudget: UInt64,
        gpuAllocated: UInt64,
        modelBytes: UInt64,
        projectorBytes: UInt64,
        nCtx: Int,
        layerCount: Int? = nil,
        hidden: Int = 2304,
        cpuAvailable: UInt64
    ) -> Plan {
        let layers = layerCount ?? estimatedLayers(fileBytes: modelBytes)
        let kv = MemoryPreflight.kvEstimateBytes(nCtx: nCtx, layers: layers, hidden: hidden)
        let free = freeBytes(budget: gpuBudget, allocated: gpuAllocated)
        let nGpu = nGpuLayers(fileBytes: modelBytes, kvBytes: kv, layerCount: layers, gpuFree: free)
        let fits = modelFitsGPU(fileBytes: modelBytes, kvBytes: kv, gpuFree: free)
        let ratio: Double
        if nGpu >= allLayers || nGpu >= layers {
            ratio = 1
        } else if layers == 0 {
            ratio = 0
        } else {
            ratio = Double(nGpu) / Double(layers)
        }
        let modelGpuUsed = UInt64(Double(modelBytes) * ratio) + UInt64(Double(kv) * ratio) + computeBytes
        let freeAfter = free > modelGpuUsed ? free - modelGpuUsed : 0
        let projector = projectorPlacement(
            projectorBytes: projectorBytes,
            gpuFreeAfterModel: freeAfter,
            cpuAvailable: cpuAvailable
        )
        return Plan(nGpuLayers: nGpu, projector: projector, modelFitsGPU: fits)
    }

    /// Memory warning: never drop the model while a request is in flight.
    static func unloadModelOnPressure(requestInFlight: Bool) -> Bool {
        !requestInFlight
    }

    static func snapshot() -> Snapshot {
        #if canImport(Metal)
        if let device = MTLCreateSystemDefaultDevice() {
            return Snapshot(
                budgetBytes: UInt64(device.recommendedMaxWorkingSetSize),
                allocatedBytes: UInt64(device.currentAllocatedSize)
            )
        }
        #endif
        return Snapshot(budgetBytes: 0, allocatedBytes: 0)
    }

    static func logLine(_ snapshot: Snapshot) -> String {
        "PCVision gpuBudgetMB=\(snapshot.budgetMB) gpuAllocatedMB=\(snapshot.allocatedMB)"
    }
}
