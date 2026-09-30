import SwiftUI

/// One-time notice before anything is sent to OpenAI (App Store guideline 5.1.2(i)).
struct OpenAIConsentSheet: View {
    let onAllow: () -> Void
    let onDecline: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Send to OpenAI?", systemImage: "paperplane")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Theme.ink)
            Text("To answer with GPT, PaperComp sends this to OpenAI using your API key:")
                .foregroundStyle(Theme.ink)
            VStack(alignment: .leading, spacing: 8) {
                bullet("The text you selected")
                bullet("Nearby text from the paper, and its title")
                bullet("An image of the area you boxed or circled")
                bullet("Your question")
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.riceDeep, in: .rect(cornerRadius: Theme.cornerRadius, style: .continuous))
            Text("It goes straight from this iPad to OpenAI and is billed to your OpenAI account. OpenAI's privacy policy applies. PaperComp has no server and keeps nothing. You can turn this off in Settings.")
                .font(.footnote)
                .foregroundStyle(Theme.inkSoft)
            HStack(spacing: 12) {
                Button("Not now", action: onDecline)
                    .buttonStyle(SearchCapsuleButtonStyle())
                    .accessibilityIdentifier("openai.consent.decline")
                Spacer()
                Button("Allow", action: onAllow)
                    .buttonStyle(SearchCapsuleButtonStyle(prominent: true))
                    .accessibilityIdentifier("openai.consent.allow")
            }
        }
        .padding(24)
        .frame(maxWidth: 520)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Theme.rice)
        .environment(\.searchCardPalette, .light)
        .tint(Theme.accent)
        .fontDesign(.rounded)
        .presentationDetents([.medium])
        .interactiveDismissDisabled()
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Circle().fill(Theme.accent).frame(width: 5, height: 5)
            Text(text).font(.subheadline).foregroundStyle(Theme.ink)
        }
    }
}
