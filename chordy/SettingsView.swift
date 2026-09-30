import AppKit
import ChordyCore
import SwiftUI

struct SettingsView: View {
    @Bindable var model: AppModel

    var body: some View {
        TabView {
            Tab("General", systemImage: "gearshape") { GeneralSettings(model: model) }
            Tab("Modes", systemImage: "slider.horizontal.3") { ModesSettings(model: model) }
            Tab("Dictionary", systemImage: "character.book.closed") { DictionarySettings(model: model) }
        }
        .frame(width: 640, height: 560)
    }
}

private struct GeneralSettings: View {
    @Bindable var model: AppModel
    @State private var microphones = AudioInputDevice.all()

    var body: some View {
        Form {
            Section {
                ForEach(ShortcutAction.allCases) { action in
                    LabeledContent {
                        ShortcutRecorder(
                            model: model,
                            binding: action.rawValue,
                            shortcut: Binding(get: { model.shortcuts[action] }, set: { model.shortcuts[action] = $0 })
                        )
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

            Section("Engines") {
                Picker("Speech", selection: $model.engineChoice) {
                    ForEach(EngineChoice.allCases) { Text($0.label).tag($0) }
                }
                if let warning = model.engineWarning {
                    Text(warning).font(.caption).foregroundStyle(.orange)
                }
                InUse(name: model.speechInUse)
                Picker("Cleanup", selection: $model.cleanupEngine) {
                    ForEach(CleanupEngine.available) { Text($0.label).tag($0) }
                }
                if let status = model.cleanupStatus {
                    Text(status).font(.caption).foregroundStyle(.secondary)
                }
                InUse(name: model.cleanupInUse)
                Picker("Microphone", selection: $model.microphoneUID) {
                    Text("System Default").tag(String?.none)
                    ForEach(microphones) { Text($0.name).tag(Optional($0.id)) }
                }
                .onAppear { microphones = AudioInputDevice.all() }
            }

            Section("While Dictating") {
                Toggle("Play sounds", isOn: $model.soundsEnabled)
                Toggle("Pause Music and Spotify", isOn: $model.pauseMedia)
            }

            Section {
                Picker("Keep history", selection: $model.historyRetention) {
                    ForEach(HistoryRetention.allCases) { Text($0.label).tag($0) }
                }
            } header: {
                Text("Privacy")
            } footer: {
                Text("Only text is saved, on this Mac. Audio is never kept.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

/// Shows the model actually running, which lags the picker while a download finishes.
private struct InUse: View {
    let name: String?

    var body: some View {
        Label("In use: \(name ?? "not ready")", systemImage: name == nil ? "hourglass" : "checkmark.circle.fill")
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}

struct CleanupSlider: View {
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
    /// "dictate", "dictateRaw" or "mode:<uuid>", for conflict checks.
    let binding: String
    @Binding var shortcut: Shortcut?
    var clearable = false

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
                    } else if let shortcut {
                        ForEach(shortcut.keycaps, id: \.self) { Keycap(text: $0) }
                    } else {
                        Text("Record Shortcut").foregroundStyle(.secondary).padding(.horizontal, 6)
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
            .overlay(alignment: .trailing) {
                if clearable, shortcut != nil, !recording {
                    Button {
                        shortcut = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                    .offset(x: 20)
                    .help("Remove shortcut")
                }
            }
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
        if let other = model.owner(of: shortcut, except: binding) {
            message = "Already used for “\(other)”"
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
        self.shortcut = shortcut
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
