import Foundation
import Security

/// Minimal generic-password Keychain wrapper.
enum Keychain {
    static let service = "com.papercomp.openai"
    /// User-entered OpenAI key (bring your own key). Distinct from the legacy account below.
    static let openAIUserAccount = "openai-user-api-key"
    /// Account used by very old builds; purged on launch. Never the user key above.
    static let legacyOpenAIAccount = "openai-api-key"
    static let consensusAccess = "consensus-access-token"
    static let consensusRefresh = "consensus-refresh-token"
    static let consensusExpiry = "consensus-token-expiry"
    static let consensusClientID = "consensus-client-id"
    static let consensusEmail = "consensus-email"

    /// Deletes the key left by very old builds under `legacyOpenAIAccount`.
    /// Only ever touches that account, so the current user key survives launches.
    static func purgeLegacyOpenAIKey(service: String = service) {
        try? delete(legacyOpenAIAccount, service: service)
    }

    static func string(for account: String, service: String = service) -> String? {
        var query = baseQuery(account, service: service)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func set(_ value: String, for account: String, service: String = service) throws {
        let data = Data(value.utf8)
        let status = SecItemUpdate(baseQuery(account, service: service) as CFDictionary,
                                   [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var query = baseQuery(account, service: service)
            query[kSecValueData as String] = data
            query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            try check(SecItemAdd(query as CFDictionary, nil))
        } else {
            try check(status)
        }
    }

    static func delete(_ account: String, service: String = service) throws {
        let status = SecItemDelete(baseQuery(account, service: service) as CFDictionary)
        if status != errSecItemNotFound { try check(status) }
    }

    private static func baseQuery(_ account: String, service: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: false,
        ]
    }

    private static func check(_ status: OSStatus) throws {
        guard status == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status),
                          userInfo: [NSLocalizedDescriptionKey: SecCopyErrorMessageString(status, nil) as String? ?? "Keychain error \(status)"])
        }
    }
}
