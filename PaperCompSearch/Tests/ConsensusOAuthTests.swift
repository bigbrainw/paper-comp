import XCTest
@testable import PaperComp

final class ConsensusOAuthTests: XCTestCase {
    func testParsesDiscoveredMetadata() {
        let resource: [String: Any] = [
            "resource": "https://mcp.consensus.app",
            "authorization_servers": ["https://consensus.app"],
            "scopes_supported": ["search", "profile"],
        ]
        let server: [String: Any] = [
            "authorization_endpoint": "https://consensus.app/oauth/authorize/",
            "token_endpoint": "https://consensus.app/oauth/token/",
            "registration_endpoint": "https://consensus.app/oauth/register/",
            "scopes_supported": ["search"],
        ]
        let meta = ConsensusOAuth.parseMetadata(resourceJSON: resource, serverJSON: server)!
        XCTAssertEqual(meta.authorizationEndpoint.absoluteString, "https://consensus.app/oauth/authorize/")
        XCTAssertEqual(meta.tokenEndpoint.absoluteString, "https://consensus.app/oauth/token/")
        XCTAssertEqual(meta.registrationEndpoint?.absoluteString, "https://consensus.app/oauth/register/")
        XCTAssertEqual(meta.resource, "https://mcp.consensus.app")
        XCTAssertEqual(ConsensusOAuth.authorizeScope(from: meta), "search profile")
    }

    func testRegistrationBodyIsPublicClient() {
        let body = ConsensusOAuth.registrationBody()
        XCTAssertEqual(body["client_name"] as? String, "PaperComp")
        XCTAssertEqual(body["redirect_uris"] as? [String], ["papercomp://oauth/consensus"])
        XCTAssertEqual(body["grant_types"] as? [String], ["authorization_code", "refresh_token"])
        XCTAssertEqual(body["token_endpoint_auth_method"] as? String, "none")
    }

    func testAuthorizeItemsIncludePKCEAndResource() {
        let meta = ConsensusOAuth.Metadata(
            authorizationEndpoint: URL(string: "https://consensus.app/oauth/authorize/")!,
            tokenEndpoint: URL(string: "https://consensus.app/oauth/token/")!,
            registrationEndpoint: URL(string: "https://consensus.app/oauth/register/")!,
            resource: "https://mcp.consensus.app",
            scopes: ["search"]
        )
        let items = ConsensusOAuth.authorizeItems(
            clientID: "cid", challenge: "abc", state: "st", meta: meta
        )
        let map = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(map["response_type"], "code")
        XCTAssertEqual(map["client_id"], "cid")
        XCTAssertEqual(map["redirect_uri"], "papercomp://oauth/consensus")
        XCTAssertEqual(map["scope"], "search")
        XCTAssertEqual(map["code_challenge"], "abc")
        XCTAssertEqual(map["code_challenge_method"], "S256")
        XCTAssertEqual(map["state"], "st")
        XCTAssertEqual(map["resource"], "https://mcp.consensus.app")
    }

    func testPKCEChallengeIsS256() {
        let verifier = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"
        XCTAssertEqual(ConsensusOAuth.challenge(for: verifier), "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    }

    func testLimitDetection() {
        XCTAssertTrue(ConsensusOAuth.isLimitMessage("Monthly quota exceeded"))
        XCTAssertTrue(ConsensusOAuth.isLimitMessage("Free tier limit reached"))
        XCTAssertFalse(ConsensusOAuth.isLimitMessage("No papers found"))
    }

    func testSearchArgumentsPreferQuestionWhenListed() {
        let args = ConsensusOAuth.searchArguments(query: "1/f noise", pageSize: 3, argumentNames: ["question", "page_size"])
        XCTAssertEqual(args["question"] as? String, "1/f noise")
        XCTAssertEqual(args["page_size"] as? Int, 3)
        XCTAssertNil(args["query"])
    }

    func testEmailFromTokenJSON() {
        XCTAssertEqual(ConsensusOAuth.email(fromTokenJSON: ["email": "a@b.com"]), "a@b.com")
        XCTAssertNil(ConsensusOAuth.email(fromTokenJSON: ["access_token": "x"]))
    }
}

final class ConsensusLimitFallbackTests: XCTestCase {
    func testLookupResultAddsLimitNote() {
        var result = ConsensusPaperParser.lookupResult([])
        result.note = ConsensusOAuth.limitNote
        XCTAssertEqual(result.note, "Consensus limit reached")
        XCTAssertTrue(result.sources.isEmpty)
    }

    func testOpenAlexParser() {
        let json = """
            {"results":[{"id":"https://openalex.org/W1","display_name":"Flicker noise","publication_year":2020,
            "doi":"https://doi.org/10.1/x","authorships":[{"author":{"display_name":"Ada"}}]}]}
            """
        let hits = LookupParsers.openAlexWorks(Data(json.utf8))
        XCTAssertEqual(hits.first?.title, "Flicker noise")
        XCTAssertEqual(hits.first?.year, 2020)
        XCTAssertEqual(hits.first?.doi, "10.1/x")
        XCTAssertEqual(hits.first?.authors, ["Ada"])
    }
}
