@testable import ChordyCore
import Testing

@Suite struct ShortcutMatcherTests {
    let bindings: [String: Shortcut] = [
        "dictate": .modifierOnly([.fn]),
        "raw": .modifierOnly([.fn, .leftControl]),
        "combo": .combo(keyCode: 49, label: "Space", modifiers: [.option]),
    ]

    @Test func holdFnPressesAndReleases() {
        var m = ShortcutMatcher(bindings: bindings)
        #expect(m.handle(.modifier(.fn, isDown: true)).outputs == [.pressed("dictate")])
        #expect(m.handle(.modifier(.fn, isDown: false)).outputs == [.released("dictate")])
    }

    @Test func addingControlSwitchesToRaw() {
        var m = ShortcutMatcher(bindings: bindings)
        _ = m.handle(.modifier(.fn, isDown: true))
        #expect(m.handle(.modifier(.leftControl, isDown: true)).outputs == [.switched("raw")])
        #expect(m.handle(.modifier(.leftControl, isDown: false)).outputs == [.released("raw")])
    }

    @Test func controlFirstThenFnIsRaw() {
        var m = ShortcutMatcher(bindings: bindings)
        #expect(m.handle(.modifier(.leftControl, isDown: true)).outputs == [])
        #expect(m.handle(.modifier(.fn, isDown: true)).outputs == [.pressed("raw")])
    }

    @Test func otherModifiersHeldPreventTrigger() {
        var m = ShortcutMatcher(bindings: bindings)
        _ = m.handle(.modifier(.leftCommand, isDown: true))
        #expect(m.handle(.modifier(.fn, isDown: true)).outputs == [])
    }

    @Test func typingWhileHoldingInterrupts() {
        var m = ShortcutMatcher(bindings: bindings)
        _ = m.handle(.modifier(.fn, isDown: true))
        let r = m.handle(.keyDown(keyCode: 126, modifiers: [.function], isRepeat: false))
        #expect(r.outputs == [.interrupted("dictate")])
        #expect(!r.consume)
        #expect(m.handle(.modifier(.fn, isDown: false)).outputs == [])
    }

    @Test func comboIsConsumedIncludingRepeatsAndKeyUp() {
        var m = ShortcutMatcher(bindings: bindings)
        let down = m.handle(.keyDown(keyCode: 49, modifiers: [.option], isRepeat: false))
        #expect(down.outputs == [.pressed("combo")] && down.consume)
        #expect(m.handle(.keyDown(keyCode: 49, modifiers: [.option], isRepeat: true)) == ([], true))
        let up = m.handle(.keyUp(keyCode: 49))
        #expect(up.outputs == [.released("combo")] && up.consume)
    }

    @Test func plainSpaceIsNotConsumed() {
        var m = ShortcutMatcher(bindings: bindings)
        #expect(m.handle(.keyDown(keyCode: 49, modifiers: [], isRepeat: false)) == ([], false))
        #expect(m.handle(.keyUp(keyCode: 49)) == ([], false))
    }

    @Test func rightOptionOnlyMatchesRightSide() {
        var m = ShortcutMatcher(bindings: ["d": .modifierOnly([.rightOption])])
        #expect(m.handle(.modifier(.leftOption, isDown: true)).outputs == [])
        _ = m.handle(.modifier(.leftOption, isDown: false))
        #expect(m.handle(.modifier(.rightOption, isDown: true)).outputs == [.pressed("d")])
    }

    @Test func keycaps() {
        #expect(Shortcut.modifierOnly([.fn, .leftControl]).keycaps == ["fn", "⌃"])
        #expect(Shortcut.modifierOnly([.rightOption]).keycaps == ["Right ⌥"])
        #expect(Shortcut.combo(keyCode: 49, label: "Space", modifiers: [.command, .option]).keycaps == ["⌥", "⌘", "Space"])
    }
}
