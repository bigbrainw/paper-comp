import XCTest
@testable import PaperComp

final class OpenAIReasoningEffortTests: XCTestCase {
    func testRequestBodyIncludesReasoningEffortForEachValue() throws {
        for effort in OpenAIReasoningEffort.allCases {
            let request = ResponsesRequest(
                model: "gpt-5.6-luna",
                instructions: "x",
                text: "q",
                reasoningEffort: effort.apiValue
            )
            let object = try JSONSerialization.jsonObject(with: request.encodeBody()) as? [String: Any]
            let reasoning = object?["reasoning"] as? [String: Any]
            XCTAssertEqual(reasoning?["effort"] as? String, effort.rawValue, effort.rawValue)
        }
    }

    func testDefaultRequestBodySendsMediumEffort() throws {
        let request = ResponsesRequest(model: "gpt-5.6-luna", instructions: "x", text: "q")
        let object = try JSONSerialization.jsonObject(with: request.encodeBody()) as? [String: Any]
        let reasoning = object?["reasoning"] as? [String: Any]
        XCTAssertEqual(reasoning?["effort"] as? String, "medium")
    }

    func testUnknownAndLegacyStoredValuesFallBackToMedium() {
        XCTAssertEqual(OpenAIReasoningEffort.resolved(nil), .medium)
        XCTAssertEqual(OpenAIReasoningEffort.resolved(""), .medium)
        XCTAssertEqual(OpenAIReasoningEffort.resolved("minimal"), .medium)
        XCTAssertEqual(OpenAIReasoningEffort.resolved("MINIMAL"), .medium)
        XCTAssertEqual(OpenAIReasoningEffort.resolved("x-high"), .medium)
        XCTAssertEqual(OpenAIReasoningEffort.resolved("gpt-5.6-luna"), .medium)
        for effort in OpenAIReasoningEffort.allCases {
            XCTAssertEqual(OpenAIReasoningEffort.resolved(effort.rawValue), effort)
        }
    }

    func testDefaultStorageKeyAndTagShape() {
        XCTAssertEqual(OpenAIReasoningEffort.storageKey, "openAIReasoningEffort")
        XCTAssertEqual(OpenAIReasoningEffort.default, .medium)
        XCTAssertEqual(SearchSettings.displayName(for: SearchSettings.defaultModel), "GPT-5.6 Luna")
        XCTAssertEqual(
            "\(SearchSettings.displayName(for: SearchSettings.defaultModel)) · \(OpenAIReasoningEffort.medium.apiValue)",
            "GPT-5.6 Luna · medium"
        )
    }
}
