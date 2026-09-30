import Foundation

struct ResponsesRequest: Sendable {
    var model: String
    var instructions: String
    var text: String
    var imageJPEG: Data?
    var previousResponseID: String?
    var webSearch = true
    var reasoningEffort: String = OpenAIReasoningEffort.default.apiValue

    func encodeBody() throws -> Data {
        try JSONEncoder().encode(RequestBody(self))
    }
}

enum OpenAIError: LocalizedError, Equatable, Sendable {
    case missingKey
    case unauthorized
    case rateLimited
    case server(Int)
    case api(String)
    case monthlyCapReached
    case consentRequired

    var errorDescription: String? {
        switch self {
        case .missingKey: "Add your own OpenAI API key in Settings to use GPT."
        case .unauthorized: "OpenAI rejected the request (401)."
        case .rateLimited: "Rate limited by OpenAI (429). Wait a moment and retry."
        case .server(let code): "OpenAI is having trouble (\(code)). Try again."
        case .api(let message): message
        case .monthlyCapReached: OpenAISpend.capReachedMessage
        case .consentRequired: "Allow sending this selection to OpenAI to use GPT."
        }
    }
}

struct OpenAIClient: Sendable {
    static let baseURL = URL(string: "https://api.openai.com/v1")!

    var session: URLSession = .shared
    /// The user's own key; injected in tests. Never logged.
    var apiKey: @Sendable () -> String? = { OpenAIKeyStore.shared.key }
    /// Defense in depth: nothing leaves the device without the one-time consent.
    var hasConsent: @Sendable () -> Bool = { OpenAIConsent.isGranted() }

    func streamResponse(_ request: ResponsesRequest) -> AsyncThrowingStream<SearchEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let (bytes, response) = try await session.bytes(for: try makeStreamRequest(request))
                    if let failure = await Self.failure(for: response, body: { try await Self.collect(bytes) }) {
                        throw failure
                    }
                    var parser = SSEParser()
                    for try await line in bytes.lines {
                        for event in parser.parse(line: line) { try Self.yield(event, to: continuation) }
                    }
                    for event in parser.finish() { try Self.yield(event, to: continuation) }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func makeStreamRequest(_ request: ResponsesRequest) throws -> URLRequest {
        guard let apiKey = OpenAIKeyStore.normalized(apiKey()) else { throw OpenAIError.missingKey }
        guard hasConsent() else { throw OpenAIError.consentRequired }
        if OpenAISpend.isAtCap() { throw OpenAIError.monthlyCapReached }
        var urlRequest = URLRequest(url: Self.baseURL.appending(path: "responses"))
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        urlRequest.httpBody = try request.encodeBody()
        return urlRequest
    }

    private static func yield(_ event: SearchEvent, to continuation: AsyncThrowingStream<SearchEvent, Error>.Continuation) throws {
        if case .failed(let message) = event { throw OpenAIError.api(message) }
        continuation.yield(event)
    }

    private static func collect(_ bytes: URLSession.AsyncBytes) async throws -> Data {
        var data = Data()
        for try await byte in bytes {
            data.append(byte)
            if data.count > 64_000 { break }
        }
        return data
    }

    private static func failure(for response: URLResponse, body: () async throws -> Data) async -> OpenAIError? {
        guard let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) else { return nil }
        switch http.statusCode {
        case 401: return .unauthorized
        case 429: return .rateLimited
        case 500...: return .server(http.statusCode)
        default:
            let data = (try? await body()) ?? Data()
            struct Envelope: Decodable { struct Detail: Decodable { let message: String }; let error: Detail }
            let message = (try? JSONDecoder().decode(Envelope.self, from: data))?.error.message
            return .api(message ?? "Request failed with HTTP \(http.statusCode).")
        }
    }
}

private struct RequestBody: Encodable {
    struct Content: Encodable {
        let type: String
        var text: String?
        var imageURL: String?
        enum CodingKeys: String, CodingKey { case type, text, imageURL = "image_url" }
    }
    struct Message: Encodable {
        let role = "user"
        let content: [Content]
    }
    struct Tool: Encodable { let type: String }
    struct Reasoning: Encodable { let effort: String }

    let model: String
    let instructions: String
    let input: [Message]
    let tools: [Tool]
    let stream = true
    let previousResponseID: String?
    let reasoning: Reasoning

    enum CodingKeys: String, CodingKey {
        case model, instructions, input, tools, stream, reasoning
        case previousResponseID = "previous_response_id"
    }

    init(_ request: ResponsesRequest) {
        var content = [Content(type: "input_text", text: request.text)]
        if let jpeg = request.imageJPEG {
            content.append(Content(type: "input_image", imageURL: "data:image/jpeg;base64,\(jpeg.base64EncodedString())"))
        }
        model = request.model
        instructions = request.instructions
        input = [Message(content: content)]
        tools = request.webSearch ? [Tool(type: "web_search")] : []
        previousResponseID = request.previousResponseID
        reasoning = Reasoning(effort: request.reasoningEffort)
    }
}
