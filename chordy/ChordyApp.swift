import AppKit
import ChordyCore
import SwiftUI

@main
struct ChordyApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate

    init() {
        #if DEBUG
        PillSnapshots.renderIfRequested()
        Showcase.runIfRequested()
        #endif
        #if DEBUG && canImport(ChordyMLX)
        MLXEvalHook.runIfRequested()
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

        Window("Chordy History", id: "history") {
            HistoryView(model: delegate.model)
        }
        .defaultLaunchBehavior(.suppressed)

        Window("Welcome to Chordy", id: "onboarding") {
            OnboardingView(model: delegate.model)
        }
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
        .defaultLaunchBehavior(delegate.model.hasOnboarded ? .suppressed : .presented)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        #if DEBUG
        if Showcase.active { return }
        #endif
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

        Text("Speech: \(model.speechInUse ?? "not ready")")
        Text("Cleanup: \(model.cleanupStatus ?? model.cleanupInUse ?? "off (Apple Intelligence unavailable)")")

        Divider()
        Picker("Mode", selection: $model.forcedModeID) {
            Text("Automatic (\(model.modeForFrontmostApp.name))").tag(UUID?.none)
            Divider()
            ForEach(model.modes) { mode in
                Label(mode.name, systemImage: mode.symbol).tag(Optional(mode.id))
            }
        }

        Divider()
        if !model.history.isEmpty {
            Menu("Recent") {
                ForEach(model.history.prefix(10)) { entry in
                    Button(entry.preview) { model.copyToClipboard(entry.text) }
                }
                Divider()
                Text("Click to copy")
            }
            Button("Paste Last as Raw") { model.pasteLastRaw() }
        }
        Button("History…") { show("history") }
            .keyboardShortcut("y")

        Divider()
        if let dictate = model.shortcuts[.dictate] {
            Text("Hold \(dictate.displayName) to dictate · double-tap to lock")
        }
        Button("Settings…") { show("settings") }
            .keyboardShortcut(",")
        Button("Setup Guide…") { show("onboarding") }
        Button("Quit Chordy") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }

    private func show(_ id: String) {
        NSApp.activate()
        openWindow(id: id)
    }
}
