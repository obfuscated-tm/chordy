import Foundation

/// Spoken code conventions: file mentions and casing commands. Never touches text inside backticks.
public enum DevRules {
    public static func apply(_ text: String) -> String {
        var vault = Vault()
        let protected = apply(text, protectingIn: &vault)
        return vault.restore(protected)
    }

    /// Applies the rules, swapping every rule output and backtick span for a placeholder the LLM can't mangle.
    public static func apply(_ text: String, protectingIn vault: inout Vault) -> String {
        // Even indices are outside backticks.
        text.split(separator: "`", omittingEmptySubsequences: false)
            .enumerated()
            .map { part in
                part.offset.isMultiple(of: 2)
                    ? applyCasing(applyFileMentions(String(part.element), &vault), &vault)
                    : vault.store("`" + part.element + "`")
            }
            .joined()
    }

    /// Holds protected spans. Placeholders look like ⟦0⟧.
    public struct Vault: Sendable {
        public private(set) var items: [String] = []

        public init() {}

        mutating func store(_ s: String) -> String {
            items.append(s)
            return "⟦\(items.count - 1)⟧"
        }

        public func restore(_ text: String) -> String {
            var out = text
            for (i, item) in items.enumerated() { out = out.replacingOccurrences(of: "⟦\(i)⟧", with: item) }
            return out
        }

        /// True if `output` has exactly the placeholders `input` had, each once.
        public func preserves(from input: String, in output: String) -> Bool {
            items.indices.allSatisfy { i in
                let marker = "⟦\(i)⟧"
                return output.components(separatedBy: marker).count == input.components(separatedBy: marker).count
            }
        }
    }

    /// "at src slash app dot ts" → "@src/app.ts"
    static func applyFileMentions(_ text: String, _ vault: inout Vault) -> String {
        text.replacing(/(?i)\bat\s+((?:[\w.-]+\s+(?:slash|dot)\s+)+[\w.-]+)/) { match in
            let path = String(match.output.1)
                .replacing(/(?i)\s+slash\s+/, with: "/")
                .replacing(/(?i)\s+dot\s+/, with: ".")
            let trailingDot = path.hasSuffix(".")
            return vault.store("@" + (trailingDot ? String(path.dropLast()) : path)) + (trailingDot ? "." : "")
        }
    }

    /// Words that end a casing command's identifier ("camel case user name is broken" → "userName is broken").
    static let stopWords: Set<String> = [
        "is", "was", "are", "were", "the", "a", "an", "and", "or", "but", "to", "in", "of", "for",
        "with", "that", "this", "it", "on", "should", "then", "please", "from", "into", "as", "be",
        "now", "here", "there", "instead", "too", "again", "so", "because", "if", "when", "at", "by",
    ]

    /// "camel case user name" → "userName"; also snake, kebab, pascal and constant case. At most 4 words.
    static func applyCasing(_ text: String, _ vault: inout Vault) -> String {
        text.replacing(/(?i)\b(camel|snake|kebab|pascal|constant)\s+case\s+([A-Za-z0-9]+(?:\s+[A-Za-z0-9]+)*)/) { match in
            let style = match.output.1.lowercased()
            let all = match.output.2.split(separator: " ").map(String.init)
            var words: [String] = []
            for w in all {
                if words.count == 4 || (!words.isEmpty && stopWords.contains(w.lowercased())) { break }
                words.append(w.lowercased())
            }
            let rest = all.dropFirst(words.count).joined(separator: " ")
            let identifier = vault.store(format(words, style: style))
            return rest.isEmpty ? identifier : identifier + " " + rest
        }
    }

    static func format(_ words: [String], style: String) -> String {
        switch style {
        case "snake": words.joined(separator: "_")
        case "kebab": words.joined(separator: "-")
        case "constant": words.joined(separator: "_").uppercased()
        case "pascal": words.map(\.capitalized).joined()
        default: (words.first ?? "") + words.dropFirst().map(\.capitalized).joined()
        }
    }
}
