import XCTest
@testable import PaperComp

final class MCPClientTests: XCTestCase {
    func testDecodeJSONRPCObject() throws {
        let data = Data(#"{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"2025-03-26"}}"#.utf8)
        let object = try MCPClient.decodePayload(data, contentType: "application/json")
        XCTAssertEqual((object["result"] as? [String: Any])?["protocolVersion"] as? String, "2025-03-26")
    }

    func testDecodeSSEMessage() throws {
        let sse = """
            event: message
            data: {"jsonrpc":"2.0","id":2,"result":{"tools":[{"name":"search","description":"Search papers"}]}}

            """
        let object = try MCPClient.decodePayload(Data(sse.utf8), contentType: "text/event-stream")
        let tools = ((object["result"] as? [String: Any])?["tools"] as? [[String: Any]]) ?? []
        XCTAssertEqual(tools.first?["name"] as? String, "search")
    }

    func testInitializeListAndCallAgainstFixture() async throws {
        let transport = FixtureMCPTransport()
        transport.responses = [
            FixtureMCPTransport.json(#"{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"2025-03-26"}}"#),
            FixtureMCPTransport.json(#"{}"#),
            FixtureMCPTransport.json(#"{"jsonrpc":"2.0","id":2,"result":{"tools":[{"name":"search"}]}}"#),
            FixtureMCPTransport.json(#"{"jsonrpc":"2.0","id":3,"result":{"content":[{"type":"text","text":"[1] [Hello](https://consensus.app/p/1)"}]}}"#),
        ]
        let client = MCPClient(endpoint: URL(string: "https://example.test/mcp")!, transport: transport)
        let session = try await client.initialize()
        XCTAssertEqual(session.sessionID, "sess-1")
        let tools = try await client.listTools(session)
        XCTAssertEqual(tools.map(\.name), ["search"])
        let result = try await client.callTool(session, name: "search", arguments: ["query": "creatine"])
        XCTAssertTrue(result.text.contains("Hello"))
    }

    func testUnauthorizedBecomesMCPError() async {
        let transport = FixtureMCPTransport()
        transport.status = 401
        transport.responses = [(Data(), "application/json")]
        let client = MCPClient(endpoint: URL(string: "https://example.test/mcp")!, transport: transport)
        do {
            _ = try await client.initialize()
            XCTFail("expected unauthorized")
        } catch let error as MCPError {
            XCTAssertEqual(error, .unauthorized)
        } catch {
            XCTFail("wrong error \(error)")
        }
    }
}

final class FixtureMCPTransport: MCPTransporting, @unchecked Sendable {
    var responses: [(Data, String)] = []
    var status = 200

    static func json(_ text: String) -> (Data, String) { (Data(text.utf8), "application/json") }

    func perform(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let payload = responses.isEmpty ? (Data(), "application/json") : responses.removeFirst()
        var headers = ["Content-Type": payload.1]
        if status == 200 { headers["Mcp-Session-Id"] = "sess-1" }
        let http = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: headers)!
        return (payload.0, http)
    }
}
