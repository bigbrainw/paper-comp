import Foundation

/// One conversation thread with a backend. Engines keep their own thread state, so
/// follow-ups sent to the same instance continue the conversation.
@MainActor
protocol SearchEngine: AnyObject {
    var kind: SearchEngineKind { get }
    var displayTag: String { get }
    func stream(question: String) -> AsyncThrowingStream<SearchEvent, Error>
}

extension SearchEngine {
    var displayTag: String { kind.tag }
}

/// The OpenAI Responses API with hosted web search. The first turn sends the capture and crop;
/// follow-ups chain with `previous_response_id`.
@MainActor
final class OpenAISearchEngine: SearchEngine {
    let kind: SearchEngineKind = .openAI
    var displayTag: String {
        "\(SearchSettings.displayName) · \(OpenAIReasoningEffort.current.apiValue)"
    }
    private let capture: CircleCapture
    private var previousResponseID: String?

    init(capture: CircleCapture) {
        self.capture = capture
    }

    func stream(question: String) -> AsyncThrowingStream<SearchEvent, Error> {
        if OpenAISpend.isAtCap() {
            return AsyncThrowingStream { $0.finish(throwing: OpenAIError.monthlyCapReached) }
        }
        let isFirst = previousResponseID == nil
        let request = ResponsesRequest(
            model: SearchSettings.model,
            instructions: SearchSettings.instructions,
            text: isFirst ? SearchAgent.prompt(for: capture, question: question) : question,
            imageJPEG: isFirst ? capture.image.searchJPEG() : nil,
            previousResponseID: previousResponseID,
            reasoningEffort: OpenAIReasoningEffort.current.apiValue
        )
        let upstream = OpenAIClient().streamResponse(request)
        return AsyncThrowingStream { continuation in
            let task = Task { @MainActor [weak self] in
                do {
                    for try await event in upstream {
                        if case .completed(let id, _) = event, let id, !id.isEmpty {
                            self?.previousResponseID = id
                        }
                        continuation.yield(event)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
