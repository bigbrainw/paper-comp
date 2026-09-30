import Foundation
import PDFKit
import SwiftData
import Testing
@testable import PaperComp

@MainActor
struct SamplePaperTests {
    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: PaperDocument.self, PageDrawing.self, SearchRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    @Test func sampleIsBundled() throws {
        let url = try #require(SamplePaper.bundledURL())
        let size = try #require(try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int)
        #expect(size < 2_000_000)
    }

    @Test func importCreatesReadablePaperWithTitle() throws {
        let context = try makeContext()
        let document = try DocumentStore.importSamplePaper(into: context)
        defer { DocumentStore.delete(document, from: context) }

        #expect(document.id == SamplePaper.documentID)
        #expect(document.title == SamplePaper.title)
        #expect(!document.isNotebook)
        let pdf = try #require(PDFDocument(url: document.fileURL))
        #expect(pdf.pageCount == 7)
        #expect(document.pages.count == pdf.pageCount)
        let firstPage = try #require(pdf.page(at: 0)?.string)
        #expect(firstPage.contains("grouped-query attention"))
    }

    @Test func importingTwiceDoesNotDuplicate() throws {
        let context = try makeContext()
        let first = try DocumentStore.importSamplePaper(into: context)
        defer { DocumentStore.delete(first, from: context) }
        let second = try DocumentStore.importSamplePaper(into: context)
        #expect(first.id == second.id)
        #expect(try context.fetchCount(FetchDescriptor<PaperDocument>()) == 1)
    }

    @Test func attributionNamesPaperAndLicense() {
        #expect(SamplePaper.attribution.contains("arXiv:2305.13245"))
        #expect(SamplePaper.attribution.contains("CC BY 4.0"))
        #expect(SamplePaper.attribution.contains("Ainslie"))
        #expect(SamplePaper.licenseURL.absoluteString == "https://creativecommons.org/licenses/by/4.0/")
    }
}

@MainActor
struct AppPagesTests {
    @Test func policyAndSupportAreBundled() throws {
        #expect(AppLinks.privacyURL?.host == "papercomp-site.vercel.app" && AppLinks.supportURL?.host == "papercomp-site.vercel.app")
        for resource in [AppLinks.privacyResource, AppLinks.supportResource] {
            let source = try #require(WebPageSource.resolve(resource: resource, hostedURL: nil))
            guard case .bundled(let url) = source else { Issue.record("expected bundled"); continue }
            let html = try String(contentsOf: url, encoding: .utf8)
            #expect(html.contains("prefers-color-scheme: dark"))
        }
    }

    @Test func hostedURLWinsWhenSet() {
        let hosted = URL(string: "https://example.org/privacy.html")!
        #expect(WebPageSource.resolve(resource: "privacy", hostedURL: hosted) == .hosted(hosted))
    }

    @Test func bundledPageLinkRouting() throws {
        let page = URL(fileURLWithPath: "/App.app/support.html")
        let source = WebPageSource.bundled(page)
        let exists: (URL) -> Bool = { $0.lastPathComponent == "privacy.html" }
        #expect(source.action(for: URL(fileURLWithPath: "/App.app/privacy.html"), fileExists: exists) == .load)
        #expect(source.action(for: URL(fileURLWithPath: "/App.app/index.html"), fileExists: exists) == .ignore)
        #expect(source.action(for: URL(string: "https://openai.com/policies/")!, fileExists: exists) == .openExternally)
        #expect(source.action(for: URL(string: "mailto:someone@example.org")!, fileExists: exists) == .openExternally)
        #expect(source.action(for: URL(string: "javascript:alert(1)")!, fileExists: exists) == .ignore)
    }

    @Test func hostedPageKeepsSameHostInside() {
        let source = WebPageSource.hosted(URL(string: "https://example.org/privacy.html")!)
        #expect(source.action(for: URL(string: "https://example.org/support.html")!) == .load)
        #expect(source.action(for: URL(string: "https://huggingface.co/privacy")!) == .openExternally)
    }
}
