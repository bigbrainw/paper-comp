import XCTest
@testable import PaperComp

final class GenerationStopTests: XCTestCase {
    func testBlankLineStopStringDoesNotEndGeneration() {
        let output = "**In short:** These terms describe the supplies.\n\n"
        XCTAssertFalse(GenerationStopPolicy.shouldStop(output: output, stop: "\n\n"))
        XCTAssertFalse(GenerationStopPolicy.shouldStop(output: output, stop: "\n**"))
        XCTAssertNil(GenerationStopPolicy.firstHonoredStop(in: output, stops: ["\n\n", "\n**"]))
    }

    func testHonoredStopStillMatches() {
        XCTAssertEqual(
            GenerationStopPolicy.firstHonoredStop(in: "hello<turn|>", stops: [PromptFormat.gemmaTurnClose]),
            PromptFormat.gemmaTurnClose
        )
        XCTAssertEqual(GenerationStopReason.maxTokens.logLabel, "maxTokens")
        XCTAssertTrue(GenerationStopReason.eog(id: 106, piece: "").logLabel.contains("eog"))
    }
}
