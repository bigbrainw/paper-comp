import Foundation

enum SearchEngineKind: String, Sendable, Codable {
    case onDevice, openAI

    /// Small tag shown on each answer.
    var tag: String {
        switch self {
        case .onDevice: "On-device"
        case .openAI: "GPT"
        }
    }
}

/// Settings choice, stored under `"searchEngine"`.
enum SearchEnginePreference: String, CaseIterable, Sendable {
    case auto, onDevice, openAI

    static let storageKey = "searchEngine"

    static var current: SearchEnginePreference {
        resolved(UserDefaults.standard.string(forKey: storageKey), hasOpenAIKey: OpenAIKeyStore.shared.hasKey)
    }

    /// Without a user key every search stays on-device, whatever was stored.
    static func resolved(_ raw: String?, hasOpenAIKey: Bool) -> SearchEnginePreference {
        let stored = raw.flatMap(Self.init(rawValue:)) ?? .onDevice
        if !hasOpenAIKey, stored != .onDevice { return .onDevice }
        return stored
    }

    static var visibleCases: [SearchEnginePreference] {
        visibleCases(hasOpenAIKey: OpenAIKeyStore.shared.hasKey)
    }

    static func visibleCases(hasOpenAIKey: Bool) -> [SearchEnginePreference] {
        hasOpenAIKey ? allCases : [.onDevice]
    }

    var label: String {
        switch self {
        case .auto: "Auto"
        case .onDevice: "Local model"
        case .openAI: "OpenAI"
        }
    }
}

enum LocalModelAvailability: Equatable, Sendable {
    case available
    case unavailable(reason: String)
}

enum SearchRoute: Equatable, Sendable {
    /// Use the downloaded local GGUF model; on failure, retry with OpenAI when `fallbackToOpenAI`.
    case onDevice(fallbackToOpenAI: Bool)
    case openAI
    /// The user asked for on-device only, and it can't run here.
    case onDeviceUnavailable(reason: String)
}

enum SearchRouter {
    static func route(
        preference: SearchEnginePreference,
        local: LocalModelAvailability,
        hasOpenAIKey: Bool = OpenAIKeyStore.shared.hasKey
    ) -> SearchRoute {
        // No user key: every search stays on-device, whatever the stored preference.
        guard hasOpenAIKey else {
            switch local {
            case .available: return .onDevice(fallbackToOpenAI: false)
            case .unavailable(let reason): return .onDeviceUnavailable(reason: reason)
            }
        }
        return switch (preference, local) {
        case (.auto, .available): .onDevice(fallbackToOpenAI: true)
        case (.auto, .unavailable): .openAI
        case (.onDevice, .available): .onDevice(fallbackToOpenAI: false)
        case (.onDevice, .unavailable(let reason)): .onDeviceUnavailable(reason: reason)
        case (.openAI, _): .openAI
        }
    }
}
