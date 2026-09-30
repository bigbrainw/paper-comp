import XCTest
@testable import PaperComp

final class PromptFormatTests: XCTestCase {
    func testGemma4RenderMatchesOfficialTemplateWithoutBOS() {
        let rendered = PromptFormat.gemma4.render(system: "SYS", user: "USR")
        XCTAssertEqual(
            rendered,
            "<|turn>system\nSYS<turn|>\n<|turn>user\nUSR<turn|>\n<|turn>model\n"
        )
        XCTAssertFalse(rendered.contains("<bos>"))
        XCTAssertFalse(rendered.contains("<|think|>"))
    }

    func testGemma3AndChatMLRender() {
        XCTAssertEqual(
            PromptFormat.gemma3.render(system: "S", user: "U"),
            "<start_of_turn>user\nS\n\nU<end_of_turn>\n<start_of_turn>model\n"
        )
        XCTAssertEqual(
            PromptFormat.chatml.render(system: "S", user: "U"),
            "<|im_start|>system\nS<|im_end|>\n<|im_start|>user\nU<|im_end|>\n<|im_start|>assistant\n"
        )
    }

    func testInferFromGGUFTemplateString() {
        XCTAssertEqual(PromptFormat.infer(from: "…<|turn>user{{ content }}<turn|>…"), .gemma4)
        XCTAssertEqual(PromptFormat.infer(from: "<start_of_turn>user\n"), .gemma3)
        XCTAssertEqual(PromptFormat.infer(from: "<|im_start|>user"), .chatml)
        XCTAssertNil(PromptFormat.infer(from: nil))
        XCTAssertNil(PromptFormat.infer(from: "plain"))
    }

    func testResolvePrefersCatalogThenInference() {
        XCTAssertEqual(PromptFormat.resolve(catalog: .gemma4, template: "<|im_start|>"), .gemma4)
        XCTAssertEqual(PromptFormat.resolve(catalog: nil, template: "<|turn>system"), .gemma4)
        XCTAssertEqual(PromptFormat.resolve(catalog: nil, template: nil), .chatml)
    }
}
