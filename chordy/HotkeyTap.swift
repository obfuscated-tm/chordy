import AppKit
import ChordyCore

/// A system-wide keyboard event tap. Unlike an NSEvent monitor it can swallow events,
/// so a shortcut like ⌥Space doesn't also type a space. Needs Accessibility permission.
final class HotkeyTap {
    /// Return true to swallow the event.
    var handler: ((KeyEvent) -> Bool)?
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?

    var isRunning: Bool { tap != nil }

    @discardableResult
    func start() -> Bool {
        stop()
        let types: [CGEventType] = [.keyDown, .keyUp, .flagsChanged]
        let mask = types.reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon in
                let me = Unmanaged<HotkeyTap>.fromOpaque(refcon!).takeUnretainedValue()
                return MainActor.assumeIsolated { me.handle(type: type, event: event) }
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }
        self.tap = tap
        source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    func stop() {
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        tap = nil
        source = nil
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let pass = Unmanaged.passUnretained(event)
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return pass
        }
        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let keyEvent: KeyEvent
        switch type {
        case .flagsChanged:
            guard let key = ModifierKey(rawValue: keyCode) else { return pass }
            keyEvent = .modifier(key, isDown: event.flags.contains(Self.flag(for: key.family)))
        case .keyDown:
            keyEvent = .keyDown(
                keyCode: keyCode,
                modifiers: Self.families(in: event.flags),
                isRepeat: event.getIntegerValueField(.keyboardEventAutorepeat) != 0
            )
        case .keyUp:
            keyEvent = .keyUp(keyCode: keyCode)
        default:
            return pass
        }
        return handler?(keyEvent) == true ? nil : pass
    }

    static func flag(for family: ModifierFamily) -> CGEventFlags {
        switch family {
        case .function: .maskSecondaryFn
        case .control: .maskControl
        case .option: .maskAlternate
        case .shift: .maskShift
        case .command: .maskCommand
        }
    }

    static func families(in flags: CGEventFlags) -> Set<ModifierFamily> {
        Set(ModifierFamily.allCases.filter { flags.contains(flag(for: $0)) })
    }
}
