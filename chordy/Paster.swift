import AppKit

/// Pastes text into the focused app via the clipboard and a synthetic ⌘V, then restores the clipboard.
enum Paster {
    static func paste(_ text: String) {
        let pasteboard = NSPasteboard.general
        let saved = pasteboard.pasteboardItems?.map { item in
            item.types.compactMap { type in item.data(forType: type).map { (type, $0) } }
        } ?? []

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        let ourChange = pasteboard.changeCount

        press(9, flags: .maskCommand)  // ⌘V

        // Give the target app time to read the clipboard, then put the user's clipboard back
        // (unless something else has written to it since).
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            guard pasteboard.changeCount == ourChange, !saved.isEmpty else { return }
            pasteboard.clearContents()
            pasteboard.writeObjects(saved.map { pairs in
                let item = NSPasteboardItem()
                for (type, data) in pairs { item.setData(data, forType: type) }
                return item
            })
        }
    }

    /// ⌘Z in the focused app.
    static func undo() {
        press(6, flags: .maskCommand)
    }

    /// Deletes characters one by one, for apps like terminals where ⌘Z doesn't undo a paste.
    static func backspace(times: Int) {
        for _ in 0..<times { press(51) }
    }

    private static func press(_ key: CGKeyCode, flags: CGEventFlags = []) {
        let source = CGEventSource(stateID: .combinedSessionState)
        for keyDown in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: keyDown)
            event?.flags = flags
            event?.post(tap: .cghidEventTap)
        }
    }
}
