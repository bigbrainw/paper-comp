import XCTest
@testable import PaperComp

final class ThinkingStripTests: XCTestCase {
    func testStripsThinkBlockWhenModelUsesThinking() {
        let input = "Hello <think>hidden</think> world."
        XCTAssertEqual(ThinkingStrip.strip(input, usesThinking: true), "Hello world.")
    }

    func testStripsThinkBlockEvenWhenFlagIsFalse() {
        let input = "Hello <think>hidden</think> world."
        XCTAssertEqual(ThinkingStrip.strip(input, usesThinking: false), "Hello world.")
    }

    func testHidesUnterminatedThinkWhileStreaming() {
        let leaked = "IA\n<think>\nOkay, let's see. The user wants me to list technical terms"
        XCTAssertEqual(ThinkingStrip.strip(leaked, usesThinking: false), "IA")
        XCTAssertEqual(ThinkingStrip.strip("<think>Okay, let's see", usesThinking: false), "")
        XCTAssertEqual(ThinkingStrip.strip("Answer so far <thi", usesThinking: false), "Answer so far")
    }

    func testStripsGemmaThoughtChannelAndOrphanClose() {
        XCTAssertEqual(ThinkingStrip.strip("<|channel>thought\nFirst, I need to<channel|>VDD is the supply."), "VDD is the supply.")
        XCTAssertEqual(ThinkingStrip.strip("<|channel>thought\nFirst, I need to"), "")
        XCTAssertEqual(ThinkingStrip.strip("Okay, let's see.</think>Backend handles storage."), "Backend handles storage.")
    }

    func testNoThinkSuffixIsThinkingModelsOnly() {
        XCTAssertEqual(ThinkingStrip.userSuffix(disableThinking: true, usesThinking: true), " /no_think")
        XCTAssertEqual(ThinkingStrip.userSuffix(disableThinking: true, usesThinking: false), "")
        XCTAssertEqual(ThinkingStrip.userSuffixForQwen(disableThinking: true, modelID: "qwen3-1.7b-q4"), " /no_think")
        XCTAssertEqual(ThinkingStrip.userSuffixForQwen(disableThinking: true, modelID: "gemma4-e2b-q4"), "")
    }
}
