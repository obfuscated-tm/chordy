import Foundation

/// Rejects LLM output that changed too much, so the worst case is "slightly messy", never "wrong".
public enum DiffGuard {
    public struct Verdict: Equatable, Sendable {
        public var accepted: Bool
        /// Share of output words that weren't in the input (catches answering or adding content).
        public var novelRatio: Double
        /// Share of input words missing from the output (catches summarizing).
        public var droppedRatio: Double
    }

    static let assistantOpeners = ["sure", "here is", "here's", "certainly", "of course", "i can", "i'm sorry", "as an ai"]

    public static func check(input: String, output: String, level: CleanupLevel) -> Verdict {
        let a = words(input), b = words(output)
        guard !b.isEmpty else { return Verdict(accepted: a.isEmpty, novelRatio: 0, droppedRatio: a.isEmpty ? 0 : 1) }
        guard !a.isEmpty else { return Verdict(accepted: false, novelRatio: 1, droppedRatio: 0) }

        var pool = counts(a)
        var novel = 0
        for w in b {
            if let n = pool[w], n > 0 { pool[w] = n - 1 } else { novel += 1 }
        }
        let novelRatio = Double(novel) / Double(b.count)
        let droppedRatio = Double(pool.values.reduce(0, +)) / Double(a.count)

        let (maxNovel, maxDropped) = limits(for: level)
        let lower = output.lowercased().trimmingCharacters(in: .whitespaces)
        let soundsLikeAssistant = assistantOpeners.contains { lower.hasPrefix($0) }
            && !input.lowercased().trimmingCharacters(in: .whitespaces).hasPrefix(String(lower.prefix(4)))
        let tooLong = Double(b.count) > Double(a.count) * 1.5 + 3

        let accepted = novelRatio <= maxNovel && droppedRatio <= maxDropped && !soundsLikeAssistant && !tooLong
        return Verdict(accepted: accepted, novelRatio: novelRatio, droppedRatio: droppedRatio)
    }

    static func limits(for level: CleanupLevel) -> (novel: Double, dropped: Double) {
        switch level {
        case .raw, .tidy: (0, 0)
        case .clean: (0.15, 0.35)
        case .smooth: (0.30, 0.40)
        case .polish: (0.50, 0.50)
        }
    }

    static func words(_ s: String) -> [String] {
        s.lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "'" })
            .map(String.init)
    }

    static func counts(_ ws: [String]) -> [String: Int] {
        ws.reduce(into: [:]) { $0[$1, default: 0] += 1 }
    }
}
