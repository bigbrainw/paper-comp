import Foundation
import Observation

/// The user's own OpenAI API key, kept only in this device's Keychain
/// (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, not synced).
/// `hasKey` is observable so Settings and the search card update right after save/remove.
@Observable
final class OpenAIKeyStore: @unchecked Sendable {
    static let shared = OpenAIKeyStore()

    @ObservationIgnored let service: String
    @ObservationIgnored let account: String
    private(set) var hasKey: Bool

    init(service: String = Keychain.service, account: String = Keychain.openAIUserAccount) {
        self.service = service
        self.account = account
        hasKey = Self.normalized(Keychain.string(for: account, service: service)) != nil
    }

    /// Read fresh from the Keychain each time; never cached in memory or logged.
    var key: String? {
        Self.normalized(Keychain.string(for: account, service: service))
    }

    func save(_ rawKey: String) throws {
        guard let value = Self.normalized(rawKey) else {
            try remove()
            return
        }
        try Keychain.set(value, for: account, service: service)
        hasKey = true
    }

    func remove() throws {
        try Keychain.delete(account, service: service)
        hasKey = false
    }

    static func normalized(_ raw: String?) -> String? {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }
}

/// One-time consent (App Store 5.1.2(i)) before any selection is sent to OpenAI.
enum OpenAIConsent {
    static let storageKey = "openai.consent.granted"

    static func isGranted(defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: storageKey)
    }

    static func grant(defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: storageKey)
    }

    static func revoke(defaults: UserDefaults = .standard) {
        defaults.set(false, forKey: storageKey)
    }
}

/// "Test key" in Settings: `GET /v1/models` with the candidate key.
enum OpenAIKeyTester {
    enum Result: Equatable, Sendable {
        case ok
        case invalid
        case networkError(String)
        case failed(Int)

        var message: String {
            switch self {
            case .ok: "Key works."
            case .invalid: "OpenAI rejected this key."
            case .networkError(let detail): "Couldn't reach OpenAI: \(detail)"
            case .failed(let code): "OpenAI returned HTTP \(code)."
            }
        }
    }

    static func test(key: String, session: URLSession = .shared) async -> Result {
        var request = URLRequest(url: OpenAIClient.baseURL.appending(path: "models"))
        request.httpMethod = "GET"
        request.timeoutInterval = 20
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        do {
            let (_, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { return .failed(0) }
            switch http.statusCode {
            case 200..<300: return .ok
            case 401, 403: return .invalid
            default: return .failed(http.statusCode)
            }
        } catch {
            return .networkError(error.localizedDescription)
        }
    }
}
