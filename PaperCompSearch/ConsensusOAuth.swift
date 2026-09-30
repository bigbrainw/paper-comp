import CryptoKit
import Foundation

/// Pure OAuth helpers for Consensus. Endpoints come from metadata, not literals in the flow.
enum ConsensusOAuth {
    static let callbackScheme = "papercomp"
    static let redirectURI = "papercomp://oauth/consensus"
    static let clientName = "PaperComp"
    static let resourceFallback = "https://mcp.consensus.app"
    static let limitNote = "Consensus limit reached"

    struct Metadata: Equatable, Sendable {
        var authorizationEndpoint: URL
        var tokenEndpoint: URL
        var registrationEndpoint: URL?
        var resource: String
        var scopes: [String]
    }

    static func parseMetadata(resourceJSON: [String: Any], serverJSON: [String: Any]) -> Metadata? {
        guard let auth = (serverJSON["authorization_endpoint"] as? String).flatMap(URL.init(string:)),
              let token = (serverJSON["token_endpoint"] as? String).flatMap(URL.init(string:)) else {
            return nil
        }
        let resource = (resourceJSON["resource"] as? String)
            ?? (resourceJSON["authorization_servers"] as? [String])?.first
            ?? resourceFallback
        let resourceScopes = resourceJSON["scopes_supported"] as? [String] ?? []
        let serverScopes = serverJSON["scopes_supported"] as? [String] ?? []
        var scopes = resourceScopes.isEmpty ? serverScopes : resourceScopes
        if !scopes.contains("search") { scopes.insert("search", at: 0) }
        return Metadata(
            authorizationEndpoint: auth,
            tokenEndpoint: token,
            registrationEndpoint: (serverJSON["registration_endpoint"] as? String).flatMap(URL.init(string:)),
            resource: resource,
            scopes: scopes
        )
    }

    static func authorizeScope(from meta: Metadata) -> String {
        let wanted = ["search", "profile"]
        let granted = wanted.filter { meta.scopes.contains($0) }
        return granted.isEmpty ? "search" : granted.joined(separator: " ")
    }

    static func registrationBody() -> [String: Any] {
        [
            "client_name": clientName,
            "redirect_uris": [redirectURI],
            "grant_types": ["authorization_code", "refresh_token"],
            "response_types": ["code"],
            "token_endpoint_auth_method": "none",
        ]
    }

    static func authorizeItems(clientID: String, challenge: String, state: String, meta: Metadata) -> [URLQueryItem] {
        [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "scope", value: authorizeScope(from: meta)),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "resource", value: meta.resource),
        ]
    }

    static func challenge(for verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return Data(digest).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func isLimitMessage(_ text: String) -> Bool {
        let lower = text.lowercased()
        return lower.contains("limit")
            || lower.contains("quota")
            || lower.contains("rate limit")
            || lower.contains("too many requests")
            || lower.contains("upgrade")
            || lower.contains("free tier")
    }

    static func email(fromTokenJSON object: [String: Any]) -> String? {
        if let email = object["email"] as? String, email.contains("@") { return email }
        if let info = object["user"] as? [String: Any],
           let email = info["email"] as? String, email.contains("@") {
            return email
        }
        return nil
    }

    static func searchArguments(query: String, pageSize: Int, argumentNames: [String]) -> [String: Any] {
        var args: [String: Any] = [:]
        if argumentNames.contains("question") {
            args["question"] = query
        } else {
            args["query"] = query
        }
        if argumentNames.contains("page_size") {
            args["page_size"] = pageSize
        } else if argumentNames.contains("pageSize") {
            args["pageSize"] = pageSize
        } else if argumentNames.contains("limit") {
            args["limit"] = pageSize
        }
        return args
    }
}
