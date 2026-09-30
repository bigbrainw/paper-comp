import XCTest
@testable import PaperComp

final class OpenAISpendTests: XCTestCase {
    func testLunaTokenPricesAndWebSearchEstimate() {
        XCTAssertEqual(OpenAISpend.cost(inputTokens: 1_000_000, outputTokens: 0, webSearchCalls: 0), 1.0, accuracy: 0.000_001)
        XCTAssertEqual(OpenAISpend.cost(inputTokens: 0, outputTokens: 1_000_000, webSearchCalls: 0), 6.0, accuracy: 0.000_001)
        XCTAssertEqual(OpenAISpend.cost(inputTokens: 0, outputTokens: 0, webSearchCalls: 2), 0.05, accuracy: 0.000_001)
        let usage = OpenAIUsage(inputTokens: 1_200, outputTokens: 80, webSearchCalls: 1)
        let expected = Double(usage.inputTokens) / 1_000_000 * 1.0
            + Double(usage.outputTokens) / 1_000_000 * 6.0
            + Double(usage.webSearchCalls) * 0.025
        XCTAssertEqual(OpenAISpend.cost(usage), expected, accuracy: 0.000_001)
    }

    func testReasoningTokensAreNotAddedOnTopOfOutputTokens() {
        let usage = OpenAIUsage(inputTokens: 0, outputTokens: 80, webSearchCalls: 0, reasoningTokens: 50)
        XCTAssertLessThanOrEqual(usage.reasoningTokens, usage.outputTokens)
        XCTAssertEqual(
            OpenAISpend.cost(usage),
            OpenAISpend.cost(inputTokens: 0, outputTokens: 80, webSearchCalls: 0),
            accuracy: 0.000_001
        )
        XCTAssertNotEqual(
            OpenAISpend.cost(usage),
            OpenAISpend.cost(inputTokens: 0, outputTokens: 80 + 50, webSearchCalls: 0),
            accuracy: 0.000_001
        )
    }

    func testCapBlocksWhenUsedReachesDefaultFiveDollars() {
        let under = OpenAISpend.Ledger(month: "2026-09", used: 4.99, cap: OpenAISpend.defaultCapDollars)
        XCTAssertFalse(under.blocks())
        let at = OpenAISpend.Ledger(month: "2026-09", used: 5.0, cap: OpenAISpend.defaultCapDollars)
        XCTAssertTrue(at.blocks())
        XCTAssertEqual(OpenAIError.monthlyCapReached.localizedDescription, "Monthly GPT limit reached")
    }

    func testRecordUsesIsolatedDefaultsAndResetsOnNewMonth() {
        let suite = "OpenAISpendTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("2020-01", forKey: OpenAISpend.monthKey)
        defaults.set(4.2, forKey: OpenAISpend.usedKey)
        defaults.set(OpenAISpend.defaultCapDollars, forKey: OpenAISpend.capKey)

        let fresh = OpenAISpend.ledger(defaults: defaults, now: date(year: 2026, month: 9))
        XCTAssertEqual(fresh.used, 0, accuracy: 0.000_001)
        XCTAssertEqual(fresh.month, "2026-09")
        XCTAssertFalse(fresh.blocks())

        OpenAISpend.record(
            OpenAIUsage(inputTokens: 1_000_000, outputTokens: 0, webSearchCalls: 0),
            defaults: defaults,
            now: date(year: 2026, month: 9)
        )
        let after = OpenAISpend.ledger(defaults: defaults, now: date(year: 2026, month: 9))
        XCTAssertEqual(after.used, 1.0, accuracy: 0.000_001)
        XCTAssertFalse(OpenAISpend.isAtCap(defaults: defaults, now: date(year: 2026, month: 9)))

        defaults.set(5.0, forKey: OpenAISpend.usedKey)
        XCTAssertTrue(OpenAISpend.isAtCap(defaults: defaults, now: date(year: 2026, month: 9)))
    }

    func testUsdString() {
        XCTAssertEqual(OpenAISpend.usdString(1.2), "$1.20")
        XCTAssertEqual(OpenAISpend.usdString(5), "$5.00")
    }

    private func date(year: Int, month: Int) -> Date {
        var parts = DateComponents()
        parts.year = year
        parts.month = month
        parts.day = 15
        return Calendar(identifier: .gregorian).date(from: parts)!
    }
}
