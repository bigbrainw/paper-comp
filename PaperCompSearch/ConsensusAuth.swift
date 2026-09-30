import AuthenticationServices
import Foundation
import UIKit

/// OAuth for a free Consensus account. Metadata is discovered; endpoints are not hardcoded.
@MainActor
final class ConsensusAuth: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = ConsensusAuth()

    var isConnected: Bool { Keychain.string(for: Keychain.consensusAccess) != nil }
    var connectedEmail: String? { Keychain.string(for: Keychain.consensusEmail) }

    private var authSession: ASWebAuthenticationSession?

    func validAccessToken() async -> String? {
        guard let token = Keychain.string(for: Keychain.consensusAccess) else { return nil }
        if let expiry = Keychain.string(for: Keychain.consensusExpiry),
           let interval = TimeInterval(expiry), Date().timeIntervalSince1970 > interval - 60 {
            return await refreshAccessToken() ?? token
        }
        return token
    }

    func connect() async throws {
        let meta = try await discover()
        let clientID = try await registeredClientID(meta: meta)
        let verifier = Self.randomURLSafe(32)
        let challenge = ConsensusOAuth.challenge(for: verifier)
        let state = Self.randomURLSafe(16)
        var components = URLComponents(url: meta.authorizationEndpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = ConsensusOAuth.authorizeItems(
            clientID: clientID, challenge: challenge, state: state, meta: meta
        )
        guard let url = components.url else { throw MCPError.decode("Bad authorize URL.") }
        let callback = try await startSession(url: url)
        guard let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems else {
            throw MCPError.decode("Missing OAuth callback query.")
        }
        if items.first(where: { $0.name == "state" })?.value != state {
            throw MCPError.decode("OAuth state mismatch.")
        }
        guard let code = items.first(where: { $0.name == "code" })?.value else {
            throw MCPError.decode("OAuth callback had no code.")
        }
        try await exchange(code: code, verifier: verifier, clientID: clientID, tokenURL: meta.tokenEndpoint)
    }

    func disconnect() {
        try? Keychain.delete(Keychain.consensusAccess)
        try? Keychain.delete(Keychain.consensusRefresh)
        try? Keychain.delete(Keychain.consensusExpiry)
        try? Keychain.delete(Keychain.consensusEmail)
    }

    func refreshAccessToken() async -> String? {
        await refresh()
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow } ?? ASPresentationAnchor()
    }

    private func startSession(url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: ConsensusOAuth.callbackScheme) { callback, error in
                if let error { continuation.resume(throwing: error) }
                else if let callback { continuation.resume(returning: callback) }
                else { continuation.resume(throwing: MCPError.decode("OAuth cancelled.")) }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            self.authSession = session
            if !session.start() {
                continuation.resume(throwing: MCPError.decode("Could not start the sign-in session."))
            }
        }
    }

    private func discover() async throws -> ConsensusOAuth.Metadata {
        let resourceURL = URL(string: "https://mcp.consensus.app/.well-known/oauth-protected-resource")!
        let resource = try await json(resourceURL)
        let issuer = (resource["authorization_servers"] as? [String])?.first ?? "https://consensus.app"
        let wellKnown = URL(string: issuer.hasSuffix("/")
            ? "\(issuer).well-known/oauth-authorization-server"
            : "\(issuer)/.well-known/oauth-authorization-server")!
        let server = try await json(wellKnown)
        guard let meta = ConsensusOAuth.parseMetadata(resourceJSON: resource, serverJSON: server) else {
            throw MCPError.decode("Authorization server metadata was incomplete.")
        }
        return meta
    }

    private func registeredClientID(meta: ConsensusOAuth.Metadata) async throws -> String {
        if let existing = Keychain.string(for: Keychain.consensusClientID) { return existing }
        guard let registration = meta.registrationEndpoint else {
            throw MCPError.decode("No registration_endpoint in metadata.")
        }
        var request = URLRequest(url: registration, timeoutInterval: 15)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ConsensusOAuth.registrationBody())
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw MCPError.http(http.statusCode)
        }
        let object = (try JSONSerialization.jsonObject(with: data)) as? [String: Any]
        guard let clientID = object?["client_id"] as? String else {
            throw MCPError.decode("Registration returned no client_id.")
        }
        try Keychain.set(clientID, for: Keychain.consensusClientID)
        return clientID
    }

    private func exchange(code: String, verifier: String, clientID: String, tokenURL: URL) async throws {
        try await storeTokens(from: tokenURL, form: [
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": ConsensusOAuth.redirectURI,
            "client_id": clientID,
            "code_verifier": verifier,
        ])
    }

    private func refresh() async -> String? {
        guard let refresh = Keychain.string(for: Keychain.consensusRefresh),
              let clientID = Keychain.string(for: Keychain.consensusClientID) else { return nil }
        do {
            let meta = try await discover()
            try await storeTokens(from: meta.tokenEndpoint, form: [
                "grant_type": "refresh_token",
                "refresh_token": refresh,
                "client_id": clientID,
            ])
            return Keychain.string(for: Keychain.consensusAccess)
        } catch {
            return nil
        }
    }

    private func storeTokens(from url: URL, form: [String: String]) async throws {
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = form
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw MCPError.http(http.statusCode)
        }
        let object = (try JSONSerialization.jsonObject(with: data)) as? [String: Any]
        guard let access = object?["access_token"] as? String else {
            throw MCPError.decode("Token response had no access_token.")
        }
        try Keychain.set(access, for: Keychain.consensusAccess)
        if let refresh = object?["refresh_token"] as? String {
            try Keychain.set(refresh, for: Keychain.consensusRefresh)
        }
        if let object, let email = ConsensusOAuth.email(fromTokenJSON: object) {
            try Keychain.set(email, for: Keychain.consensusEmail)
        }
        let expires = (object?["expires_in"] as? Int).map { Date().timeIntervalSince1970 + Double($0) } ?? (Date().timeIntervalSince1970 + 3600)
        try Keychain.set(String(Int(expires)), for: Keychain.consensusExpiry)
    }

    private func json(_ url: URL) async throws -> [String: Any] {
        let (data, response) = try await URLSession.shared.data(from: url)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw MCPError.http(http.statusCode)
        }
        return (try JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
    }

    private static func randomURLSafe(_ bytes: Int) -> String {
        var buffer = [UInt8](repeating: 0, count: bytes)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes, &buffer)
        return Data(buffer).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

}
