import Foundation

/// The CC BY 4.0 arXiv paper bundled in every build, so the app can be tried without importing a PDF.
enum SamplePaper {
    /// Fixed so a second "Add sample paper" finds the existing copy instead of duplicating it.
    static let documentID = UUID(uuidString: "6A0C5E1B-2305-4132-9450-5A3B1E0C2305")!
    static let resourceName = "SamplePaper-2305.13245"
    static let title = "GQA: Training Generalized Multi-Query Transformer Models from Multi-Head Checkpoints"
    static let authors = "Joshua Ainslie, James Lee-Thorp, Michiel de Jong, Yury Zemlyanskiy, Federico Lebrón, Sumit Sanghai"
    static let arXivID = "2305.13245"
    static let licenseName = "CC BY 4.0"
    static let licenseURL = URL(string: "https://creativecommons.org/licenses/by/4.0/")!
    static let abstractURL = URL(string: "https://arxiv.org/abs/2305.13245")!

    /// One line for Settings → About.
    static var attribution: String {
        "Sample paper: “\(title)” by \(authors), arXiv:\(arXivID) (v3), licensed \(licenseName). Included unmodified."
    }

    static func bundledURL(in bundle: Bundle = .main) -> URL? {
        bundle.url(forResource: resourceName, withExtension: "pdf")
    }
}
