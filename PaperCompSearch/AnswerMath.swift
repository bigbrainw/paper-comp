import Foundation

/// Turns `$…$` LaTeX snippets into Unicode so answers never show raw dollar signs.
enum AnswerMath {
    static func render(_ text: String) -> String {
        var result = replacePairs(in: text, delimiter: "$$")
        result = replacePairs(in: result, delimiter: "$")
        return result.replacingOccurrences(of: "$", with: "")
    }

    private static func replacePairs(in text: String, delimiter: String) -> String {
        var output = ""
        var remaining = text[...]
        while let start = remaining.range(of: delimiter) {
            output += remaining[..<start.lowerBound]
            let after = remaining[start.upperBound...]
            if let end = after.range(of: delimiter) {
                output += convert(String(after[..<end.lowerBound]))
                remaining = after[end.upperBound...]
            } else {
                output += convert(String(after))
                remaining = after[after.endIndex...]
                break
            }
        }
        output += remaining
        return output
    }

    static func convert(_ latex: String) -> String {
        var s = latex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty { return "" }

        let commands: [(String, String)] = [
            ("\\mathrm", ""), ("\\operatorname", ""), ("\\text", ""),
            ("\\left", ""), ("\\right", ""),
            ("\\,", " "), ("\\;", " "), ("\\:", " "), ("\\!", ""),
            ("\\times", "×"), ("\\cdot", "·"), ("\\pm", "±"),
            ("\\approx", "≈"), ("\\neq", "≠"), ("\\leq", "≤"), ("\\geq", "≥"),
            ("\\infty", "∞"), ("\\partial", "∂"), ("\\sum", "Σ"),
            ("\\prod", "Π"), ("\\int", "∫"), ("\\sqrt", "√"),
            ("\\alpha", "α"), ("\\beta", "β"), ("\\gamma", "γ"), ("\\delta", "δ"),
            ("\\epsilon", "ε"), ("\\varepsilon", "ε"), ("\\theta", "θ"),
            ("\\lambda", "λ"), ("\\mu", "μ"), ("\\nu", "ν"), ("\\pi", "π"),
            ("\\rho", "ρ"), ("\\sigma", "σ"), ("\\tau", "τ"), ("\\phi", "φ"),
            ("\\omega", "ω"), ("\\Gamma", "Γ"), ("\\Delta", "Δ"),
            ("\\Theta", "Θ"), ("\\Lambda", "Λ"), ("\\Pi", "Π"),
            ("\\Sigma", "Σ"), ("\\Phi", "Φ"), ("\\Omega", "Ω"),
            ("\\hbar", "ℏ"), ("\\ell", "ℓ"),
        ]
        for (command, replacement) in commands {
            s = s.replacingOccurrences(of: command, with: replacement)
        }

        s = replaceFrac(s)
        s = replaceScripts(s, marker: "^", map: superscripts)
        s = replaceScripts(s, marker: "_", map: subscripts)
        s = s.replacingOccurrences(of: "{", with: "")
        s = s.replacingOccurrences(of: "}", with: "")
        s = s.replacingOccurrences(of: "\\", with: "")
        return s
    }

    private static func replaceFrac(_ input: String) -> String {
        var s = input
        while let range = s.range(of: "\\frac") {
            var rest = s[range.upperBound...]
            guard let num = takeBrace(&rest) else { break }
            let afterNum = rest
            var denomRest = afterNum
            guard let den = takeBrace(&denomRest) else {
                s.replaceSubrange(range.lowerBound..<s.endIndex, with: "\(num)/")
                break
            }
            s.replaceSubrange(range.lowerBound..<denomRest.startIndex, with: "\(num)/\(den)")
        }
        return s
    }

    private static func takeBrace(_ rest: inout Substring) -> String? {
        while rest.first?.isWhitespace == true { rest = rest.dropFirst() }
        guard rest.first == "{" else { return nil }
        rest = rest.dropFirst()
        var depth = 1
        var body = ""
        while let char = rest.first {
            rest = rest.dropFirst()
            if char == "{" { depth += 1 }
            if char == "}" {
                depth -= 1
                if depth == 0 { return body }
            }
            if depth > 0 { body.append(char) }
        }
        return nil
    }

    private static func replaceScripts(_ input: String, marker: Character, map: [Character: Character]) -> String {
        var output = ""
        var chars = Array(input)
        var index = 0
        while index < chars.count {
            if chars[index] == marker, index + 1 < chars.count {
                if chars[index + 1] == "{", let close = chars[(index + 2)...].firstIndex(of: "}") {
                    output += mapped(String(chars[(index + 2)..<close]), map: map)
                    index = close + 1
                    continue
                }
                output.append(map[chars[index + 1]] ?? chars[index + 1])
                index += 2
                continue
            }
            output.append(chars[index])
            index += 1
        }
        return output
    }

    private static func mapped(_ text: String, map: [Character: Character]) -> String {
        String(text.map { map[$0] ?? $0 })
    }

    private static let superscripts: [Character: Character] = [
        "0": "⁰", "1": "¹", "2": "²", "3": "³", "4": "⁴",
        "5": "⁵", "6": "⁶", "7": "⁷", "8": "⁸", "9": "⁹",
        "+": "⁺", "-": "⁻", "n": "ⁿ", "i": "ⁱ",
    ]

    private static let subscripts: [Character: Character] = [
        "0": "₀", "1": "₁", "2": "₂", "3": "₃", "4": "₄",
        "5": "₅", "6": "₆", "7": "₇", "8": "₈", "9": "₉",
        "+": "₊", "-": "₋", "a": "ₐ", "e": "ₑ", "i": "ᵢ",
        "o": "ₒ", "x": "ₓ", "n": "ₙ",
    ]
}
