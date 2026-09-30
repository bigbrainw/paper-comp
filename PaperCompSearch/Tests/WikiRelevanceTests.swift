import XCTest
@testable import PaperComp

final class WikiRelevanceTests: XCTestCase {
    private let eegPaper = WikiQueryContext(
        term: "MQA",
        paperTitle: "A Wearable Dry EEG Electrode with High Signal Integrity",
        brief: "This paper studies EEG electrode signal integrity at the scalp interface.",
        selection: "MQA"
    )

    private let mqaArticle = WikiSummary(
        title: "Master Quality Authenticated",
        description: "Audio codec",
        extract: "Master Quality Authenticated (MQA) is an audio coding format for digital music.",
        url: URL(string: "https://en.wikipedia.org/wiki/Master_Quality_Authenticated"),
        isDisambiguation: false
    )

    private let eegArticle = WikiSummary(
        title: "Electroencephalography",
        description: "Electrophysiological monitoring method",
        extract: "EEG is a method to record electrical activity of the brain using electrodes.",
        url: URL(string: "https://en.wikipedia.org/wiki/Electroencephalography"),
        isDisambiguation: false
    )

    func testQueryAddsPaperTopicKeywords() {
        let query = WikiRelevance.query(eegPaper)
        XCTAssertTrue(query.hasPrefix("MQA "), query)
        let lower = query.lowercased()
        XCTAssertTrue(lower.contains("eeg") || lower.contains("electrode") || lower.contains("signal"), query)
        XCTAssertFalse(lower.contains("master quality"), query)
    }

    func testTopicKeywordsPreferScientificTokens() {
        let topics = WikiRelevance.topicKeywords(
            title: eegPaper.paperTitle,
            brief: eegPaper.brief
        )
        let lower = Set(topics.map { $0.lowercased() })
        XCTAssertTrue(lower.contains("eeg"))
        XCTAssertTrue(lower.contains("electrode") || lower.contains("integrity") || lower.contains("signal"))
        XCTAssertFalse(lower.contains("a"))
        XCTAssertFalse(lower.contains("with"))
        XCTAssertFalse(lower.contains("paper"))
    }

    func testAcronymResultIsFilteredOut() {
        let keywords = WikiRelevance.matchKeywords(eegPaper)
        XCTAssertFalse(keywords.isEmpty)
        XCTAssertFalse(
            WikiRelevance.isRelevant(mqaArticle, keywords: keywords),
            "MQA audio article must not count as relevant to an EEG paper"
        )
    }

    func testOnTopicArticleIsKept() {
        let keywords = WikiRelevance.matchKeywords(eegPaper)
        XCTAssertTrue(WikiRelevance.isRelevant(eegArticle, keywords: keywords))
    }

    func testPickSkipsDisambiguationAndJunk() {
        let disambiguation = WikiSummary(
            title: "MQA",
            description: "Disambiguation",
            extract: "MQA may refer to Master Quality Authenticated or other topics.",
            url: URL(string: "https://en.wikipedia.org/wiki/MQA"),
            isDisambiguation: true
        )
        let keywords = WikiRelevance.matchKeywords(eegPaper)
        let picked = WikiRelevance.pick(
            summaries: [disambiguation, mqaArticle, eegArticle],
            keywords: keywords
        )
        XCTAssertEqual(picked?.title, "Electroencephalography")
    }

    func testAllFilteredMeansNoGoodSource() {
        let keywords = WikiRelevance.matchKeywords(eegPaper)
        XCTAssertNil(WikiRelevance.pick(summaries: [mqaArticle], keywords: keywords))
        XCTAssertEqual(WikiRelevance.noGoodSource, "No good source found")
    }

    func testStemMatchesPluralElectrodes() {
        XCTAssertEqual(WikiRelevance.stem("electrodes"), "electrode")
        XCTAssertEqual(WikiRelevance.stem("electrode"), "electrode")
        XCTAssertEqual(WikiRelevance.stem("electrodes"), WikiRelevance.stem("electrode"))
        XCTAssertEqual(WikiRelevance.stem("signals"), WikiRelevance.stem("signal"))
        XCTAssertEqual(WikiRelevance.stem("studies"), "study")
        XCTAssertEqual(WikiRelevance.stem("boxes"), "box")

        let paperKeys = WikiRelevance.matchKeywords(WikiQueryContext(
            term: "MQA",
            paperTitle: "Dry EEG electrode signal integrity",
            brief: nil,
            selection: "MQA"
        ))
        let articleKeys = Set(WikiRelevance.stems(from: ["EEG uses electrodes at the scalp."]))
        XCTAssertTrue(paperKeys.contains("electrode"))
        XCTAssertTrue(articleKeys.contains("electrode"))
        XCTAssertFalse(paperKeys.isDisjoint(with: articleKeys))
    }

    func testEmptyTopicDoesNotInventKeywords() {
        let bare = WikiQueryContext(term: "transformer", paperTitle: "", brief: nil, selection: "transformer")
        XCTAssertEqual(WikiRelevance.query(bare), "transformer")
        XCTAssertTrue(WikiRelevance.matchKeywords(bare).isEmpty)
        XCTAssertTrue(WikiRelevance.isRelevant(title: "Transformer", extract: "A model.", keywords: []))
    }
}
