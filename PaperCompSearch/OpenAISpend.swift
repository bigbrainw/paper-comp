import Foundation

struct OpenAIUsage: Equatable, Sendable {
    var inputTokens: Int
    var outputTokens: Int
    var webSearchCalls: Int
    /// Subset of `output_tokens`. Billed via `outputTokens` only — do not add this in.
    var reasoningTokens: Int = 0
}

/// gpt-5.6-luna list prices plus a flat web-search estimate. Month-to-date lives in UserDefaults.
enum OpenAISpend {
    static let defaultCapDollars = 5.0
    static let inputUSDPerMillion = 1.0
    static let outputUSDPerMillion = 6.0
    static let webSearchUSD = 0.025

    static let capKey = "openai.spend.cap"
    static let monthKey = "openai.spend.month"
    static let usedKey = "openai.spend.used"

    static let capReachedMessage = "Monthly GPT limit reached"

    struct Ledger: Equatable, Sendable {
        var month: String
        var used: Double
        var cap: Double

        var remaining: Double { max(0, cap - used) }

        func blocks(additional: Double = 0) -> Bool {
            used + additional >= cap && cap > 0
        }
    }

    static func cost(inputTokens: Int, outputTokens: Int, webSearchCalls: Int) -> Double {
        let input = Double(max(0, inputTokens)) / 1_000_000 * inputUSDPerMillion
        let output = Double(max(0, outputTokens)) / 1_000_000 * outputUSDPerMillion
        let search = Double(max(0, webSearchCalls)) * webSearchUSD
        return input + output + search
    }

    static func cost(_ usage: OpenAIUsage) -> Double {
        cost(inputTokens: usage.inputTokens, outputTokens: usage.outputTokens, webSearchCalls: usage.webSearchCalls)
    }

    static func monthStamp(_ date: Date = Date(), calendar: Calendar = .current) -> String {
        let year = calendar.component(.year, from: date)
        let month = calendar.component(.month, from: date)
        return String(format: "%04d-%02d", year, month)
    }

    static func usdString(_ value: Double) -> String {
        String(format: "$%.2f", value)
    }

    static func ledger(defaults: UserDefaults = .standard, now: Date = Date()) -> Ledger {
        let month = monthStamp(now)
        let storedMonth = defaults.string(forKey: monthKey)
        let cap = defaults.object(forKey: capKey) as? Double ?? defaultCapDollars
        let used = storedMonth == month ? defaults.double(forKey: usedKey) : 0
        return Ledger(month: month, used: used, cap: cap)
    }

    static func isAtCap(defaults: UserDefaults = .standard, now: Date = Date()) -> Bool {
        ledger(defaults: defaults, now: now).blocks()
    }

    static func record(_ usage: OpenAIUsage, defaults: UserDefaults = .standard, now: Date = Date()) {
        var current = ledger(defaults: defaults, now: now)
        current.used += cost(usage)
        defaults.set(current.month, forKey: monthKey)
        defaults.set(current.used, forKey: usedKey)
        if defaults.object(forKey: capKey) == nil {
            defaults.set(defaultCapDollars, forKey: capKey)
        }
    }
}
