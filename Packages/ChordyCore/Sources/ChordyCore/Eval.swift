import Foundation

/// One messy → clean example from Evals/cleanup.json.
public struct EvalCase: Codable, Sendable {
    public var level: CleanupLevel
    public var input: String
    public var expect: String
    public var note: String?
}

public enum Eval {
    /// Word overlap between two texts, 0–1, ignoring case and punctuation (Dice coefficient over the diff).
    public static func similarity(_ a: String, _ b: String) -> Double {
        let x = normalized(a), y = normalized(b)
        let total = words(x) + words(y)
        guard total > 0 else { return 1 }
        let same = WordDiff.diff(x, y).filter { $0.kind == .same }.reduce(0) { $0 + words($1.text) }
        return Double(2 * same) / Double(total)
    }

    public static func exact(_ a: String, _ b: String) -> Bool {
        a.trimmingCharacters(in: .whitespacesAndNewlines) == b.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func normalized(_ s: String) -> String {
        s.lowercased().unicodeScalars
            .map { CharacterSet.alphanumerics.contains($0) || $0 == "'" || $0 == "@" || $0 == "/" || $0 == "_" ? String($0) : " " }
            .joined()
    }

    static func words(_ s: String) -> Int {
        s.split(whereSeparator: \.isWhitespace).count
    }
}
