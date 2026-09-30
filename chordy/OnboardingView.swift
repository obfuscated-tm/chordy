import AppKit
import ChordyCore
import Combine
import SwiftUI

struct OnboardingView: View {
    enum Step: Int, CaseIterable {
        case welcome, microphone, accessibility, fnKey, engine, tryIt
    }

    @Bindable var model: AppModel
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var step = Step.welcome
    @State private var preset = SetupPreset.recommended
    @State private var fnDoesNothing = FnKeySetting.doesNothing
    @State private var practice = ""

    private let poll = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var steps: [Step] {
        Step.allCases.filter { $0 != .fnKey || model.usesFnKey }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                ForEach(steps, id: \.self) { s in
                    Capsule()
                        .fill(s.rawValue <= step.rawValue ? Color.chordy : Color.primary.opacity(0.12))
                        .frame(height: 4)
                }
            }
            .padding(.horizontal, 32)
            .padding(.top, 20)

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 40)
                .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
                .id(step)

            HStack {
                if step != .welcome {
                    Button("Back") { go(-1) }
                }
                Spacer()
                if step == .tryIt {
                    Button("Done") { finish() }
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button(nextTitle) { advance() }
                        .keyboardShortcut(.defaultAction)
                }
            }
            .controlSize(.large)
            .padding(20)
        }
        .frame(width: 560, height: 460)
        .onReceive(poll) { _ in fnDoesNothing = FnKeySetting.doesNothing }
    }

    private var nextTitle: String {
        switch step {
        case .microphone where !model.microphoneGranted: "Skip"
        case .accessibility where !model.accessibilityGranted: "Skip"
        case .welcome: "Get Started"
        default: "Continue"
        }
    }

    @ViewBuilder private var content: some View {
        switch step {
        case .welcome:
            StepLayout(symbol: "waveform", title: "Welcome to Chordy") {
                Text("Hold a key, talk, and let go. Chordy types what you said, tidied up, wherever your cursor is.")
                Text("Everything runs on this Mac. Your voice never leaves it.")
                    .foregroundStyle(.secondary)
            }
        case .microphone:
            StepLayout(symbol: "mic.fill", title: "Let Chordy hear you") {
                Text("Chordy only listens while you hold the shortcut.")
                PermissionRow(granted: model.microphoneGranted, action: "Allow Microphone") {
                    if Permissions.microphoneDenied { Permissions.openMicrophoneSettings() } else { model.requestMicrophone() }
                }
            }
        case .accessibility:
            StepLayout(symbol: "keyboard", title: "Let Chordy type for you") {
                Text("Accessibility access lets Chordy notice your shortcut in any app and paste the text.")
                PermissionRow(granted: model.accessibilityGranted, action: "Open Accessibility Settings") {
                    Permissions.promptForAccessibilityIfNeeded()
                    Permissions.openAccessibilitySettings()
                }
                if !model.accessibilityGranted {
                    Text("Turn on Chordy in the list, then come back. This page updates by itself.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        case .fnKey:
            StepLayout(symbol: "globe", title: "Free up the fn key") {
                Text("macOS uses fn (🌐) for the emoji picker by default. Set **Press 🌐 key to** → **Do Nothing** so it's all Chordy's.")
                PermissionRow(granted: fnDoesNothing, grantedText: "Set to Do Nothing", action: "Open Keyboard Settings") {
                    FnKeySetting.openSettings()
                }
                Text("Prefer another key? Change it any time in Settings.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        case .engine:
            StepLayout(symbol: "cpu", title: "Pick your models") {
                VStack(spacing: 8) {
                    ForEach(SetupPreset.allCases) { option in
                        PresetCard(preset: option, selected: preset == option) { preset = option }
                    }
                }
                Text("Downloads run in the background. Chordy uses the built-in models until they're ready.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        case .tryIt:
            StepLayout(symbol: "sparkles", title: "Try it") {
                if let shortcut = model.shortcuts[.dictate] {
                    Text("Click the box, hold **\(shortcut.displayName)** and say something. Double-tap to go hands-free.")
                }
                TextEditor(text: $practice)
                    .font(.body)
                    .frame(height: 90)
                    .padding(6)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.12)))
                Text(model.engineStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func advance() {
        if step == .engine { model.apply(preset) }
        go(1)
    }

    private func go(_ delta: Int) {
        guard let i = steps.firstIndex(of: step), steps.indices.contains(i + delta) else { return }
        withAnimation(.spring(duration: 0.35)) { step = steps[i + delta] }
    }

    private func finish() {
        model.hasOnboarded = true
        dismissWindow(id: "onboarding")
    }
}

private struct StepLayout<Content: View>: View {
    let symbol: String
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 34, weight: .medium))
                .foregroundStyle(Color.chordy)
                .frame(height: 44)
            Text(title).font(.title.bold())
            VStack(spacing: 12) { content }
                .multilineTextAlignment(.center)
                .frame(maxWidth: 440)
        }
    }
}

private struct PermissionRow: View {
    let granted: Bool
    var grantedText = "Allowed"
    let action: String
    let perform: () -> Void

    var body: some View {
        if granted {
            Label(grantedText, systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.headline)
        } else {
            Button(action, action: perform)
                .buttonStyle(.borderedProminent)
                .tint(.chordy)
                .controlSize(.large)
        }
    }
}

private struct PresetCard: View {
    let preset: SetupPreset
    let selected: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(preset.title).font(.headline)
                    Text(preset.detail).font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(selected ? Color.chordy : Color.secondary)
            }
            .padding(12)
            .contentShape(Rectangle())
            .background(RoundedRectangle(cornerRadius: 10).fill(selected ? Color.chordy.opacity(0.1) : Color.primary.opacity(0.04)))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(selected ? Color.chordy : Color.primary.opacity(0.1)))
        }
        .buttonStyle(.plain)
        .multilineTextAlignment(.leading)
    }
}

/// System Settings → Keyboard → "Press 🌐 key to". 0 means Do Nothing.
enum FnKeySetting {
    static var doesNothing: Bool {
        CFPreferencesAppSynchronize("com.apple.HIToolbox" as CFString)
        let value = CFPreferencesCopyAppValue("AppleFnUsageType" as CFString, "com.apple.HIToolbox" as CFString)
        return (value as? Int) == 0
    }

    static func openSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension")!)
    }
}
