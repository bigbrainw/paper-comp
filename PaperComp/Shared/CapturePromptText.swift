import Foundation

/// Chooses PDF text vs handwriting OCR for prompts; text-only models get a clear vision note when ink lacks OCR.
enum CapturePromptText {
    struct Result: Equatable {
        let text: String
        /// When true, the caller should tell the user handwriting needs a vision-capable model.
        let needsVisionCapableModel: Bool
    }

    static func resolve(
        selectedText: String,
        handwritingText: String,
        containsInk: Bool,
        hasProjector: Bool
    ) -> Result {
        let selected = selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !selected.isEmpty { return Result(text: selected, needsVisionCapableModel: false) }
        let handwriting = handwritingText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !handwriting.isEmpty { return Result(text: handwriting, needsVisionCapableModel: false) }
        if hasProjector { return Result(text: "", needsVisionCapableModel: false) }
        if containsInk {
            return Result(text: "", needsVisionCapableModel: true)
        }
        return Result(text: "", needsVisionCapableModel: false)
    }

    static let visionRequiredNote =
        "This selection is handwriting. Download a vision-capable local model, or use GPT, to read it."
}
