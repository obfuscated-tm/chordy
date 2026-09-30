import Foundation

/// Transcript → final text. Deterministic rules first, then the LLM, then the guard.
public struct Pipeline: Sendable {
    public struct Result: Sendable, Equatable {
        public var raw: String
        public var text: String
        public var usedLLM: Bool
        /// The LLM's output was thrown away for changing too much.
        public var guardRejected: Bool
    }

    /// Below this many words the LLM isn't worth the latency.
    public var minimumWordsForLLM = 4
    public var cleaner: (any TextCleaner)?

    public init(cleaner: (any TextCleaner)? = nil) {
        self.cleaner = cleaner
    }

    public func process(_ raw: String, level: CleanupLevel, devRules: Bool, prefix: String = "", suffix: String = "") async -> Result {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        var usedLLM = false
        var rejected = false

        if level >= .tidy { text = TextRules.tidy(text) }
        // Rules run before the LLM so it can't swallow spoken commands like "camel case".
        var vault = DevRules.Vault()
        if devRules, level >= .tidy { text = DevRules.apply(text, protectingIn: &vault) }
        if level >= .clean { text = TextRules.removeFillers(text) }

        if level.usesLLM, let cleaner, cleaner.isAvailable {
            // Line by line, so spoken line breaks survive the LLM.
            var lines = text.components(separatedBy: "\n")
            for i in lines.indices where lines[i].split(whereSeparator: \.isWhitespace).count >= minimumWordsForLLM {
                guard let cleaned = try? await cleaner.clean(lines[i], level: level) else { continue }
                usedLLM = true
                if vault.preserves(from: lines[i], in: cleaned),
                   DiffGuard.check(input: lines[i], output: cleaned, level: level).accepted {
                    lines[i] = cleaned
                } else {
                    rejected = true
                }
            }
            text = lines.joined(separator: "\n")
        }

        text = vault.restore(text)
        if text.isEmpty { return Result(raw: raw, text: "", usedLLM: usedLLM, guardRejected: rejected) }
        return Result(raw: raw, text: prefix + text + suffix, usedLLM: usedLLM, guardRejected: rejected)
    }
}
