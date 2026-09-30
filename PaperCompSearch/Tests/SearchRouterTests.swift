import XCTest
@testable import PaperComp

final class SearchRouterTests: XCTestCase {
    func testAutoUsesOnDeviceWhenAvailable() {
        XCTAssertEqual(
            SearchRouter.route(preference: .auto, local: .available, hasOpenAIKey: true),
            .onDevice(fallbackToOpenAI: true)
        )
        XCTAssertEqual(
            SearchRouter.route(preference: .auto, local: .available, hasOpenAIKey: false),
            .onDevice(fallbackToOpenAI: false)
        )
    }

    func testAutoFallsBackToOpenAIWhenUnavailable() {
        XCTAssertEqual(
            SearchRouter.route(preference: .auto, local: .unavailable(reason: "off"), hasOpenAIKey: true),
            .openAI
        )
        XCTAssertEqual(
            SearchRouter.route(preference: .auto, local: .unavailable(reason: LocalModelStatus.downloadReason),
                               hasOpenAIKey: false),
            .onDeviceUnavailable(reason: LocalModelStatus.downloadReason)
        )
    }

    func testOnDeviceOnlyWithoutFallback() {
        XCTAssertEqual(
            SearchRouter.route(preference: .onDevice, local: .available, hasOpenAIKey: true),
            .onDevice(fallbackToOpenAI: false)
        )
    }

    func testOnDeviceOnlyWhenUnavailable() {
        let reason = "Download a local model in Settings to search on-device."
        XCTAssertEqual(
            SearchRouter.route(preference: .onDevice, local: .unavailable(reason: reason), hasOpenAIKey: true),
            .onDeviceUnavailable(reason: reason)
        )
    }

    func testOpenAIPreferenceAlwaysOpenAI() {
        XCTAssertEqual(
            SearchRouter.route(preference: .openAI, local: .available, hasOpenAIKey: true),
            .openAI
        )
        XCTAssertEqual(
            SearchRouter.route(preference: .openAI, local: .unavailable(reason: "x"), hasOpenAIKey: true),
            .openAI
        )
        XCTAssertEqual(
            SearchRouter.route(preference: .openAI, local: .available, hasOpenAIKey: false),
            .onDevice(fallbackToOpenAI: false)
        )
    }

    // MARK: BYOK

    func testNoKeyAlwaysOnDevice() {
        for preference in SearchEnginePreference.allCases {
            let route = SearchRouter.route(preference: preference, local: .available, hasOpenAIKey: false)
            XCTAssertEqual(route, .onDevice(fallbackToOpenAI: false), "\(preference)")
            let offline = SearchRouter.route(preference: preference, local: .unavailable(reason: "r"), hasOpenAIKey: false)
            XCTAssertNotEqual(offline, .openAI, "\(preference)")
        }
    }

    func testStoredPreferenceIgnoredWithoutKey() {
        XCTAssertEqual(SearchEnginePreference.resolved("openAI", hasOpenAIKey: false), .onDevice)
        XCTAssertEqual(SearchEnginePreference.resolved("auto", hasOpenAIKey: false), .onDevice)
        XCTAssertEqual(SearchEnginePreference.resolved("openAI", hasOpenAIKey: true), .openAI)
        XCTAssertEqual(SearchEnginePreference.resolved(nil, hasOpenAIKey: true), .onDevice)
        XCTAssertEqual(SearchEnginePreference.visibleCases(hasOpenAIKey: false), [.onDevice])
        XCTAssertEqual(SearchEnginePreference.visibleCases(hasOpenAIKey: true), SearchEnginePreference.allCases)
    }

    func testKeyAndOpenAIPreferenceRoutesToOpenAI() {
        XCTAssertEqual(SearchRouter.route(preference: .openAI, local: .available, hasOpenAIKey: true), .openAI)
    }

    func testKeyAutoAndLocalAvailableFallsBackToOpenAI() {
        XCTAssertEqual(
            SearchRouter.route(preference: .auto, local: .available, hasOpenAIKey: true),
            .onDevice(fallbackToOpenAI: true)
        )
    }
}
