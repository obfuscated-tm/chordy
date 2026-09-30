#if DEBUG
import AppKit
import ChordyCore
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

/// README images, rendered from the real views with sample data. Nothing is saved.
///   Chordy --showcase <screen>   opens one window and prints its window number (for `screencapture -l`)
///   Chordy --render-demo <dir>   writes demo.gif, an animated dictation
enum Showcase {
    static var active: Bool { CommandLine.arguments.contains("--showcase") }

    static func runIfRequested() {
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--render-demo"), i + 1 < args.count {
            Store.readOnly = true
            renderDemo(to: URL(fileURLWithPath: args[i + 1], isDirectory: true))
            exit(0)
        }
        guard let i = args.firstIndex(of: "--showcase"), i + 1 < args.count else { return }
        Store.readOnly = true
        let screen = args[i + 1]
        DispatchQueue.main.async { show(screen) }
    }

    static func sampleModel() -> AppModel {
        let model = AppModel()
        model.speechInUse = "Whisper large-v3 turbo"
        model.cleanupInUse = "Qwen3 4B (MLX)"
        model.engineStatus = "Ready · Whisper large-v3 turbo"
        model.modes = Mode.defaults
        model.vocabulary = Vocabulary([
            VocabularyEntry(term: "Chordy", soundsLike: ["cordy", "chordie"]),
            VocabularyEntry(term: "SwiftUI", soundsLike: ["swift you eye"]),
            VocabularyEntry(term: "Ms. Alvarez"),
        ])
        model.snippets = [
            Snippet(trigger: "my email", expansion: "me@example.com"),
            Snippet(trigger: "sign off", expansion: "Thanks,\nSam"),
        ]
        let now = Date()
        model.history = [
            HistoryEntry(date: now.addingTimeInterval(-120),
                         raw: "um so I think we should uh ship it on friday no wait thursday",
                         text: "So I think we should ship it on Thursday.", mode: "Default", app: "Notes",
                         speechModel: "Whisper large-v3 turbo", cleanupModel: "Qwen3 4B (MLX)"),
            HistoryEntry(date: now.addingTimeInterval(-900),
                         raw: "fix the bug in at src slash parser dot swift where camel case line count is off by one",
                         text: "Fix the bug in @src/parser.swift where lineCount is off by one.", mode: "Prompt", app: "Claude",
                         speechModel: "Whisper large-v3 turbo", cleanupModel: "Qwen3 4B (MLX)"),
            HistoryEntry(date: now.addingTimeInterval(-5400),
                         raw: "in conclusion the author use imagery to show how lonely the character feel",
                         text: "In conclusion, the author uses imagery to show how lonely the character feels.", mode: "Essay", app: "Pages",
                         speechModel: "Whisper large-v3 turbo", cleanupModel: "Qwen3 4B (MLX)"),
            HistoryEntry(date: now.addingTimeInterval(-86400),
                         raw: "git status", text: "git status", mode: "Terminal", app: "Terminal",
                         speechModel: "Whisper large-v3 turbo", cleanupModel: "Rules only"),
        ]
        return model
    }

    private static var window: NSWindow?

    private static func show(_ screen: String) {
        let model = sampleModel()
        let view: AnyView
        switch screen {
        case "general": view = AnyView(SettingsView(model: model, page: .general))
        case "modes": view = AnyView(SettingsView(model: model, page: .modes, initialMode: Mode.builtIn(.prompt).id))
        case "dictionary": view = AnyView(SettingsView(model: model, page: .dictionary))
        case "history": view = AnyView(HistoryView(model: model).frame(width: 760, height: 440))
        case let s where s.hasPrefix("onboarding-"):
            let step = OnboardingView.Step.allCases.first { "onboarding-\($0)" == s } ?? .welcome
            view = AnyView(OnboardingView(model: model, step: step))
        default:
            fatalError("unknown screen \(screen)")
        }
        let window = NSWindow(contentViewController: NSHostingController(rootView: view))
        window.title = screen == "history" ? "Chordy History" : screen.hasPrefix("onboarding") ? "" : "Chordy Settings"
        if screen.hasPrefix("onboarding") {
            window.titlebarAppearsTransparent = true
            window.styleMask.insert(.fullSizeContentView)
        }
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
        self.window = window
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            print(window.windowNumber)
            fflush(stdout)
        }
    }

    // MARK: - Demo GIF

    private static let spoken = "um so I think we should uh ship it on friday no wait thursday"
    private static let result = "So I think we should ship it on Thursday."

    private static func renderDemo(to dir: URL) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let model = sampleModel()
        model.activeMode = .builtIn(.standard)
        let presence = PillPresence()
        let words = spoken.split(separator: " ")

        struct Frame { var typed: String; var caption: String; var pill: Bool; var hold: Double }
        var frames: [Frame] = []
        var configure: [(AppModel) -> Void] = []

        func add(_ f: Frame, _ c: @escaping (AppModel) -> Void) { frames.append(f); configure.append(c) }

        for i in 0..<6 { add(Frame(typed: i % 2 == 0 ? "|" : "", caption: "Click where you want to type…", pill: false, hold: 0.25)) { _ in } }
        let listenFrames = 34
        for i in 0..<listenFrames {
            let shown = words.prefix(Int(Double(words.count) * Double(i + 1) / Double(listenFrames) + 0.5)).joined(separator: " ")
            let level = Float(0.35 + 0.45 * abs(sin(Double(i) * 0.9)) * (i % 5 == 4 ? 0.3 : 1))
            add(Frame(typed: "|", caption: "Hold fn and talk:  “\(shown)”", pill: true, hold: 0.09)) { m in
                m.phase = .recording; m.level = level
            }
        }
        for _ in 0..<8 {
            add(Frame(typed: "|", caption: "Let go…", pill: true, hold: 0.09)) { m in m.phase = .processing }
        }
        for i in 0..<14 {
            add(Frame(typed: result + (i % 2 == 0 ? "|" : ""), caption: "…and it's typed for you, cleaned up.", pill: true, hold: 0.22)) { m in
                m.phase = .done(.pasted(undoable: true))
            }
        }
        add(Frame(typed: result, caption: "…and it's typed for you, cleaned up.", pill: false, hold: 1.8)) { _ in }

        let url = dir.appending(path: "demo.gif")
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString, frames.count, nil) else { return }
        CGImageDestinationSetProperties(dest, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        for (frame, setup) in zip(frames, configure) {
            setup(model)
            presence.visible = frame.pill
            let scene = DemoScene(model: model, presence: presence, typed: frame.typed, caption: frame.caption)
            let renderer = ImageRenderer(content: scene)
            renderer.scale = 1.5
            guard let image = renderer.cgImage else { continue }
            CGImageDestinationAddImage(dest, image, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: frame.hold]] as CFDictionary)
        }
        CGImageDestinationFinalize(dest)
        print("wrote \(url.path)")
    }
}

/// A pretend Notes window with the pill underneath, drawn only with shapes and text so ImageRenderer can draw it.
private struct DemoScene: View {
    let model: AppModel
    let presence: PillPresence
    let typed: String
    let caption: String

    var body: some View {
        ZStack(alignment: .bottom) {
            LinearGradient(colors: [Color(red: 0.36, green: 0.27, blue: 0.40), Color(red: 0.16, green: 0.14, blue: 0.22)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            VStack(spacing: 18) {
                VStack(spacing: 0) {
                    HStack(spacing: 7) {
                        ForEach([Color.red, .yellow, .green], id: \.self) { Circle().fill($0.opacity(0.85)).frame(width: 11, height: 11) }
                        Spacer()
                        Text("Notes").font(.system(size: 13, weight: .semibold)).foregroundStyle(.black.opacity(0.55))
                        Spacer()
                        Color.clear.frame(width: 47, height: 1)
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 34)
                    .background(Color(white: 0.93))
                    Text(typed.replacingOccurrences(of: "|", with: "▏"))
                        .font(.system(size: 20))
                        .foregroundStyle(.black.opacity(0.85))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .padding(22)
                        .background(Color.white)
                }
                .frame(width: 560, height: 190)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(color: .black.opacity(0.35), radius: 18, y: 8)

                Text(caption)
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.9))
                    .frame(width: 620, height: 44)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 30)
            .frame(maxHeight: .infinity, alignment: .top)

            PillView(model: model, presence: presence)
                .frame(width: 420, height: 90)
        }
        .frame(width: 680, height: 400)
    }
}
#endif
