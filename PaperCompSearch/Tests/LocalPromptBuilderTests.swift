import XCTest
@testable import PaperComp

final class LocalPromptBuilderTests: XCTestCase {
    func testBuildIncludesSnippetsAndWordLimitInstruction() {
        let snippets = [
            LocalPromptBuilder.SourceSnippet(index: 1, title: "Wikipedia", body: "Transformer architecture"),
            LocalPromptBuilder.SourceSnippet(index: 2, title: "Papers", body: "Attention Is All You Need"),
        ]
        let built = LocalPromptBuilder.build(
            paperTitle: "My Paper",
            circledText: "self-attention",
            surroundingText: "We use self-attention throughout the encoder.",
            question: "Define this.",
            snippets: snippets
        )
        XCTAssertTrue(built.system.contains("Answer the user's question directly"))
        XCTAssertTrue(built.user.contains("Selected passage (do not repeat it)"))
        XCTAssertTrue(built.user.contains("[S1] Wikipedia"))
        XCTAssertTrue(built.user.contains("[S2] Papers"))
        XCTAssertTrue(built.user.contains("Selected passage"))
        XCTAssertTrue(built.user.contains("Paper context"))
        XCTAssertTrue(built.user.contains("self-attention"))
        XCTAssertFalse(built.user.localizedCaseInsensitiveContains("circled"))
        XCTAssertFalse(built.user.localizedCaseInsensitiveContains("surrounding text"))
        XCTAssertFalse(built.user.contains("Nearby text"))
        XCTAssertFalse(built.user.contains("attached as an image"))
        XCTAssertFalse(built.user.contains("Paper brief"))
    }

    func testBuildMentionsAttachedImage() {
        let built = LocalPromptBuilder.build(
            paperTitle: "My Paper",
            circledText: "",
            surroundingText: "",
            question: "What is this figure?",
            snippets: [],
            includesImage: true
        )
        XCTAssertTrue(built.user.contains("attached as an image"))
    }

    func testBuildIncludesBriefPassagesAndReferences() {
        let built = LocalPromptBuilder.build(
            paperTitle: "My Paper",
            circledText: "[6]",
            surroundingText: "",
            question: "Find cited paper",
            snippets: [],
            paperBrief: "This paper introduces transformers.",
            passages: [PaperChunk(pageIndex: 2, text: "Related work discusses attention.")],
            references: [PaperReference(marker: "6", raw: "[6] Smith. A Title. 2020.", title: "A Title", authors: "Smith", year: "2020", arxivID: nil, doi: nil)]
        )
        XCTAssertTrue(built.user.contains("Paper brief"))
        XCTAssertTrue(built.user.contains("p.3"))
        XCTAssertTrue(built.user.contains("[6]"))
        XCTAssertTrue(built.user.contains("A Title"))
    }

    func testTeachingPromptOrderAndFormat() {
        let snippets = [LocalPromptBuilder.SourceSnippet(index: 1, title: "Wikipedia", body: "Flicker noise.")]
        let built = LocalPromptBuilder.build(
            paperTitle: "Circuits",
            circledText: "1/f noise is typically mitigated by dynamic circuit techniques.",
            surroundingText: "Chopping moves flicker out of band.",
            question: TeachChipPrompt.explain(terms: ["1/f noise", "dynamic circuit techniques"]),
            snippets: snippets,
            kind: .teach,
            terms: ["1/f noise", "dynamic circuit techniques"]
        )
        XCTAssertTrue(built.system.contains("patient tutor"))
        XCTAssertTrue(built.system.contains("In short"))
        XCTAssertTrue(built.user.contains("input-referred noise"))
        XCTAssertTrue(built.user.contains("[S1] Wikipedia"))
        XCTAssertTrue(built.user.contains("Hard terms: 1/f noise · dynamic circuit techniques"))
        let sourcesAt = built.user.range(of: "[S1] Wikipedia")!.lowerBound
        let passageAt = built.user.range(of: "1/f noise is typically")!.lowerBound
        let termsAt = built.user.range(of: "Hard terms: 1/f noise")!.lowerBound
        let questionAt = built.user.range(of: "Question: Breaking down:")!.lowerBound
        XCTAssertLessThan(sourcesAt, passageAt)
        XCTAssertLessThan(passageAt, termsAt)
        XCTAssertLessThan(termsAt, questionAt)
        XCTAssertFalse(built.user.localizedCaseInsensitiveContains("circled"))
    }

    func testChipQuestions() {
        XCTAssertEqual(
            TeachChipPrompt.explain(terms: ["1/f noise", "chopping"]),
            "Breaking down: 1/f noise · chopping"
        )
        XCTAssertEqual(TeachChipPrompt.define(terms: ["1/f noise"]), "Define 1/f noise in plain language.")
        XCTAssertEqual(TeachChipPrompt.simpler(), "Explain this passage to a first-year undergraduate, with an analogy.")
        XCTAssertEqual(
            TeachChipPrompt.explain(terms: []),
            "Breaking down the hard concepts in this figure"
        )
        XCTAssertFalse(TeachChipPrompt.explain(terms: []).contains("especially"))
        XCTAssertFalse(TeachChipPrompt.explain(terms: ["the hard concepts here"]).contains("especially"))
        XCTAssertFalse(TeachChipPrompt.explain(terms: []).contains("the hard concepts here"))
        XCTAssertEqual(
            TeachChipPrompt.displayed("Explain the concepts in this passage that a student would find hard, especially: the hard concepts here"),
            TeachChipPrompt.explain(terms: [])
        )
        XCTAssertEqual(
            TeachChipPrompt.define(terms: []),
            "Define the terms in this passage in plain language."
        )
        XCTAssertFalse(TeachChipPrompt.define(terms: []).contains("key terms in this passage"))
    }

    func testTrimmedContextCentersOnSnippet() {
        let context = String(repeating: "a", count: 200) + "needle" + String(repeating: "b", count: 200)
        let trimmed = LocalPrompt.trimmedContext(context, around: "needle", limit: 40)
        XCTAssertTrue(trimmed.contains("needle"))
        XCTAssertLessThanOrEqual(trimmed.count, 42)
    }
}
