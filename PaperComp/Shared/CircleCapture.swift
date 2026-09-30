import UIKit

/// What the user circled on a PDF page. Produced by the reader, consumed by the search agent.
struct CircleCapture: Identifiable, Equatable {
    let id = UUID()
    /// Stable ID of the PaperDocument this came from.
    let documentID: UUID
    let paperTitle: String
    let pageIndex: Int
    /// Bounding box of the circle in PDF page coordinates (points, origin bottom-left).
    let pageRect: CGRect
    /// Text found inside the circle. Empty for figures or scanned pages.
    let selectedText: String
    /// Vision OCR of handwriting / ink when `selectedText` was empty and ink was present. Kept separate from PDF text.
    let handwritingText: String
    /// True when live PencilKit ink was composited into `image` (not lasso chrome or markers).
    let containsInk: Bool
    /// Rendered crop of the circled region (PDF + ink), adaptive scale capped near 2048px long edge.
    let image: UIImage
    /// Roughly 1,500 characters of surrounding page text, for context.
    let surroundingText: String

    init(
        documentID: UUID,
        paperTitle: String,
        pageIndex: Int,
        pageRect: CGRect,
        selectedText: String,
        handwritingText: String = "",
        containsInk: Bool = false,
        image: UIImage,
        surroundingText: String
    ) {
        self.documentID = documentID
        self.paperTitle = paperTitle
        self.pageIndex = pageIndex
        self.pageRect = pageRect
        self.selectedText = selectedText
        self.handwritingText = handwritingText
        self.containsInk = containsInk
        self.image = image
        self.surroundingText = surroundingText
    }

    func withHandwritingText(_ text: String) -> CircleCapture {
        CircleCapture(
            documentID: documentID,
            paperTitle: paperTitle,
            pageIndex: pageIndex,
            pageRect: pageRect,
            selectedText: selectedText,
            handwritingText: text,
            containsInk: containsInk,
            image: image,
            surroundingText: surroundingText
        )
    }

    static func == (lhs: CircleCapture, rhs: CircleCapture) -> Bool { lhs.id == rhs.id }
}
