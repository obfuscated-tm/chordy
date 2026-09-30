import Foundation

/// Word-level diff between the raw transcript and the cleaned text, for the history view.
public enum WordDiff {
    public enum Kind: Sendable { case same, removed, added }

    public struct Segment: Equatable, Sendable {
        public var kind: Kind
        public var text: String
    }

    public static func diff(_ old: String, _ new: String) -> [Segment] {
        let a = old.split(whereSeparator: \.isWhitespace).map(String.init)
        let b = new.split(whereSeparator: \.isWhitespace).map(String.init)
        // Longest common subsequence table.
        var lcs = Array(repeating: Array(repeating: 0, count: b.count + 1), count: a.count + 1)
        for i in stride(from: a.count - 1, through: 0, by: -1) {
            for j in stride(from: b.count - 1, through: 0, by: -1) {
                lcs[i][j] = a[i] == b[j] ? lcs[i + 1][j + 1] + 1 : max(lcs[i + 1][j], lcs[i][j + 1])
            }
        }
        var out: [Segment] = []
        func push(_ kind: Kind, _ word: String) {
            if let last = out.last, last.kind == kind {
                out[out.count - 1].text += " " + word
            } else {
                out.append(Segment(kind: kind, text: word))
            }
        }
        var i = 0, j = 0
        while i < a.count || j < b.count {
            if i < a.count, j < b.count, a[i] == b[j] {
                push(.same, a[i]); i += 1; j += 1
            } else if i < a.count, j == b.count || lcs[i + 1][j] >= lcs[i][j + 1] {
                push(.removed, a[i]); i += 1
            } else {
                push(.added, b[j]); j += 1
            }
        }
        return out
    }
}
