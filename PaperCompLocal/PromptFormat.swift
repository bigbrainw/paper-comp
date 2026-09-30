import Foundation

enum PromptFormat: String, Codable, Equatable, Sendable {
    case gemma4
    case gemma3
    case chatml

    static let gemmaTurnClose = "<turn|>"

    static func infer(from template: String?) -> PromptFormat? {
        guard let template, !template.isEmpty else { return nil }
        if template.contains("<|turn>") || template.contains("<turn|>") { return .gemma4 }
        if template.contains("<start_of_turn>") { return .gemma3 }
        if template.contains("<|im_start|>") { return .chatml }
        return nil
    }

    static func resolve(catalog: PromptFormat?, template: String?) -> PromptFormat {
        catalog ?? infer(from: template) ?? .chatml
    }

    func render(system: String, user: String) -> String {
        switch self {
        case .gemma4:
            return "<|turn>system\n\(system)<turn|>\n<|turn>user\n\(user)<turn|>\n<|turn>model\n"
        case .gemma3:
            return "<start_of_turn>user\n\(system)\n\n\(user)<end_of_turn>\n<start_of_turn>model\n"
        case .chatml:
            return "<|im_start|>system\n\(system)<|im_end|>\n<|im_start|>user\n\(user)<|im_end|>\n<|im_start|>assistant\n"
        }
    }
}
