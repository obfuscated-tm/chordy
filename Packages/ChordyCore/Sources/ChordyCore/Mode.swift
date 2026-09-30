import Foundation

public struct AppRef: Codable, Hashable, Sendable, Identifiable {
    public var bundleID: String
    public var name: String
    public var id: String { bundleID }

    public init(bundleID: String, name: String) {
        self.bundleID = bundleID
        self.name = name
    }
}

/// A way of dictating: how much to clean up, which rules to apply, and which apps it's for.
public struct Mode: Codable, Hashable, Sendable, Identifiable {
    public enum BuiltIn: String, Codable, Sendable, CaseIterable {
        case standard, prompt, terminal, essay, raw
    }

    public var id: UUID
    public var name: String
    public var symbol: String
    public var level: CleanupLevel
    public var devRules: Bool
    public var prefix: String
    public var suffix: String
    public var apps: [AppRef]
    /// Optional shortcut that always dictates in this mode, whatever app is in front.
    public var shortcut: Shortcut?
    /// Extra guidance for the LLM (Advanced). Empty for most people.
    public var customInstructions: String
    public var builtIn: BuiltIn?

    public init(
        id: UUID = UUID(), name: String, symbol: String, level: CleanupLevel, devRules: Bool,
        prefix: String = "", suffix: String = "", apps: [AppRef] = [], shortcut: Shortcut? = nil,
        customInstructions: String = "", builtIn: BuiltIn? = nil
    ) {
        self.id = id
        self.name = name
        self.symbol = symbol
        self.level = level
        self.devRules = devRules
        self.prefix = prefix
        self.suffix = suffix
        self.apps = apps
        self.shortcut = shortcut
        self.customInstructions = customInstructions
        self.builtIn = builtIn
    }

    public static func builtIn(_ kind: BuiltIn) -> Mode {
        // Fixed IDs so settings survive restarts and "Reset" can find them.
        let id = UUID(uuidString: "C40D0000-0000-0000-0000-00000000000\(BuiltIn.allCases.firstIndex(of: kind)!)")!
        switch kind {
        case .standard:
            return Mode(id: id, name: "Default", symbol: "text.bubble", level: .clean, devRules: true, builtIn: kind)
        case .prompt:
            return Mode(id: id, name: "Prompt", symbol: "sparkles", level: .smooth, devRules: true, apps: [
                AppRef(bundleID: "com.anthropic.claudefordesktop", name: "Claude"),
                AppRef(bundleID: "com.openai.chat", name: "ChatGPT"),
            ], builtIn: kind)
        case .terminal:
            return Mode(id: id, name: "Terminal", symbol: "terminal", level: .tidy, devRules: true, apps: [
                AppRef(bundleID: "com.apple.Terminal", name: "Terminal"),
                AppRef(bundleID: "com.googlecode.iterm2", name: "iTerm"),
                AppRef(bundleID: "com.mitchellh.ghostty", name: "Ghostty"),
                AppRef(bundleID: "dev.warp.Warp-Stable", name: "Warp"),
                AppRef(bundleID: "net.kovidgoyal.kitty", name: "kitty"),
                AppRef(bundleID: "org.alacritty", name: "Alacritty"),
                AppRef(bundleID: "com.github.wez.wezterm", name: "WezTerm"),
            ], builtIn: kind)
        case .essay:
            return Mode(id: id, name: "Essay", symbol: "doc.text", level: .clean, devRules: false, apps: [
                AppRef(bundleID: "com.apple.iWork.Pages", name: "Pages"),
                AppRef(bundleID: "com.microsoft.Word", name: "Microsoft Word"),
            ], builtIn: kind)
        case .raw:
            return Mode(id: id, name: "Raw", symbol: "waveform", level: .raw, devRules: false, builtIn: kind)
        }
    }

    public static var defaults: [Mode] { BuiltIn.allCases.map(builtIn) }

    /// The mode for the frontmost app: the first mode listing it, otherwise Default.
    public static func resolve(in modes: [Mode], bundleID: String?) -> Mode {
        if let bundleID, let match = modes.first(where: { $0.apps.contains { $0.bundleID == bundleID } }) {
            return match
        }
        return modes.first { $0.builtIn == .standard } ?? modes.first ?? .builtIn(.standard)
    }
}
