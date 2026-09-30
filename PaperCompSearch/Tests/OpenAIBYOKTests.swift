import UIKit
import XCTest
@testable import PaperComp

/// Records every request aimed at api.openai.com and answers 500, so nothing real is ever called.
final class OpenAIRequestRecorder: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var _count = 0
    nonisolated(unsafe) private static var _status = 500

    static var count: Int { lock.withLock { _count } }
    static func reset(status: Int = 500) { lock.withLock { _count = 0; _status = status } }

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "api.openai.com"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let status = Self.lock.withLock { () -> Int in
            Self._count += 1
            return Self._status
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("{}".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    static func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [OpenAIRequestRecorder.self]
        return URLSession(configuration: config)
    }
}

final class OpenAIKeyStoreTests: XCTestCase {
    private let service = "com.papercomp.tests.openai"
    private let account = "test-user-key"
    private let fixture = "test-fixture-key-not-real"

    override func tearDown() {
        try? Keychain.delete(account, service: service)
        try? Keychain.delete(Keychain.legacyOpenAIAccount, service: service)
        try? Keychain.delete(Keychain.openAIUserAccount, service: service)
        super.tearDown()
    }

    func testSaveReadRemoveRoundTrip() throws {
        let store = OpenAIKeyStore(service: service, account: account)
        try store.remove()
        XCTAssertFalse(store.hasKey)
        XCTAssertNil(store.key)

        try store.save("  \(fixture)\n")
        XCTAssertTrue(store.hasKey)
        XCTAssertEqual(store.key, fixture)
        XCTAssertTrue(OpenAIKeyStore(service: service, account: account).hasKey, "a fresh store sees the saved key")

        try store.save("replacement-fixture")
        XCTAssertEqual(store.key, "replacement-fixture")

        try store.remove()
        XCTAssertFalse(store.hasKey)
        XCTAssertNil(store.key)
        XCTAssertFalse(OpenAIKeyStore(service: service, account: account).hasKey)
    }

    func testSavingBlankRemovesKey() throws {
        let store = OpenAIKeyStore(service: service, account: account)
        try store.save(fixture)
        try store.save("   ")
        XCTAssertFalse(store.hasKey)
        XCTAssertNil(store.key)
    }

    func testLegacyPurgeNeverDeletesUserKey() throws {
        XCTAssertNotEqual(Keychain.legacyOpenAIAccount, Keychain.openAIUserAccount)
        let store = OpenAIKeyStore(service: service, account: Keychain.openAIUserAccount)
        try store.save(fixture)
        try Keychain.set("legacy", for: Keychain.legacyOpenAIAccount, service: service)

        Keychain.purgeLegacyOpenAIKey(service: service)

        XCTAssertNil(Keychain.string(for: Keychain.legacyOpenAIAccount, service: service))
        XCTAssertEqual(store.key, fixture, "launch migration must keep the user's key")
    }
}

final class OpenAIClientKeyInjectionTests: XCTestCase {
    private let request = ResponsesRequest(model: "gpt-test", instructions: "i", text: "t")

    override func setUp() {
        super.setUp()
        OpenAIRequestRecorder.reset()
    }

    func testInjectedKeyGoesInAuthorizationHeader() throws {
        var client = OpenAIClient()
        client.apiKey = { "test-fixture-key" }
        client.hasConsent = { true }
        guard !OpenAISpend.isAtCap() else { throw XCTSkip("sim spend ledger is at cap") }
        let urlRequest = try client.makeStreamRequest(request)
        XCTAssertEqual(urlRequest.value(forHTTPHeaderField: "Authorization"), "Bearer test-fixture-key")
        XCTAssertEqual(urlRequest.url?.absoluteString, "https://api.openai.com/v1/responses")
    }

    func testMissingKeyThrowsWithoutRequest() async {
        var client = OpenAIClient(session: OpenAIRequestRecorder.session())
        client.apiKey = { nil }
        client.hasConsent = { true }
        await assertStreamFails(client, with: .missingKey)
        XCTAssertEqual(OpenAIRequestRecorder.count, 0)
    }

    func testNoConsentSendsNothingToOpenAI() async {
        var client = OpenAIClient(session: OpenAIRequestRecorder.session())
        client.apiKey = { "test-fixture-key" }
        client.hasConsent = { false }
        await assertStreamFails(client, with: .consentRequired)
        XCTAssertEqual(OpenAIRequestRecorder.count, 0)
    }

    private func assertStreamFails(_ client: OpenAIClient, with expected: OpenAIError,
                                   file: StaticString = #filePath, line: UInt = #line) async {
        do {
            for try await _ in client.streamResponse(request) {}
            XCTFail("expected \(expected)", file: file, line: line)
        } catch {
            XCTAssertEqual(error as? OpenAIError, expected, file: file, line: line)
        }
    }
}

final class OpenAIKeyTesterTests: XCTestCase {
    override func setUp() {
        super.setUp()
        OpenAIRequestRecorder.reset()
    }

    func testOkInvalidAndServerError() async {
        OpenAIRequestRecorder.reset(status: 200)
        let okResult = await OpenAIKeyTester.test(key: "k", session: OpenAIRequestRecorder.session())
        XCTAssertEqual(okResult, .ok)
        OpenAIRequestRecorder.reset(status: 401)
        let invalidResult = await OpenAIKeyTester.test(key: "k", session: OpenAIRequestRecorder.session())
        XCTAssertEqual(invalidResult, .invalid)
        OpenAIRequestRecorder.reset(status: 503)
        let serverResult = await OpenAIKeyTester.test(key: "k", session: OpenAIRequestRecorder.session())
        XCTAssertEqual(serverResult, .failed(503))
    }
}

@MainActor
final class OpenAIConsentGateTests: XCTestCase {
    override func setUp() {
        super.setUp()
        OpenAIRequestRecorder.reset()
        URLProtocol.registerClass(OpenAIRequestRecorder.self)
    }

    override func tearDown() {
        URLProtocol.unregisterClass(OpenAIRequestRecorder.self)
        super.tearDown()
    }

    private func capture() -> CircleCapture {
        CircleCapture(
            documentID: UUID(),
            paperTitle: "Consent",
            pageIndex: 0,
            pageRect: CGRect(x: 0, y: 0, width: 40, height: 20),
            selectedText: "entropy",
            image: UIImage(),
            surroundingText: ""
        )
    }

    func testConsentDefaultsOff() {
        let defaults = UserDefaults(suiteName: "consent-\(UUID().uuidString)")!
        XCTAssertFalse(OpenAIConsent.isGranted(defaults: defaults))
        OpenAIConsent.grant(defaults: defaults)
        XCTAssertTrue(OpenAIConsent.isGranted(defaults: defaults))
        OpenAIConsent.revoke(defaults: defaults)
        XCTAssertFalse(OpenAIConsent.isGranted(defaults: defaults))
    }

    func testRoutedToOpenAIWithoutConsentAsksFirstAndSendsNothing() async {
        let agent = SearchAgent(capture: capture(), hasOpenAIKey: { true }, hasOpenAIConsent: { false },
                                preference: { .openAI })
        await agent.ask("What is entropy?")

        XCTAssertEqual(agent.pendingOpenAIConsent, .route)
        XCTAssertNotEqual(agent.engineKind, .openAI)
        XCTAssertFalse(agent.status.isBusy)
        XCTAssertEqual(OpenAIRequestRecorder.count, 0)

        // "Not now": answer locally (or say the local model is unavailable), never OpenAI.
        await agent.resolveOpenAIConsent(allowed: false)?.value
        XCTAssertNil(agent.pendingOpenAIConsent)
        XCTAssertNotEqual(agent.engineKind, .openAI)
        if case .failed(let message) = agent.status {
            XCTAssertEqual(message, LocalModelStatus.downloadReason)
        }
        XCTAssertEqual(OpenAIRequestRecorder.count, 0)

        // Later questions on the same card stay local instead of re-asking.
        await agent.ask("And again?")
        XCTAssertNil(agent.pendingOpenAIConsent)
        XCTAssertEqual(OpenAIRequestRecorder.count, 0)
    }

    func testAskGPTInsteadWithoutConsentAsksFirst() async {
        let agent = SearchAgent(capture: capture(), hasOpenAIKey: { true }, hasOpenAIConsent: { false },
                                preference: { .onDevice })
        await agent.ask("What is entropy?")
        await agent.askGPTInstead()
        XCTAssertEqual(agent.pendingOpenAIConsent, .askGPT)
        XCTAssertEqual(OpenAIRequestRecorder.count, 0)
        await agent.resolveOpenAIConsent(allowed: false)?.value
        XCTAssertNil(agent.pendingOpenAIConsent)
        XCTAssertEqual(OpenAIRequestRecorder.count, 0)
    }

    func testNoKeyNeverAsksForConsentOrCallsOpenAI() async {
        let agent = SearchAgent(capture: capture(), hasOpenAIKey: { false }, hasOpenAIConsent: { false },
                                preference: { .openAI })
        await agent.ask("What is entropy?")
        XCTAssertNil(agent.pendingOpenAIConsent)
        XCTAssertNotEqual(agent.engineKind, .openAI)
        XCTAssertEqual(OpenAIRequestRecorder.count, 0)
    }
}
