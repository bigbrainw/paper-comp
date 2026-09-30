import XCTest
@testable import PaperComp

@MainActor
final class ModelManagerStateTests: XCTestCase {
    func testDownloadStateTransitions() {
        let entry = ModelCatalogEntry(
            id: "test-model",
            name: "Test",
            shortName: "Test",
            downloadURL: "https://example.com/x.gguf",
            fileName: "x.gguf",
            byteSize: 1024,
            isDefault: false
        )
        var state: ModelDownloadState = .notDownloaded
        XCTAssertEqual(state, .notDownloaded)
        state = .downloading(progress: 0.42)
        XCTAssertEqual(state, .downloading(progress: 0.42))
        let url = URL(fileURLWithPath: "/tmp/x.gguf")
        state = .ready(url: url)
        if case .ready(let readyURL) = state {
            XCTAssertEqual(readyURL, url)
        } else {
            XCTFail("Expected ready state")
        }
        state = .failed("network")
        XCTAssertEqual(state, .failed("network"))
    }

    func testGemmaUpgradeOffer() {
        XCTAssertTrue(ModelManager.shouldOfferGemmaUpgrade(
            activeID: "qwen3-1.7b-q4",
            states: ["qwen3-1.7b-q4": .ready(url: URL(fileURLWithPath: "/tmp/q.gguf"))]
        ))
        XCTAssertFalse(ModelManager.shouldOfferGemmaUpgrade(
            activeID: "qwen3-1.7b-q4",
            states: ["gemma4-e2b-q4": .ready(url: URL(fileURLWithPath: "/tmp/g.gguf"))]
        ))
        XCTAssertFalse(ModelManager.shouldOfferGemmaUpgrade(activeID: "gemma4-e2b-q4", states: [:]))
    }

    func testRAMWarningThreshold() {
        let manager = ModelManager.shared
        let entry = ModelCatalogEntry(
            id: "huge",
            name: "Huge",
            shortName: "Huge",
            downloadURL: "https://example.com/h.gguf",
            fileName: "h.gguf",
            byteSize: Int64(ProcessInfo.processInfo.physicalMemory),
            isDefault: false
        )
        XCTAssertTrue(manager.warnsAboutRAM(for: entry))
    }
}
