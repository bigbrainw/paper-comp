import XCTest
@testable import PaperComp

final class ModelCatalogTests: XCTestCase {
    func testDecodesBundledCatalog() throws {
        let catalog = try ModelCatalog.loadBundled()
        XCTAssertGreaterThanOrEqual(catalog.models.count, 5)
        XCTAssertEqual(catalog.defaultModel?.id, "gemma4-e2b-q4")
        XCTAssertEqual(catalog.defaultModel?.byteSize, 3_106_738_272)
        XCTAssertFalse(catalog.defaultModel?.usesThinking ?? true)
        XCTAssertEqual(catalog.defaultModel?.nCtx, 8192)
        XCTAssertEqual(catalog.defaultModel?.projectorByteSize, 985_654_080)
        XCTAssertEqual(
            catalog.defaultModel?.projectorURL,
            "https://huggingface.co/unsloth/gemma-4-E2B-it-GGUF/resolve/main/mmproj-F16.gguf"
        )
        XCTAssertEqual(catalog.defaultModel?.totalByteSize, 3_106_738_272 + 985_654_080)
        XCTAssertEqual(try XCTUnwrap(catalog.entry(id: "qwen3-1.7b-q4")).note, "Fast but weak")
        XCTAssertNil(try XCTUnwrap(catalog.entry(id: "qwen3-1.7b-q4")).projectorURL)
        let e4b = try XCTUnwrap(catalog.entry(id: "gemma4-e4b-q4"))
        XCTAssertEqual(e4b.byteSize, 4_977_171_584)
        XCTAssertTrue(e4b.mayExceedMemoryOn8GB)
        XCTAssertEqual(e4b.projectorByteSize, 990_372_672)
        XCTAssertTrue(try XCTUnwrap(catalog.entry(id: "qwen3-1.7b-q4")).usesThinking)
        XCTAssertEqual(catalog.defaultModel?.promptFormat, .gemma4)
        XCTAssertEqual(try XCTUnwrap(catalog.entry(id: "qwen3-1.7b-q4")).promptFormat, .chatml)
        XCTAssertEqual(try XCTUnwrap(catalog.entry(id: "gemma3-1b-q4")).promptFormat, .gemma3)
    }

    func testDecodeSampleJSON() throws {
        let json = """
        {"models":[{"id":"a","name":"A","shortName":"A","downloadURL":"https://example.com/m.gguf","fileName":"m.gguf","byteSize":100,"isDefault":true}]}
        """
        let catalog = try JSONDecoder().decode(ModelCatalog.self, from: Data(json.utf8))
        XCTAssertEqual(catalog.models.first?.fileName, "m.gguf")
    }
}
