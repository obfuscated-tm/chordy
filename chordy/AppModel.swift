import AppKit
import ChordyCore
import Observation

enum EngineChoice: String, CaseIterable, Identifiable {
    case whisper, whisperLite, apple
    var id: Self { self }
    var label: String {
        switch self {
        case .whisper: "Whisper large-v3 turbo (download ~630 MB)"
        case .whisperLite: "Whisper small (download ~250 MB)"
        case .apple: "Apple Speech (built-in)"
        }
    }
}

struct HistoryEntry: Identifiable {
    let id = UUID()
    let date = Date()
    let raw: String
    let text: String
    var preview: String { text.count > 60 ? text.prefix(60) + "…" : text }
}

@Observable
final class AppModel {
    enum Phase: Equatable {
        case idle, recording, locked, processing
        /// Brief result shown in the pill before it hides.
        case done(Outcome)
    }

    enum Outcome: Equatable {
        case pasted, nothingHeard, cancelled, failed(String)
    }

    var phase: Phase = .idle
    var engineStatus = "Starting…"
    var engineWarning: String?
    var lastError: String?
    var history: [HistoryEntry] = []
    var accessibilityGranted = Permissions.accessibilityGranted
    var microphoneGranted = Permissions.microphoneGranted
    var recordingStartedAt: Date?
    var activeAction: ShortcutAction = .dictate
    /// Smoothed input level, 0–1, for the pill.
    var level: Float = 0
    /// Set while the settings window is recording a new shortcut, so keys don't trigger dictation.
    var shortcutsSuspended = false

    var modeName: String { activeAction == .dictateRaw ? CleanupLevel.raw.name : cleanupLevel.name }

    var engineChoice: EngineChoice {
        didSet {
            UserDefaults.standard.set(engineChoice.rawValue, forKey: "engine")
            Task { await prepareEngine() }
        }
    }
    var cleanupLevel: CleanupLevel {
        didSet { UserDefaults.standard.set(cleanupLevel.rawValue, forKey: "cleanupLevel") }
    }
    var devRules: Bool {
        didSet { UserDefaults.standard.set(devRules, forKey: "devRules") }
    }
    var soundsEnabled: Bool {
        didSet { UserDefaults.standard.set(soundsEnabled, forKey: "sounds") }
    }
    var shortcuts: [ShortcutAction: Shortcut] {
        didSet {
            ShortcutStore.save(shortcuts)
            matcher = ShortcutMatcher(bindings: Self.bindings(shortcuts))
        }
    }

    private let recorder = AudioRecorder()
    private let apple = AppleSpeechTranscriber()
    private var transcriber: (any Transcriber)?
    private let cleaner = AppleIntelligenceCleaner()
    private let pipeline: Pipeline
    private var gesture = HotkeyGesture()
    private var matcher: ShortcutMatcher
    private let tap = HotkeyTap()
    private let pill = PillController()
    private var hideWork: DispatchWorkItem?

    init() {
        let defaults = UserDefaults.standard
        engineChoice = defaults.string(forKey: "engine").flatMap(EngineChoice.init(rawValue:)) ?? .whisper
        cleanupLevel = CleanupLevel(rawValue: defaults.object(forKey: "cleanupLevel") as? Int ?? 2) ?? .clean
        devRules = defaults.object(forKey: "devRules") as? Bool ?? true
        soundsEnabled = defaults.object(forKey: "sounds") as? Bool ?? true
        let shortcuts = ShortcutStore.load()
        self.shortcuts = shortcuts
        matcher = ShortcutMatcher(bindings: Self.bindings(shortcuts))
        pipeline = Pipeline(cleaner: cleaner)
    }

    private static func bindings(_ shortcuts: [ShortcutAction: Shortcut]) -> [String: Shortcut] {
        Dictionary(uniqueKeysWithValues: shortcuts.map { ($0.key.rawValue, $0.value) })
    }

    var menuBarSymbol: String {
        switch phase {
        case .idle, .done: lastError == nil ? "waveform" : "exclamationmark.triangle"
        case .recording, .locked: "waveform.circle.fill"
        case .processing: "ellipsis.circle"
        }
    }

    var statusLine: String {
        if let lastError { return "⚠︎ \(lastError)" }
        return switch phase {
        case .idle, .done: engineStatus
        case .recording: "Listening…"
        case .locked: "Listening hands-free, press \(shortcuts[activeAction]?.displayName ?? "the shortcut") to finish"
        case .processing: "Transcribing…"
        }
    }

    var usesFnKey: Bool {
        shortcuts.values.contains { $0.modifierKeys.contains(.fn) }
    }

    func start() {
        pill.attach(to: self)
        recorder.onLevel = { [weak self] rms in
            Task { @MainActor [weak self] in self?.meter(rms) }
        }
        tap.handler = { [weak self] event in self?.handleKey(event) ?? false }
        tap.start()
        Permissions.promptForAccessibilityIfNeeded()
        Task {
            microphoneGranted = await Permissions.requestMicrophone()
        }
        cleaner.prewarm()
        Task { await prepareEngine() }
        pollPermissions()
    }

    func resetShortcuts() {
        shortcuts = Dictionary(uniqueKeysWithValues: ShortcutAction.allCases.map { ($0, $0.defaultShortcut) })
    }

    // MARK: - Engines

    /// Apple Speech is readied first so dictation works immediately; Whisper takes over once downloaded.
    private func prepareEngine() async {
        engineWarning = nil
        if transcriber == nil || engineChoice == .apple {
            engineStatus = "Preparing Apple Speech…"
            do {
                try await apple.prepare { _ in }
                transcriber = apple
                engineStatus = "Ready · Apple Speech"
            } catch {
                engineStatus = "Apple Speech unavailable: \(error.localizedDescription)"
            }
        }
        guard engineChoice != .apple else { return }

        let choice = engineChoice
        let whisper = WhisperTranscriber(model: choice == .whisper ? .recommended : .lite)
        do {
            try await whisper.prepare { [weak self] p in
                Task { @MainActor [weak self] in
                    guard let self, self.engineChoice == choice else { return }
                    self.engineStatus = "Loading \(whisper.name)… \(Int(p * 100))% (Apple Speech meanwhile)"
                }
            }
            guard engineChoice == choice else { return }
            transcriber = whisper
            engineStatus = "Ready · \(whisper.name)"
        } catch {
            guard engineChoice == choice else { return }
            engineWarning = error.localizedDescription
            engineStatus = transcriber == nil ? "No speech engine available" : "Ready · Apple Speech (fallback)"
        }
    }

    // MARK: - Keys

    /// Called for every key event system-wide. Returns true to swallow it.
    private func handleKey(_ event: KeyEvent) -> Bool {
        guard !shortcutsSuspended else { return false }

        // Esc cancels an in-progress dictation.
        if case .keyDown(53, _, false) = event, gesture.isRecording {
            gesture.reset()
            matcher.reset()
            cancelRecording(showing: .cancelled)
            return true
        }

        let (outputs, consume) = matcher.handle(event)
        let now = ProcessInfo.processInfo.systemUptime
        for output in outputs {
            switch output {
            case .pressed(let id):
                if !gesture.isRecording { activeAction = ShortcutAction(rawValue: id) ?? .dictate }
                perform(gesture.press(at: now))
            case .released:
                perform(gesture.release(at: now))
            case .switched(let id):
                activeAction = ShortcutAction(rawValue: id) ?? activeAction
            case .interrupted:
                // Holding the key and typing means it was used as a normal modifier (e.g. Fn+↑).
                // Only abandon a recording that just started; a long dictation is worth keeping.
                if phase == .recording, let started = recordingStartedAt, Date().timeIntervalSince(started) < 1 {
                    gesture.reset()
                    cancelRecording(showing: nil)
                }
            }
        }
        return consume
    }

    private func perform(_ action: HotkeyGesture.Action) {
        switch action {
        case .none:
            break
        case .start:
            startRecording()
        case .locked:
            phase = .locked
            if soundsEnabled { NSSound(named: "Pop")?.play() }
        case .finish:
            finishRecording()
        case .cancel:
            cancelRecording(showing: nil)
        case .scheduleTimeout(let deadline):
            let delay = max(0, deadline - ProcessInfo.processInfo.systemUptime)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self else { return }
                self.perform(self.gesture.timeout(at: ProcessInfo.processInfo.systemUptime))
            }
        }
    }

    // MARK: - Recording

    private func startRecording() {
        lastError = nil
        guard microphoneGranted else {
            gesture.reset()
            lastError = "Microphone access is off"
            return
        }
        do {
            try recorder.start()
        } catch {
            gesture.reset()
            lastError = error.localizedDescription
            return
        }
        hideWork?.cancel()
        level = 0
        recordingStartedAt = Date()
        phase = .recording
        pill.show()
        if soundsEnabled { NSSound(named: "Tink")?.play() }
    }

    private func cancelRecording(showing outcome: Outcome?) {
        _ = recorder.stop()
        recordingStartedAt = nil
        if let outcome { finish(with: outcome) } else { hidePill() }
    }

    private func finishRecording() {
        let samples = recorder.stop()
        recordingStartedAt = nil
        // Under ~0.3 s is almost certainly an accidental press.
        guard samples.count > Int(AudioFormat.sampleRate * 0.3) else { return hidePill() }
        guard let transcriber else {
            lastError = "No speech engine is ready yet"
            return finish(with: .failed("Speech engine not ready"))
        }
        phase = .processing
        let level = activeAction == .dictateRaw ? CleanupLevel.raw : cleanupLevel
        let devRules = devRules
        Task {
            do {
                let raw = try await transcriber.transcribe(samples)
                let result = await pipeline.process(raw, level: level, devRules: devRules)
                if result.text.isEmpty {
                    finish(with: .nothingHeard)
                } else {
                    Paster.paste(result.text)
                    history.insert(HistoryEntry(raw: raw, text: result.text), at: 0)
                    if history.count > 100 { history.removeLast() }
                    finish(with: .pasted)
                }
            } catch {
                lastError = error.localizedDescription
                finish(with: .failed("Transcription failed"))
            }
        }
    }

    private func finish(with outcome: Outcome) {
        phase = .done(outcome)
        let delay: Double = outcome == .pasted ? 0.7 : 1.6
        let work = DispatchWorkItem { [weak self] in self?.hidePill() }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func hidePill() {
        hideWork?.cancel()
        pill.hide { [weak self] in
            guard let self, !self.gesture.isRecording, self.phase != .processing else { return }
            self.phase = .idle
        }
    }

    /// Maps RMS to a 0–1 meter on a dB scale, rising fast and falling slowly.
    private func meter(_ rms: Float) {
        guard phase == .recording || phase == .locked else { return }
        let db = 20 * log10(max(rms, 1e-6))
        let target = min(1, max(0, (db + 55) / 40))
        level = target > level ? level + (target - level) * 0.6 : level + (target - level) * 0.15
    }

    // MARK: - Misc

    func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func pollPermissions() {
        Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.accessibilityGranted = Permissions.accessibilityGranted
                self.microphoneGranted = Permissions.microphoneGranted
                // The tap can only be created once Accessibility is granted.
                if self.accessibilityGranted, !self.tap.isRunning { self.tap.start() }
            }
        }
    }
}
