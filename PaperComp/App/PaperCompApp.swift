import SwiftData
import SwiftUI
import UIKit

@main
struct PaperCompApp: App {
    let container: ModelContainer

    init() {
        do {
            #if DEBUG
            if DocumentStore.usesScratchLibrary {
                container = try ModelContainer(
                    for: PaperDocument.self, PageDrawing.self, SearchRecord.self,
                    configurations: ModelConfiguration(isStoredInMemoryOnly: true)
                )
            } else {
                container = try ModelContainer(for: PaperDocument.self, PageDrawing.self, SearchRecord.self)
            }
            #else
            container = try ModelContainer(for: PaperDocument.self, PageDrawing.self, SearchRecord.self)
            #endif
        } catch {
            fatalError("Could not create the SwiftData container: \(error)")
        }
        Self.applyUIKitAppearance()
        LlamaLifecycle.install()
        Keychain.purgeLegacyOpenAIKey()
        #if DEBUG
        TouchProbe.install()
        #endif
    }

    var body: some Scene {
        WindowGroup {
            LibraryView()
                .tint(Theme.accent)
                .fontDesign(.rounded)
                .preferredColorScheme(nil)
                .observeLlamaLifecycle()
        }
        .modelContainer(container)
    }

    /// UIKit pieces (PDFView, alerts, text cursors, nav bar titles) don't read SwiftUI's tint.
    private static func applyUIKitAppearance() {
        UIWindow.appearance().tintColor = Theme.uiAccent
        UIView.appearance(whenContainedInInstancesOf: [UIAlertController.self]).tintColor = Theme.uiAccent

        let navBar = UINavigationBar.appearance()
        navBar.tintColor = Theme.uiAccent
        navBar.titleTextAttributes = [.foregroundColor: Theme.uiInk, .font: roundedFont(.headline)]
        navBar.largeTitleTextAttributes = [.foregroundColor: Theme.uiInk, .font: roundedFont(.largeTitle, bold: true)]
    }

    private static func roundedFont(_ style: UIFont.TextStyle, bold: Bool = false) -> UIFont {
        var descriptor = UIFontDescriptor.preferredFontDescriptor(withTextStyle: style)
        if bold, let boldDescriptor = descriptor.withSymbolicTraits(.traitBold) { descriptor = boldDescriptor }
        if let rounded = descriptor.withDesign(.rounded) { descriptor = rounded }
        return UIFont(descriptor: descriptor, size: 0)
    }
}
