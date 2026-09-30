import Foundation

enum HTMLMainText {
    static func extract(_ html: String, cap: Int = 3_000) -> String {
        var text = html
        let dropBlocks = [
            #"(?is)<script[^>]*>.*?</script>"#,
            #"(?is)<style[^>]*>.*?</style>"#,
            #"(?is)<nav[^>]*>.*?</nav>"#,
            #"(?is)<footer[^>]*>.*?</footer>"#,
            #"(?is)<header[^>]*>.*?</header>"#,
            #"(?is)<noscript[^>]*>.*?</noscript>"#,
            #"(?is)<!--.*?-->"#,
        ]
        for pattern in dropBlocks {
            text = text.replacingOccurrences(of: pattern, with: " ", options: .regularExpression)
        }
        text = text.replacingOccurrences(of: #"(?is)<br\s*/?>"#, with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: #"(?is)</p>"#, with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: #"(?is)<[^>]+>"#, with: " ", options: .regularExpression)
        let entities: [(String, String)] = [
            ("&nbsp;", " "), ("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"),
            ("&quot;", "\""), ("&#39;", "'"), ("&apos;", "'"),
        ]
        for (entity, replacement) in entities {
            text = text.replacingOccurrences(of: entity, with: replacement)
        }
        text = text.replacingOccurrences(of: #"&#(\d+);"#, with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: #"[ \t]{2,}"#, with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.count > cap {
            return String(text.prefix(cap)).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
        }
        return text
    }
}
