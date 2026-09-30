import Foundation

/// Transcript → final text. Deterministic rules first, then the LLM, then the guard.
public struct Pipeline: Sendable {
    public struct Options: Sendable {
        public var level: CleanupLevel
        public var devRules: Bool
        public var prefix: String
        public var suffix: String
        public var vocabulary: Vocabulary
        public var snippets: [Snippet]
        public var customInstructions: String

        public init(
            level: CleanupLevel, devRules: Bool, prefix: String = "", suffix: String = "",
            vocabulary: Vocabulary = Vocabulary(), snippets: [Snippet] = [], customInstructions: String = ""
        ) {
            self.level = level
            self.devRules = devRules
            self.prefix = prefix
            self.suffix = suffix
            self.vocabulary = vocabulary
            self.snippets = snippets
            self.customInstructions = customInstructions
        }

        public init(mode: Mode, vocabulary: Vocabulary = Vocabulary(), snippets: [Snippet] = []) {
            self.init(
                level: mode.level, devRules: mode.devRules, prefix: mode.prefix, suffix: mode.suffix,
                vocabulary: vocabulary, snippets: snippets, customInstructions: mode.customInstructions
            )
        }
    }

    public struct Result: Sendable, Equatable {
        public var raw: String
        public var text: String
        public var usedLLM: Bool
        /// The LLM's output was thrown away for changing too much.
        public var guardRejected: Bool
        public var snippet: Snippet?
    }

    /// Below this many words the LLM isn't worth the latency.
    public var minimumWordsForLLM = 4
    public var cleaner: (any TextCleaner)?

    public init(cleaner: (any TextCleaner)? = nil) {
        self.cleaner = cleaner
    }

    public func process(_ raw: String, level: CleanupLevel, devRules: Bool, prefix: String = "", suffix: String = "") async -> Result {
        await process(raw, options: Options(level: level, devRules: devRules, prefix: prefix, suffix: suffix))
    }

    public func process(_ raw: String, options: Options) async -> Result {
        let level = options.level
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        var usedLLM = false
        var rejected = false

        if level >= .tidy, let snippet = Snippet.match(text, in: options.snippets) {
            return Result(raw: raw, text: snippet.expansion, usedLLM: false, guardRejected: false, snippet: snippet)
        }

        if level >= .tidy {
            text = TextRules.tidy(text)
            text = options.vocabulary.apply(text)
        }
        // Rules run before the LLM so it can't swallow spoken commands like "camel case".
        var vault = DevRules.Vault()
        if options.devRules, level >= .tidy { text = DevRules.apply(text, protectingIn: &vault) }
        if level >= .clean { text = TextRules.removeFillers(text) }

        if level.usesLLM, let cleaner, cleaner.isAvailable {
            let context = CleanupContext(terms: options.vocabulary.terms, customInstructions: options.customInstructions)
            // Line by line, so spoken line breaks survive the LLM.
            var lines = text.components(separatedBy: "\n")
            for i in lines.indices where lines[i].split(whereSeparator: \.isWhitespace).count >= minimumWordsForLLM {
                guard let cleaned = try? await cleaner.clean(lines[i], level: level, context: context) else { continue }
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
        return Result(raw: raw, text: options.prefix + text + options.suffix, usedLLM: usedLLM, guardRejected: rejected)
    }
}
