/// How much Chordy is allowed to change what you said. Levels 0–1 are pure rules; 2+ use the LLM.
public enum CleanupLevel: Int, CaseIterable, Codable, Sendable, Comparable {
    case raw = 0
    case tidy = 1
    case clean = 2
    case smooth = 3
    case polish = 4

    public var name: String {
        switch self {
        case .raw: "Raw"
        case .tidy: "Tidy"
        case .clean: "Clean"
        case .smooth: "Smooth"
        case .polish: "Polish"
        }
    }

    public var usesLLM: Bool { self >= .clean }

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}
