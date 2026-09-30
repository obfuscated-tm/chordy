import AppKit
import ChordyCore
import SwiftUI

@main
struct ChordyApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate

    init() {
        #if DEBUG
        PillSnapshots.renderIfRequested()
        #endif
    }

    var body: some Scene {
        MenuBarExtra {
            MenuContent(model: delegate.model)
        } label: {
            Image(systemName: delegate.model.menuBarSymbol)
        }
        .menuBarExtraStyle(.menu)

        Window("Chordy Settings", id: "settings") {
            SettingsView(model: delegate.model)
        }
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(.suppressed)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        model.start()
    }
}

struct MenuContent: View {
    @Bindable var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text(model.statusLine)
        if let warning = model.engineWarning {
            Text(warning)
        }

        if !model.accessibilityGranted {
            Divider()
            Button("Grant Accessibility Access…") { Permissions.openAccessibilitySettings() }
            Text("Needed to hear the Fn key and paste text")
        }
        if !model.microphoneGranted {
            Button("Grant Microphone Access…") { Permissions.openMicrophoneSettings() }
        }

        Divider()
        Picker("Speech Engine", selection: $model.engineChoice) {
            ForEach(EngineChoice.allCases) { Text($0.label).tag($0) }
        }
        Picker("Cleanup", selection: $model.cleanupLevel) {
            ForEach(CleanupLevel.allCases, id: \.self) { Text("\($0.rawValue) · \($0.name)").tag($0) }
        }
        Toggle("Coding Rules (@paths, camel case…)", isOn: $model.devRules)

        if !model.history.isEmpty {
            Divider()
            Menu("Recent") {
                ForEach(model.history.prefix(10)) { entry in
                    Button(entry.preview) { model.copyToClipboard(entry.text) }
                }
            }
        }

        Divider()
        if let dictate = model.shortcuts[.dictate] {
            Text("Hold \(dictate.displayName) to dictate · double-tap to lock")
        }
        Button("Settings…") {
            NSApp.activate()
            openWindow(id: "settings")
        }
        .keyboardShortcut(",")
        Button("Quit Chordy") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
