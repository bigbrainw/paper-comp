import Foundation

enum MCPError: LocalizedError, Equatable {
    case http(Int)
    case rpc(code: Int, message: String)
    case decode(String)
    case unauthorized
    case limited(String)

    var errorDescription: String? {
        switch self {
        case .http(let code): "MCP HTTP \(code)"
        case .rpc(_, let message): message
        case .decode(let message): message
        case .unauthorized: "Consensus requires a signed-in account."
        case .limited(let message): message
        }
    }
}

struct MCPTool: Equatable, Sendable {
    var name: String
    var description: String
    var argumentNames: [String] = []
}

struct MCPToolResult: Equatable, Sendable {
    var text: String
}

struct MCPSession: Equatable, Sendable {
    var sessionID: String?
    var protocolVersion: String
}

/// JSON-RPC 2.0 over Streamable HTTP. Handles `application/json` and `text/event-stream`.
struct MCPClient: Sendable {
    var endpoint: URL
    var session: URLSession
    var accessToken: String?
    var transport: any MCPTransporting

    init(endpoint: URL, session: URLSession = .shared, accessToken: String? = nil,
         transport: (any MCPTransporting)? = nil) {
        self.endpoint = endpoint
        self.session = session
        self.accessToken = accessToken
        self.transport = transport ?? URLSessionMCPTransport(session: session)
    }

    func initialize(clientName: String = "PaperComp", version: String = "0.1.0") async throws -> MCPSession {
        let body: [String: Any] = [
            "jsonrpc": "2.0",
            "id": 1,
            "method": "initialize",
            "params": [
                "protocolVersion": "2025-03-26",
                "capabilities": [:] as [String: Any],
                "clientInfo": ["name": clientName, "version": version],
            ],
        ]
        let (object, headers) = try await send(body, sessionID: nil)
        try throwIfRPCError(object)
        let result = object["result"] as? [String: Any] ?? [:]
        let version = result["protocolVersion"] as? String ?? "2025-03-26"
        let sessionID = headers["Mcp-Session-Id"] ?? headers["mcp-session-id"]
        var session = MCPSession(sessionID: sessionID, protocolVersion: version)
        try await notifyInitialized(session: &session)
        return session
    }

    func listTools(_ mcpSession: MCPSession) async throws -> [MCPTool] {
        let body: [String: Any] = ["jsonrpc": "2.0", "id": 2, "method": "tools/list", "params": [:]]
        let (object, _) = try await send(body, sessionID: mcpSession.sessionID)
        try throwIfRPCError(object)
        let tools = ((object["result"] as? [String: Any])?["tools"] as? [[String: Any]]) ?? []
        return tools.compactMap { tool in
            guard let name = tool["name"] as? String else { return nil }
            let schema = tool["inputSchema"] as? [String: Any]
            let props = schema?["properties"] as? [String: Any]
            return MCPTool(
                name: name,
                description: tool["description"] as? String ?? "",
                argumentNames: props.map { Array($0.keys) } ?? []
            )
        }
    }

    func callTool(_ mcpSession: MCPSession, name: String, arguments: [String: Any]) async throws -> MCPToolResult {
        let body: [String: Any] = [
            "jsonrpc": "2.0",
            "id": 3,
            "method": "tools/call",
            "params": ["name": name, "arguments": arguments],
        ]
        let (object, _) = try await send(body, sessionID: mcpSession.sessionID)
        try throwIfRPCError(object)
        let result = object["result"] as? [String: Any] ?? [:]
        let content = result["content"] as? [[String: Any]] ?? []
        let text = content.compactMap { $0["text"] as? String }.joined(separator: "\n")
        return MCPToolResult(text: text)
    }

    private func notifyInitialized(session: inout MCPSession) async throws {
        let body: [String: Any] = [
            "jsonrpc": "2.0",
            "method": "notifications/initialized",
            "params": [:] as [String: Any],
        ]
        _ = try await send(body, sessionID: session.sessionID, expectResult: false)
    }

    private func send(_ body: [String: Any], sessionID: String?, expectResult: Bool = true) async throws -> ([String: Any], [String: String]) {
        var request = URLRequest(url: endpoint, timeoutInterval: 30)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue("PaperComp/1.0", forHTTPHeaderField: "User-Agent")
        if let sessionID { request.setValue(sessionID, forHTTPHeaderField: "Mcp-Session-Id") }
        if let accessToken { request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization") }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, http) = try await transport.perform(request)
        if http.statusCode == 401 { throw MCPError.unauthorized }
        if http.statusCode == 429 { throw MCPError.limited("Consensus limit reached") }
        if !(200..<300).contains(http.statusCode), expectResult { throw MCPError.http(http.statusCode) }
        var headers: [String: String] = [:]
        http.allHeaderFields.forEach { key, value in
            headers["\(key)"] = "\(value)"
        }
        if data.isEmpty { return ([:], headers) }
        let object = try Self.decodePayload(data, contentType: http.value(forHTTPHeaderField: "Content-Type") ?? "")
        return (object, headers)
    }

    static func decodePayload(_ data: Data, contentType: String) throws -> [String: Any] {
        if contentType.contains("text/event-stream") {
            return try decodeSSE(data)
        }
        let object = try JSONSerialization.jsonObject(with: data)
        if let dict = object as? [String: Any] { return dict }
        throw MCPError.decode("Expected a JSON object.")
    }

    static func decodeSSE(_ data: Data) throws -> [String: Any] {
        let text = String(data: data, encoding: .utf8) ?? ""
        var payload: [String] = []
        for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = raw.hasSuffix("\r") ? String(raw.dropLast()) : String(raw)
            if line.hasPrefix("data:") {
                var value = line.dropFirst(5)
                if value.first == " " { value = value.dropFirst() }
                payload.append(String(value))
            } else if line.isEmpty, !payload.isEmpty {
                if let object = jsonObject(payload.joined(separator: "\n")) { return object }
                payload.removeAll()
            }
        }
        if let object = jsonObject(payload.joined(separator: "\n")) { return object }
        throw MCPError.decode("No JSON object in SSE stream.")
    }

    private static func jsonObject(_ text: String) -> [String: Any]? {
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return object
    }

    private func throwIfRPCError(_ object: [String: Any]) throws {
        guard let error = object["error"] as? [String: Any] else { return }
        let code = error["code"] as? Int ?? 0
        let message = error["message"] as? String ?? "MCP error"
        let lower = message.lowercased()
        if lower.contains("limit") || lower.contains("quota") || lower.contains("too many requests") {
            throw MCPError.limited(message)
        }
        throw MCPError.rpc(code: code, message: message)
    }
}

protocol MCPTransporting: Sendable {
    func perform(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

struct URLSessionMCPTransport: MCPTransporting {
    let session: URLSession
    func perform(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw MCPError.http(-1) }
        return (data, http)
    }
}
