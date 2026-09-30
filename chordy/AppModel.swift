import AppKit
import ChordyCore
import Observation
#if canImport(ChordyMLX)
import ChordyMLX
#endif

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

enum CleanupEngine: String, CaseIterable, Identifiable {
    case qwen, qwenLite, apple
    var id: Self { self }
    var label: String {
        switch self {
        case .qwen: "Qwen3 4B (download ~2.3 GB)"
        case .qwenLite: "Qwen3 1.7B (download ~1 GB)"
        case .apple: "Apple Intelligence (built-in)"
        }
    }

    /// The downloaded models need Chordy to be built with MLX (see README).
    static var available: [CleanupEngine] {
        #if canImport(ChordyMLX)
        allCases
        #else
        [.apple]
        #endif
    }
}

/// The three choices offered during setup.
enum SetupPreset: String, CaseIterable, Identifiable {
    case recommended, lite, builtIn
    var id: Self { self }
    var title: String {
        switch self {
        case .recommended: "Recommended"
        case .lite: "Lite"
        case .builtIn: "Built-in"
        }
    }
    var detail: String {
        switch self {
        case .recommended: CleanupEngine.available.contains(.qwen) ? "Most accurate · ~3 GB download" : "Most accurate · ~630 MB download"
        case .lite: CleanupEngine.available.contains(.qwen) ? "Faster, smaller · ~1.2 GB download" : "Faster, smaller · ~250 MB download"
        case .builtIn: "Apple's on-device models · no download"
        }
    }
    var engines: (EngineChoice, CleanupEngine) {
        let mlx = CleanupEngine.available.contains(.qwen)
        return switch self {
        case .recommended: (.whisper, mlx ? .qwen : .apple)
        case .lite: (.whisperLite, mlx ? .qwenLite : .apple)
        case .builtIn: (.apple, .apple)
        }
    }
}

@Observable
final class AppModel {
    enum Phase: Equatable {
        case idle, recording, locked, processing
        /// Brief result shown in the pill before it hides.
        case done(Outcome)
    }

    enum Outcome: Equatable {
        case pasted(undoable: Bool), nothingHeard, cancelled, failed(String)
    }

    /// What was pasted last, so it can be swapped for the raw transcript.
    struct LastPaste {
        var raw: String
        var text: String
        var bundleID: String?
        var usesBackspace: Bool
    }

    var phase: Phase = .idle
    var engineStatus = "Starting…"
    var engineWarning: String?
    var cleanupStatus: String?
    var lastError: String?
    var accessibilityGranted = Permissions.accessibilityGranted
    var microphoneGranted = Permissions.microphoneGranted
    var recordingStartedAt: Date?
    /// The mode of the current (or last) dictation, shown in the pill.
    var activeMode = Mode.builtIn(.standard)
    private var activeBinding = ShortcutAction.dictate.rawValue
    /// Smoothed input level, 0–1, for the pill.
    var level: Float = 0
    /// Set while the settings window is recording a new shortcut, so keys don't trigger dictation.
    var shortcutsSuspended = false
    private(set) var lastPaste: LastPaste?

    var modeName: String { activeMode.name }

    // MARK: Settings

    var engineChoice: EngineChoice {
        didSet {
            UserDefaults.standard.set(engineChoice.rawValue, forKey: "engine")
            Task { await prepareEngine() }
        }
    }
    var cleanupEngine: CleanupEngine {
        didSet {
            UserDefaults.standard.set(cleanupEngine.rawValue, forKey: "cleanupEngine")
            Task { await prepareCleaner() }
        }
    }
    var soundsEnabled: Bool {
        didSet { UserDefaults.standard.set(soundsEnabled, forKey: "sounds") }
    }
    var pauseMedia: Bool {
        didSet { UserDefaults.standard.set(pauseMedia, forKey: "pauseMedia") }
    }
    var microphoneUID: String? {
        didSet { UserDefaults.standard.set(microphoneUID, forKey: "microphone") }
    }
    var hasOnboarded: Bool {
        didSet { UserDefaults.standard.set(hasOnboarded, forKey: "onboarded") }
    }
    var shortcuts: [ShortcutAction: Shortcut] {
        didSet {
            ShortcutStore.save(shortcuts)
            rebuildMatcher()
        }
    }
    var modes: [Mode] {
        didSet {
            Store.save(modes, to: "modes.json")
            rebuildMatcher()
        }
    }
    /// nil = pick the mode from the frontmost app.
    var forcedModeID: UUID? {
        didSet { UserDefaults.standard.set(forcedModeID?.uuidString, forKey: "forcedMode") }
    }
    var vocabulary: Vocabulary {
        didSet { Store.save(vocabulary, to: "vocabulary.json") }
    }
    var snippets: [Snippet] {
        didSet { Store.save(snippets, to: "snippets.json") }
    }
    var history: [HistoryEntry] {
        didSet { historyRetention == .never ? Store.delete("history.json") : Store.save(history, to: "history.json") }
    }
    var historyRetention: HistoryRetention {
        didSet {
            UserDefaults.standard.set(historyRetention.rawValue, forKey: "historyRetention")
            pruneHistory()
        }
    }

    // MARK: Engines

    private let recorder = AudioRecorder()
    private let apple = AppleSpeechTranscriber()
    private var transcriber: (any Transcriber)?
    private let appleCleaner = AppleIntelligenceCleaner()
    private var pipeline: Pipeline
    private var gesture = HotkeyGesture()
    private var matcher = ShortcutMatcher(bindings: [:])
    private let tap = HotkeyTap()
    private let pill = PillController()
    private let media = MediaPause()
    private var hideWork: DispatchWorkItem?
    private var mediaPaused = false

    init() {
        let defaults = UserDefaults.standard
        engineChoice = defaults.string(forKey: "engine").flatMap(EngineChoice.init(rawValue:)) ?? .whisper
        let savedCleanup = defaults.string(forKey: "cleanupEngine").flatMap(CleanupEngine.init(rawValue:))
        cleanupEngine = savedCleanup.flatMap { CleanupEngine.available.contains($0) ? $0 : nil } ?? CleanupEngine.available[0]
        soundsEnabled = defaults.object(forKey: "sounds") as? Bool ?? true
        pauseMedia = defaults.object(forKey: "pauseMedia") as? Bool ?? true
        microphoneUID = defaults.string(forKey: "microphone")
        hasOnboarded = defaults.bool(forKey: "onboarded")
        forcedModeID = defaults.string(forKey: "forcedMode").flatMap(UUID.init(uuidString:))
        historyRetention = HistoryRetention(rawValue: defaults.object(forKey: "historyRetention") as? Int ?? 30) ?? .month
        shortcuts = ShortcutStore.load()
        modes = Store.load([Mode].self, from: "modes.json") ?? Self.migratedDefaultModes()
        vocabulary = Store.load(Vocabulary.self, from: "vocabulary.json") ?? Vocabulary()
        snippets = Store.load([Snippet].self, from: "snippets.json") ?? []
        history = Store.load([HistoryEntry].self, from: "history.json") ?? []
        pipeline = Pipeline(cleaner: appleCleaner)
        rebuildMatcher()
        pruneHistory()
    }

    /// First run after modes existed: carry over the old single cleanup level and coding toggle.
    private static func migratedDefaultModes() -> [Mode] {
        var modes = Mode.defaults
        let defaults = UserDefaults.standard
        if let i = modes.firstIndex(where: { $0.builtIn == .standard }) {
            if let raw = defaults.object(forKey: "cleanupLevel") as? Int, let level = CleanupLevel(rawValue: raw) { modes[i].level = level }
            if let dev = defaults.object(forKey: "devRules") as? Bool { modes[i].devRules = dev }
        }
        return modes
    }

    private func rebuildMatcher() {
        var bindings = Dictionary(uniqueKeysWithValues: shortcuts.map { ($0.key.rawValue, $0.value) })
        for mode in modes {
            if let shortcut = mode.shortcut { bindings["mode:\(mode.id.uuidString)"] = shortcut }
        }
        matcher = ShortcutMatcher(bindings: bindings)
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
        case .locked: "Listening hands-free, press \(shortcut(for: activeBinding)?.displayName ?? "the shortcut") to finish"
        case .processing: "Transcribing…"
        }
    }

    var usesFnKey: Bool {
        (Array(shortcuts.values) + modes.compactMap(\.shortcut)).contains { $0.modifierKeys.contains(.fn) }
    }

    func start() {
        pill.attach(to: self)
        recorder.onLevel = { [weak self] rms in
            Task { @MainActor [weak self] in self?.meter(rms) }
        }
        tap.handler = { [weak self] event in self?.handleKey(event) ?? false }
        tap.start()
        // Onboarding asks for permissions itself, with an explanation first.
        if hasOnboarded {
            Permissions.promptForAccessibilityIfNeeded()
            Task { microphoneGranted = await Permissions.requestMicrophone() }
        }
        Task { await prepareEngine() }
        Task { await prepareCleaner() }
        pollPermissions()
    }

    func requestMicrophone() {
        Task { microphoneGranted = await Permissions.requestMicrophone() }
    }

    func apply(_ preset: SetupPreset) {
        let (speech, cleanup) = preset.engines
        if engineChoice != speech { engineChoice = speech }
        if cleanupEngine != cleanup { cleanupEngine = cleanup }
    }

    func resetShortcuts() {
        shortcuts = Dictionary(uniqueKeysWithValues: ShortcutAction.allCases.map { ($0, $0.defaultShortcut) })
    }

    // MARK: - Modes

    var modeForFrontmostApp: Mode {
        Mode.resolve(in: modes, bundleID: NSWorkspace.shared.frontmostApplication?.bundleIdentifier)
    }

    private var rawMode: Mode { modes.first { $0.builtIn == .raw } ?? .builtIn(.raw) }

    private func mode(for binding: String) -> Mode {
        if binding == ShortcutAction.dictateRaw.rawValue { return rawMode }
        if binding.hasPrefix("mode:"), let id = UUID(uuidString: String(binding.dropFirst(5))),
           let mode = modes.first(where: { $0.id == id }) {
            return mode
        }
        if let forcedModeID, let forced = modes.first(where: { $0.id == forcedModeID }) { return forced }
        return modeForFrontmostApp
    }

    func shortcut(for binding: String) -> Shortcut? {
        if let action = ShortcutAction(rawValue: binding) { return shortcuts[action] }
        return modes.first { "mode:\($0.id.uuidString)" == binding }?.shortcut
    }

    /// Who already uses this shortcut, if anyone (for conflict warnings while recording).
    func owner(of shortcut: Shortcut, except binding: String) -> String? {
        for action in ShortcutAction.allCases where action.rawValue != binding && shortcuts[action] == shortcut {
            return action.title
        }
        for mode in modes where "mode:\(mode.id.uuidString)" != binding && mode.shortcut == shortcut {
            return "\(mode.name) mode"
        }
        return nil
    }

    func resetBuiltInModes() {
        let custom = modes.filter { $0.builtIn == nil }
        modes = Mode.defaults + custom
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

    /// Apple Intelligence cleans up meanwhile; a downloaded model takes over once loaded.
    private func prepareCleaner() async {
        cleanupStatus = nil
        pipeline.cleaner = appleCleaner
        appleCleaner.prewarm()
        #if canImport(ChordyMLX)
        guard cleanupEngine != .apple else { return }
        let choice = cleanupEngine
        let mlx = MLXCleaner(model: choice == .qwen ? .recommended : .lite)
        do {
            try await mlx.prepare { [weak self] p in
                Task { @MainActor [weak self] in
                    guard let self, self.cleanupEngine == choice else { return }
                    self.cleanupStatus = "Loading \(mlx.name)… \(Int(p * 100))%"
                }
            }
            guard cleanupEngine == choice else { return }
            pipeline.cleaner = mlx
            cleanupStatus = nil
        } catch {
            guard cleanupEngine == choice else { return }
            cleanupStatus = "\(error.localizedDescription) Using Apple Intelligence."
        }
        #endif
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
                if !gesture.isRecording {
                    activeBinding = id
                    activeMode = mode(for: id)
                }
                perform(gesture.press(at: now))
            case .released:
                perform(gesture.release(at: now))
            case .switched(let id):
                activeBinding = id
                activeMode = mode(for: id)
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
        recorder.deviceUID = microphoneUID.flatMap { uid in AudioInputDevice.all().contains { $0.id == uid } ? uid : nil }
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
        if pauseMedia {
            media.pause()
            mediaPaused = true
        }
    }

    private func resumeMedia() {
        guard mediaPaused else { return }
        mediaPaused = false
        media.resume()
    }

    private func cancelRecording(showing outcome: Outcome?) {
        _ = recorder.stop()
        resumeMedia()
        recordingStartedAt = nil
        if let outcome { finish(with: outcome) } else { hidePill() }
    }

    private func finishRecording() {
        let recorded = recorder.stop()
        resumeMedia()
        recordingStartedAt = nil
        // Under ~0.3 s is almost certainly an accidental press.
        guard recorded.count > Int(AudioFormat.sampleRate * 0.3) else { return hidePill() }
        guard let samples = Silence.trim(recorded) else { return finish(with: .nothingHeard) }
        guard let transcriber else {
            lastError = "No speech engine is ready yet"
            return finish(with: .failed("Speech engine not ready"))
        }
        phase = .processing
        let mode = activeMode
        let options = Pipeline.Options(mode: mode, vocabulary: vocabulary, snippets: snippets)
        let hints = vocabulary.terms
        let pipeline = pipeline
        let app = NSWorkspace.shared.frontmostApplication
        Task {
            do {
                let raw = try await transcriber.transcribe(samples, hints: hints)
                let result = await pipeline.process(raw, options: options)
                guard !result.text.isEmpty else { return finish(with: .nothingHeard) }
                Paster.paste(result.text)
                let rawText = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                lastPaste = LastPaste(
                    raw: rawText, text: result.text, bundleID: app?.bundleIdentifier,
                    usesBackspace: Mode.builtIn(.terminal).apps.contains { $0.bundleID == app?.bundleIdentifier }
                )
                record(HistoryEntry(raw: rawText, text: result.text, mode: mode.name, app: app?.localizedName))
                finish(with: .pasted(undoable: rawText != result.text && result.snippet == nil))
            } catch {
                lastError = error.localizedDescription
                finish(with: .failed("Transcription failed"))
            }
        }
    }

    /// Replaces the last paste with the raw transcript: undo (or backspace in terminals), then paste.
    func undoToRaw() {
        guard let last = lastPaste, last.raw != last.text else { return }
        hideWork?.cancel()
        guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier == last.bundleID else {
            copyToClipboard(last.raw)
            return finish(with: .failed("Switched apps, raw text copied instead"))
        }
        if last.usesBackspace {
            Paster.backspace(times: last.text.count)
        } else {
            Paster.undo()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            Paster.paste(last.raw)
            self?.lastPaste?.text = last.raw
            self?.finish(with: .pasted(undoable: false))
        }
    }

    /// Menu command: paste the last dictation's raw transcript wherever the cursor is now.
    func pasteLastRaw() {
        guard let raw = lastPaste?.raw ?? history.first?.raw else { return }
        // Let the menu close and focus return to the app first.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { Paster.paste(raw) }
    }

    private func finish(with outcome: Outcome) {
        phase = .done(outcome)
        let delay: Double = switch outcome {
        case .pasted(undoable: true): 3
        case .pasted: 0.7
        default: 1.6
        }
        pill.setInteractive(outcome == .pasted(undoable: true))
        let work = DispatchWorkItem { [weak self] in self?.hidePill() }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func hidePill() {
        hideWork?.cancel()
        pill.setInteractive(false)
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

    // MARK: - History

    private func record(_ entry: HistoryEntry) {
        guard historyRetention != .never else { return }
        history.insert(entry, at: 0)
        pruneHistory()
    }

    private func pruneHistory() {
        switch historyRetention {
        case .never:
            if !history.isEmpty { history = [] } else { Store.delete("history.json") }
        case .forever:
            break
        default:
            let cutoff = Date().addingTimeInterval(-Double(historyRetention.rawValue) * 86_400)
            let kept = history.filter { $0.date >= cutoff }
            if kept.count != history.count { history = kept }
        }
    }

    func deleteHistory(_ ids: Set<HistoryEntry.ID>) {
        history.removeAll { ids.contains($0.id) }
    }

    // MARK: - Misc

    func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func pollPermissions() {
        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
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
