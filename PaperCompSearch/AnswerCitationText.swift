import SwiftUI
import UIKit

/// Renders an answer with tappable citation chips. Math is cleaned first so `$1/f$` never shows.
struct AnswerCitationText: View {
    let text: String
    var references: [PaperReference] = []
    var sources: [WebSource] = []
    var onAskAbout: ((PaperReference) -> Void)?

    @Environment(\.searchCardPalette) private var palette
    @State private var selectedPaper: PaperReference?
    @State private var selectedKind: CitationKind?
    @State private var showMissingRef = false

    var body: some View {
        TappableAnswerView(
            text: AnswerMath.render(text),
            ink: UIColor(palette.ink),
            accent: Theme.uiAccent,
            surface: Theme.uiCardSurface,
            onTap: handle
        )
        .popover(item: Binding(
            get: { selectedPaper.map { IdentifiedReference(ref: $0, kind: selectedKind) } },
            set: { selectedPaper = $0?.ref; if $0 == nil { selectedKind = nil } }
        )) { item in
            ReferencePopover(reference: item.ref, kind: item.kind, onAskAbout: onAskAbout)
        }
        .popover(isPresented: $showMissingRef) {
            MissingReferencePopover()
        }
    }

    private func handle(_ kind: CitationKind) {
        switch kind {
        case .source(let index):
            let source = sources[safe: index - 1]
            if let url = source?.url {
                SafariPresenter.present(url)
            }
        case .paper, .authorYear:
            if let found = CitationParser.resolve(kind, in: references) {
                selectedKind = kind
                selectedPaper = found
            } else {
                showMissingRef = true
            }
        }
    }
}

private struct IdentifiedReference: Identifiable {
    let ref: PaperReference
    let kind: CitationKind?
    var id: String { ref.marker + (ref.title ?? ref.raw) }
}

private struct MissingReferencePopover: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Reference not parsed yet")
                .font(.headline)
                .foregroundStyle(Theme.ink)
            Text("The reference list for this paper isn’t available, or this marker didn’t match an entry.")
                .font(.footnote)
                .foregroundStyle(Theme.inkSoft)
            Button("Jump to references section") { ReaderJump.referencesSection() }
                .buttonStyle(SearchCapsuleButtonStyle(prominent: true))
        }
        .padding(16)
        .frame(width: 280)
        .presentationCompactAdaptation(.popover)
    }
}

/// Intrinsic-height text view. Citations are NSLink chips so taps are real, not Markdown.
struct TappableAnswerView: UIViewRepresentable {
    let text: String
    let ink: UIColor
    let accent: UIColor
    let surface: UIColor
    let onTap: (CitationKind) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onTap: onTap) }

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.isEditable = false
        view.isScrollEnabled = false
        view.isSelectable = true
        view.backgroundColor = surface
        view.isOpaque = true
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        view.adjustsFontForContentSizeCategory = true
        view.delegate = context.coordinator
        view.linkTextAttributes = [
            .foregroundColor: accent,
            .underlineStyle: NSUnderlineStyle.single.rawValue,
        ]
        apply(to: view, context: context)
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        context.coordinator.onTap = onTap
        view.backgroundColor = surface
        view.isOpaque = true
        apply(to: view, context: context)
        view.invalidateIntrinsicContentSize()
    }

    // Must return `CGSize?` to satisfy `UIViewRepresentable`; a non-optional overload is never called,
    // and SwiftUI then falls back to the text view's stale intrinsic size (long answers were clipped).
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        let proposed = proposal.width ?? 0
        let width = proposed.isFinite && proposed > 0 ? proposed : SearchCardPlacement.cardWidth - 32
        guard width > 0 else { return .zero }
        let size = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: ceil(size.height))
    }

    private func apply(to view: UITextView, context: Context) {
        context.coordinator.kinds = [:]
        let markdown = AnswerMarkdown.nsAttributed(text, ink: ink)
        let attributed = AnswerMarkdown.applyingCitations(markdown, accent: accent, kinds: &context.coordinator.kinds)
        if view.attributedText != attributed {
            view.attributedText = attributed
        }
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var onTap: (CitationKind) -> Void
        var kinds: [URL: CitationKind] = [:]

        init(onTap: @escaping (CitationKind) -> Void) {
            self.onTap = onTap
        }

        func textView(_ textView: UITextView, shouldInteractWith url: URL,
                      in characterRange: NSRange, interaction: UITextItemInteraction) -> Bool {
            if let kind = kinds[url] {
                onTap(kind)
                return false
            }
            return true
        }
    }
}

enum SafariPresenter {
    static func present(_ url: URL) {
        NotificationCenter.default.post(name: .papercompOpenURL, object: url)
    }
}

extension Notification.Name {
    static let papercompOpenURL = Notification.Name("papercomp.openURL")
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

extension View {
    func safariLinkHost() -> some View {
        modifier(SafariSheetHost())
    }
}

private struct SafariSheetHost: ViewModifier {
    @State private var url: URL?

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .papercompOpenURL)) { note in
                url = note.object as? URL
            }
            .sheet(isPresented: Binding(get: { url != nil }, set: { if !$0 { url = nil } })) {
                if let url {
                    SafariView(url: url).ignoresSafeArea()
                }
            }
    }
}
