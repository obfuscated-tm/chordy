import AppKit
import ChordyCore

enum ShortcutAction: String, CaseIterable, Identifiable, Codable {
    case dictate
    case dictateRaw

    var id: Self { self }

    var title: String {
        switch self {
        case .dictate: "Dictate"
        case .dictateRaw: "Dictate without cleanup"
        }
    }

    var subtitle: String {
        switch self {
        case .dictate: "Hold to talk · double-tap to lock hands-free"
        case .dictateRaw: "Pastes exactly what you said"
        }
    }

    var defaultShortcut: Shortcut {
        switch self {
        case .dictate: .modifierOnly([.fn])
        case .dictateRaw: .modifierOnly([.fn, .leftControl])
        }
    }
}

enum ShortcutStore {
    private static let key = "shortcuts"

    static func load() -> [ShortcutAction: Shortcut] {
        var result = Dictionary(uniqueKeysWithValues: ShortcutAction.allCases.map { ($0, $0.defaultShortcut) })
        if let data = UserDefaults.standard.data(forKey: key),
           let saved = try? JSONDecoder().decode([String: Shortcut].self, from: data) {
            for (id, shortcut) in saved {
                if let action = ShortcutAction(rawValue: id) { result[action] = shortcut }
            }
        }
        return result
    }

    static func save(_ shortcuts: [ShortcutAction: Shortcut]) {
        let raw = Dictionary(uniqueKeysWithValues: shortcuts.map { ($0.key.rawValue, $0.value) })
        if let data = try? JSONEncoder().encode(raw) { UserDefaults.standard.set(data, forKey: key) }
    }
}

enum KeyNames {
    static let special: [UInt16: String] = [
        49: "Space", 36: "↩", 48: "⇥", 51: "⌫", 117: "⌦", 53: "esc", 76: "⌤",
        123: "←", 124: "→", 125: "↓", 126: "↑", 115: "↖", 119: "↘", 116: "⇞", 121: "⇟",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8",
        101: "F9", 109: "F10", 103: "F11", 111: "F12", 105: "F13", 107: "F14", 113: "F15",
        106: "F16", 64: "F17", 79: "F18", 80: "F19", 90: "F20",
    ]

    static func isFunctionKey(_ code: UInt16) -> Bool {
        special[code]?.hasPrefix("F") == true
    }

    static func label(for event: NSEvent) -> String {
        if let name = special[event.keyCode] { return name }
        return (event.charactersIgnoringModifiers ?? "?").uppercased()
    }
}
