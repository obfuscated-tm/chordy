import AppKit
import ChordyCore
import SwiftUI

struct SettingsView: View {
    @Bindable var model: AppModel

    var body: some View {
        Form {
            Section {
                ForEach(ShortcutAction.allCases) { action in
                    LabeledContent {
                        ShortcutRecorder(model: model, action: action)
                    } label: {
                        Text(action.title)
                        Text(action.subtitle)
                    }
                }
            } header: {
                Text("Shortcuts")
            } footer: {
                HStack(alignment: .firstTextBaseline) {
                    if model.usesFnKey {
                        Text("Using fn? Set System Settings → Keyboard → “Press 🌐 key to” → Do Nothing, so it doesn't open the emoji picker. Press esc to cancel a dictation.")
                    } else {
                        Text("Press esc to cancel a dictation.")
                    }
                    Spacer()
                    Button("Restore Defaults") { model.resetShortcuts() }
                        .controlSize(.small)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section("Transcription") {
                Picker("Speech engine", selection: $model.engineChoice) {
                    ForEach(EngineChoice.allCases) { Text($0.label).tag($0) }
                }
                if let warning = model.engineWarning {
                    Text(warning).font(.caption).foregroundStyle(.orange)
                }
                LabeledContent("Cleanup") {
                    CleanupSlider(level: $model.cleanupLevel)
                }
                Toggle("Coding rules", isOn: $model.devRules)
                Text("“at src slash app dot ts” → @src/app.ts, “camel case user name” → userName")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Feedback") {
                Toggle("Play sounds", isOn: $model.soundsEnabled)
            }
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct CleanupSlider: View {
    @Binding var level: CleanupLevel

    private static let details: [CleanupLevel: String] = [
        .raw: "Exactly what you said",
        .tidy: "Spacing, capitals, “new line”",
        .clean: "+ removes ums and self-corrections",
        .smooth: "+ fixes grammar, keeps your words",
        .polish: "+ rephrases for clarity, formats lists",
    ]

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            Slider(
                value: Binding(get: { Double(level.rawValue) }, set: { level = CleanupLevel(rawValue: Int($0.rounded())) ?? .clean }),
                in: 0...4,
                step: 1
            )
            .frame(width: 220)
            Text("\(level.name): \(Self.details[level] ?? "")")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

/// Click, then press the keys you want. Modifier-only shortcuts (fn, Right ⌥, fn ⌃…) are recorded when you let go.
struct ShortcutRecorder: View {
    let model: AppModel
    let action: ShortcutAction

    @State private var recording = false
    @State private var monitor: Any?
    @State private var held: Set<ModifierKey> = []
    @State private var peak: Set<ModifierKey> = []
    @State private var message: String?

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            Button(action: toggle) {
                HStack(spacing: 4) {
                    if recording {
                        Text(peak.isEmpty ? "Press keys…" : Shortcut.modifierOnly(peak).displayName)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                    } else if let shortcut = model.shortcuts[action] {
                        ForEach(shortcut.keycaps, id: \.self) { Keycap(text: $0) }
                    }
                }
                .frame(minWidth: 120, minHeight: 24)
                .padding(.horizontal, 4)
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(recording ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.05))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7)
                        .strokeBorder(recording ? Color.accentColor : Color.primary.opacity(0.12), lineWidth: recording ? 1.5 : 0.5)
                )
            }
            .buttonStyle(.plain)
            if let message {
                Text(message).font(.caption).foregroundStyle(.orange)
            }
        }
        .onDisappear(perform: stop)
    }

    private func toggle() {
        recording ? stop() : start()
    }

    private func start() {
        message = nil
        held = []
        peak = []
        recording = true
        model.shortcutsSuspended = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            handle(event)
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        recording = false
        model.shortcutsSuspended = false
    }

    private func handle(_ event: NSEvent) {
        switch event.type {
        case .flagsChanged:
            guard let key = ModifierKey(rawValue: event.keyCode) else { return }
            let flag: NSEvent.ModifierFlags = switch key.family {
            case .function: .function
            case .control: .control
            case .option: .option
            case .shift: .shift
            case .command: .command
            }
            if event.modifierFlags.contains(flag) {
                held.insert(key)
                peak.insert(key)
            } else {
                held.remove(key)
            }
            if held.isEmpty, !peak.isEmpty { commit(.modifierOnly(peak)) }
        case .keyDown:
            let families = Set(ModifierFamily.allCases.filter { family in
                switch family {
                case .function: false
                case .control: event.modifierFlags.contains(.control)
                case .option: event.modifierFlags.contains(.option)
                case .shift: event.modifierFlags.contains(.shift)
                case .command: event.modifierFlags.contains(.command)
                }
            })
            if event.keyCode == 53, families.isEmpty { return stop() }
            guard !families.isEmpty || KeyNames.isFunctionKey(event.keyCode) else {
                message = "Add a modifier (⌃ ⌥ ⌘), or it would block normal typing"
                peak = []
                return
            }
            commit(.combo(keyCode: event.keyCode, label: KeyNames.label(for: event), modifiers: families))
        default:
            break
        }
    }

    private func commit(_ shortcut: Shortcut) {
        if let other = ShortcutAction.allCases.first(where: { $0 != action && model.shortcuts[$0] == shortcut }) {
            message = "Already used for “\(other.title)”"
            peak = []
            held = []
            return
        }
        if shortcut.isModifierOnly, shortcut.modifierKeys.count == 1,
           let only = shortcut.modifierKeys.first, [.leftCommand, .leftShift, .leftControl].contains(only) {
            message = "Tip: \(only.family.symbol) alone gets in the way of normal shortcuts"
        } else {
            message = nil
        }
        model.shortcuts[action] = shortcut
        stop()
    }
}

struct Keycap: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .medium, design: .rounded))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 5).fill(Color.primary.opacity(0.08)))
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Color.primary.opacity(0.15), lineWidth: 0.5))
    }
}
