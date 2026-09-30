import Foundation

/// Why `LlamaRunner` left the sample loop. Logged in DEBUG as `PCGen stop=…`.
enum GenerationStopReason: Equatable, Sendable {
    case eog(id: Int32, piece: String)
    case turnClose
    case stopString(String)
    case maxTokens

    var logLabel: String {
        switch self {
        case .eog(let id, let piece):
            "eog id=\(id) piece=\(Self.oneLine(piece))"
        case .turnClose:
            "turnClose \(PromptFormat.gemmaTurnClose)"
        case .stopString(let stop):
            "stopString \(Self.oneLine(stop))"
        case .maxTokens:
            "maxTokens"
        }
    }

    private static func oneLine(_ text: String) -> String {
        let trimmed = text.replacingOccurrences(of: "\n", with: "\\n")
        return trimmed.isEmpty ? "∅" : String(trimmed.prefix(40))
    }
}

/// Stop strings that must not end generation (a blank line or a new bold heading).
enum GenerationStopPolicy {
    static let ignored = ["\n\n", "\n**", "\n"]

    static func firstHonoredStop(in output: String, stops: [String]) -> String? {
        stops.first { stop in
            !ignored.contains(stop) && !stop.isEmpty && output.contains(stop)
        }
    }

    static func shouldStop(output: String, stop: String) -> Bool {
        firstHonoredStop(in: output, stops: [stop]) != nil
    }
}
