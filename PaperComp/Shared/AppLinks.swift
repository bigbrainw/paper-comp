import Foundation

/// Where Settings → About opens the Privacy Policy and Support pages.
/// `nil` shows the copies of `site/privacy.html` / `site/support.html` bundled in the app (works offline).
/// Once `site/` is hosted, set these to the hosted pages (e.g. `URL(string: "https://…/privacy.html")`)
/// so the app shows the live versions; the App Store Connect URLs should match.
enum AppLinks {
    static let privacyURL: URL? = URL(string: "https://papercomp-site.vercel.app/privacy.html")
    static let supportURL: URL? = URL(string: "https://papercomp-site.vercel.app/support.html")

    static let privacyResource = "privacy"
    static let supportResource = "support"

    static var versionString: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }
}
