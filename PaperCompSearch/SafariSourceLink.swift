import SafariServices
import SwiftUI

struct SafariSourceLink: View {
    let source: WebSource
    @State private var showSafari = false

    var body: some View {
        Button {
            showSafari = true
        } label: {
            VStack(alignment: .leading, spacing: 1) {
                Text(source.title).font(.footnote).foregroundStyle(Theme.accent).lineLimit(2)
                Text(source.url.host() ?? source.url.absoluteString)
                    .font(.caption2)
                    .foregroundStyle(Theme.inkSoft)
            }
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("source.link")
        .sheet(isPresented: $showSafari) {
            SafariView(url: source.url)
                .ignoresSafeArea()
        }
    }
}

struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}
