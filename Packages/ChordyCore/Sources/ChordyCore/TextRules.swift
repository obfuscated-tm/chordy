import Foundation

/// Deterministic cleanup. Everything here is exact and instant; the LLM never has to get it right.
public enum TextRules {
    /// Level 1: strip transcriber artifacts, apply spoken line breaks, fix whitespace and capitalization.
    public static func tidy(_ text: String) -> String {
        var s = text
        s = s.replacing(/\[[A-Z_ ]+\]/, with: "")
        s = s.replacing(/(?i)[(*](music|applause|silence|laughter|inaudible|blank_audio)[)*]/, with: "")
        s = s.replacing(/(?i)[,.;]?\s*\bnew paragraph\b[,.;]?\s*/, with: "\n\n")
        s = s.replacing(/(?i)[,.;]?\s*\bnew line\b[,.;]?\s*/, with: "\n")
        s = normalizeWhitespace(s)
        return capitalizeSentenceStarts(s)
    }

    /// Level 2+ (before the LLM): drop filler sounds. Words like "like" are left to the LLM since they're often meaningful.
    public static func removeFillers(_ text: String) -> String {
        var s = text.replacing(/(?i)\b(u+m+|u+h+|e+r+m+|u+h+m+|h+m+)\b[,.]?/, with: "")
        s = s.replacing(/^\s*[,.]\s*/, with: "")
        s = s.replacing(/,\s*([,.?!])/) { $0.output.1 }
        s = normalizeWhitespace(s)
        return capitalizeSentenceStarts(s)
    }

    static func normalizeWhitespace(_ text: String) -> String {
        text.split(separator: "\n", omittingEmptySubsequences: false)
            .map { line in
                line.replacing(/[ \t]+/, with: " ")
                    .replacing(/\ ([,.?!;:])/) { String($0.output.1) }
                    .trimmingCharacters(in: .whitespaces)
            }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func capitalizeSentenceStarts(_ text: String) -> String {
        var chars = Array(text)
        var atStart = true
        for i in chars.indices {
            let c = chars[i]
            if atStart, c.isLetter {
                chars[i] = Character(c.uppercased())
                atStart = false
            } else if c == "\n" {
                atStart = true
            } else if !c.isWhitespace {
                atStart = false
            }
        }
        return String(chars)
    }
}
