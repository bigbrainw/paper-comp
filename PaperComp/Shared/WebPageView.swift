import SwiftUI
import UIKit
import WebKit

/// Shows one of the app's own pages (Privacy Policy, Support): the hosted URL from `AppLinks` when set,
/// otherwise the copy of `site/<resource>.html` bundled in the app, which works offline.
/// Only those pages load inside the view; web links open in Safari and mailto links open Mail.
struct AppPageView: View {
    let title: String
    let resource: String
    var hostedURL: URL?

    var body: some View {
        Group {
            if let source = WebPageSource.resolve(resource: resource, hostedURL: hostedURL) {
                WebPageView(source: source, fallback: WebPageSource.resolve(resource: resource, hostedURL: nil))
                    .ignoresSafeArea(edges: .bottom)
            } else {
                ContentUnavailableView(title, systemImage: "doc.text", description: Text("This page is missing from the app."))
                    .foregroundStyle(Theme.inkSoft)
            }
        }
        .background(Theme.rice)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.rice, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
    }
}

enum WebPageSource: Equatable {
    case bundled(URL)
    case hosted(URL)

    var url: URL {
        switch self {
        case .bundled(let url), .hosted(let url): url
        }
    }

    static func resolve(resource: String, hostedURL: URL?, bundle: Bundle = .main) -> WebPageSource? {
        if let hostedURL { return .hosted(hostedURL) }
        return bundle.url(forResource: resource, withExtension: "html").map(WebPageSource.bundled)
    }

    enum LinkAction: Equatable {
        /// Load inside the web view (the page itself, or another of the app's pages).
        case load
        /// Hand to the system: Safari for web links, Mail for mailto.
        case openExternally
        /// Nothing to show (e.g. a bundled page links to a page that isn't bundled).
        case ignore
    }

    /// Decides where a link tapped inside the page goes.
    func action(for url: URL, fileExists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }) -> LinkAction {
        let scheme = url.scheme?.lowercased()
        switch self {
        case .bundled:
            if url.isFileURL { return fileExists(url) ? .load : .ignore }
        case .hosted(let base):
            if scheme == "http" || scheme == "https", url.host() == base.host() { return .load }
        }
        switch scheme {
        case "http", "https", "mailto": return .openExternally
        case "about": return .load
        default: return .ignore
        }
    }
}

struct WebPageView: UIViewRepresentable {
    let source: WebPageSource
    var fallback: WebPageSource? = nil

    func makeCoordinator() -> Coordinator { Coordinator(source: source, fallback: fallback) }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.dataDetectorTypes = []
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        // Transparent until the page paints its own rice background, so there's no white flash in dark mode.
        webView.isOpaque = false
        webView.backgroundColor = Theme.uiRice
        webView.scrollView.backgroundColor = Theme.uiRice
        webView.allowsLinkPreview = false
        Self.load(source, in: webView)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.fallback = fallback
        guard context.coordinator.source != source else { return }
        context.coordinator.source = source
        context.coordinator.active = source
        Self.load(source, in: webView)
    }

    static func load(_ source: WebPageSource, in webView: WKWebView) {
        switch source {
        case .bundled(let url):
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        case .hosted(let url):
            webView.load(URLRequest(url: url))
        }
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        var source: WebPageSource
        var active: WebPageSource
        var fallback: WebPageSource?

        init(source: WebPageSource, fallback: WebPageSource?) {
            self.source = source
            self.active = source
            self.fallback = fallback
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error) {
            fallBack(in: webView, after: error)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
            fallBack(in: webView, after: error)
        }

        private func fallBack(in webView: WKWebView, after error: any Error) {
            let error = error as NSError
            if error.domain == NSURLErrorDomain, error.code == NSURLErrorCancelled { return }
            if error.domain == "WebKitErrorDomain", error.code == 102 { return }
            guard case .hosted = active, let fallback else { return }
            active = fallback
            WebPageView.load(fallback, in: webView)
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void
        ) {
            guard let url = navigationAction.request.url else { return decisionHandler(.cancel) }
            // Subframes and in-page anchors stay put.
            if navigationAction.targetFrame?.isMainFrame == false { return decisionHandler(.allow) }
            switch active.action(for: url) {
            case .load:
                decisionHandler(.allow)
            case .openExternally:
                decisionHandler(.cancel)
                UIApplication.shared.open(url)
            case .ignore:
                decisionHandler(.cancel)
            }
        }
    }
}
