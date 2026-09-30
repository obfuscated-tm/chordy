import Foundation

/// A word the transcriber should know, with optional mis-hearings to fix ("cordy" → "Chordy").
public struct VocabularyEntry: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var term: String
    public var soundsLike: [String]

    public init(id: UUID = UUID(), term: String, soundsLike: [String] = []) {
        self.id = id
        self.term = term
        self.soundsLike = soundsLike
    }
}

public struct Vocabulary: Codable, Hashable, Sendable {
    public var entries: [VocabularyEntry]

    public init(_ entries: [VocabularyEntry] = []) {
        self.entries = entries
    }

    public var terms: [String] { entries.map(\.term).filter { !$0.isEmpty } }

    /// Replaces known mis-hearings with the right spelling. Whole words only, case-insensitive.
    public func apply(_ text: String) -> String {
        var out = text
        for entry in entries where !entry.term.isEmpty {
            // Also normalise the term's own casing ("github" → "GitHub").
            for alias in entry.soundsLike + [entry.term] where !alias.isEmpty {
                let pattern = "(?<![\\w])" + NSRegularExpression.escapedPattern(for: alias) + "(?![\\w])"
                guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { continue }
                out = regex.stringByReplacingMatches(
                    in: out, range: NSRange(out.startIndex..., in: out),
                    withTemplate: NSRegularExpression.escapedTemplate(for: entry.term)
                )
            }
        }
        return out
    }
}

/// Say the trigger on its own and the expansion is pasted instead ("my email" → "me@example.com").
public struct Snippet: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var trigger: String
    public var expansion: String

    public init(id: UUID = UUID(), trigger: String, expansion: String) {
        self.id = id
        self.trigger = trigger
        self.expansion = expansion
    }

    public static func match(_ text: String, in snippets: [Snippet]) -> Snippet? {
        let spoken = normalize(text)
        guard !spoken.isEmpty else { return nil }
        return snippets.first { !$0.trigger.isEmpty && normalize($0.trigger) == spoken }
    }

    static func normalize(_ s: String) -> String {
        s.lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .joined(separator: " ")
    }
}
