import Foundation

/// A physical modifier key. Raw values are macOS virtual key codes; left and right are distinct keys.
public enum ModifierKey: UInt16, Codable, CaseIterable, Sendable {
    case fn = 63
    case leftCommand = 55, rightCommand = 54
    case leftOption = 58, rightOption = 61
    case leftControl = 59, rightControl = 62
    case leftShift = 56, rightShift = 60

    public var family: ModifierFamily {
        switch self {
        case .fn: .function
        case .leftCommand, .rightCommand: .command
        case .leftOption, .rightOption: .option
        case .leftControl, .rightControl: .control
        case .leftShift, .rightShift: .shift
        }
    }

    public var isRight: Bool { [.rightCommand, .rightOption, .rightControl, .rightShift].contains(self) }
}

/// A modifier regardless of side, as reported in event flags.
public enum ModifierFamily: String, Codable, CaseIterable, Sendable, Comparable {
    // Declared in the order macOS displays them: ⌃⌥⇧⌘.
    case function, control, option, shift, command

    public var symbol: String {
        switch self {
        case .function: "fn"
        case .control: "⌃"
        case .option: "⌥"
        case .shift: "⇧"
        case .command: "⌘"
        }
    }

    public static func < (a: Self, b: Self) -> Bool {
        allCases.firstIndex(of: a)! < allCases.firstIndex(of: b)!
    }
}

/// Either a set of modifier keys held on their own (e.g. Fn, Right ⌥), or a normal key with modifiers (e.g. ⌥Space).
public struct Shortcut: Codable, Hashable, Sendable {
    /// Exact keys for modifier-only shortcuts.
    public var modifierKeys: Set<ModifierKey>
    /// Modifiers for key combos (side doesn't matter).
    public var modifiers: Set<ModifierFamily>
    public var keyCode: UInt16?
    public var keyLabel: String?

    public var isModifierOnly: Bool { keyCode == nil }

    public static func modifierOnly(_ keys: Set<ModifierKey>) -> Shortcut {
        Shortcut(modifierKeys: keys, modifiers: [], keyCode: nil, keyLabel: nil)
    }

    public static func combo(keyCode: UInt16, label: String, modifiers: Set<ModifierFamily>) -> Shortcut {
        Shortcut(modifierKeys: [], modifiers: modifiers.subtracting([.function]), keyCode: keyCode, keyLabel: label)
    }

    /// Keycaps to display, e.g. ["fn", "⌃"] or ["⌥", "Space"].
    public var keycaps: [String] {
        if isModifierOnly {
            let sideMatters = modifierKeys.count == 1 || Set(modifierKeys.map(\.family)).count < modifierKeys.count
            return modifierKeys.sorted { ($0.family, $0.rawValue) < ($1.family, $1.rawValue) }.map { key in
                guard key != .fn else { return "fn" }
                let side = key.isRight ? "Right " : (sideMatters ? "Left " : "")
                return side + key.family.symbol
            }
        }
        return modifiers.sorted().map(\.symbol) + [keyLabel ?? "Key \(keyCode ?? 0)"]
    }

    public var displayName: String { keycaps.joined(separator: " ") }
}

public enum KeyEvent: Equatable, Sendable {
    case modifier(ModifierKey, isDown: Bool)
    case keyDown(keyCode: UInt16, modifiers: Set<ModifierFamily>, isRepeat: Bool)
    case keyUp(keyCode: UInt16)
}

/// Matches a stream of key events against named shortcuts.
public struct ShortcutMatcher: Sendable {
    public enum Output: Equatable, Sendable {
        case pressed(String)
        case released(String)
        /// While held, the keys changed to exactly another modifier-only shortcut (e.g. Fn → Fn+⌃).
        case switched(String)
        /// A normal key was typed while a modifier-only shortcut was held, so it was probably a real key combo.
        case interrupted(String)
    }

    public var bindings: [String: Shortcut]
    public private(set) var held: Set<ModifierKey> = []
    public private(set) var active: String?

    public init(bindings: [String: Shortcut]) {
        self.bindings = bindings
    }

    /// Returns what happened and whether the event should be swallowed.
    public mutating func handle(_ event: KeyEvent) -> (outputs: [Output], consume: Bool) {
        switch event {
        case .modifier(let key, let isDown):
            if isDown { held.insert(key) } else { held.remove(key) }
            if let id = active, let shortcut = bindings[id], shortcut.isModifierOnly {
                if !isDown, shortcut.modifierKeys.contains(key) {
                    active = nil
                    return ([.released(id)], false)
                }
                if isDown, let other = modifierOnlyMatch(), other != id {
                    active = other
                    return ([.switched(other)], false)
                }
                return ([], false)
            }
            if isDown, active == nil, let id = modifierOnlyMatch() {
                active = id
                return ([.pressed(id)], false)
            }
            return ([], false)

        case .keyDown(let code, let mods, let isRepeat):
            if let id = active, let shortcut = bindings[id] {
                if shortcut.keyCode == code { return ([], true) } // auto-repeat of the held combo
                if shortcut.isModifierOnly {
                    active = nil
                    return ([.interrupted(id)], false)
                }
            }
            let mods = mods.subtracting([.function])
            guard let id = bindings.first(where: { $0.value.keyCode == code && $0.value.modifiers == mods })?.key else {
                return ([], false)
            }
            if isRepeat { return ([], true) }
            active = id
            return ([.pressed(id)], true)

        case .keyUp(let code):
            guard let id = active, bindings[id]?.keyCode == code else { return ([], false) }
            active = nil
            return ([.released(id)], true)
        }
    }

    public mutating func reset() {
        active = nil
    }

    private func modifierOnlyMatch() -> String? {
        bindings.first { $0.value.isModifierOnly && $0.value.modifierKeys == held }?.key
    }
}
