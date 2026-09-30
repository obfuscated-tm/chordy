#if DEBUG
import AppKit
import SwiftUI

/// `Chordy --render-pill <dir>` writes a PNG of every pill state, for design review without dictating.
enum PillSnapshots {
    static func renderIfRequested() {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--render-pill"), i + 1 < args.count else { return }
        let dir = URL(fileURLWithPath: args[i + 1], isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let presence = PillPresence()
        presence.visible = true
        let states: [(String, (AppModel) -> Void)] = [
            ("1-listening", { $0.phase = .recording; $0.level = 0.7 }),
            ("2-listening-quiet", { $0.phase = .recording; $0.level = 0.1 }),
            ("3-raw", { $0.phase = .recording; $0.level = 0.5; $0.activeAction = .dictateRaw }),
            ("4-locked", { $0.phase = .locked; $0.level = 0.6; $0.recordingStartedAt = Date().addingTimeInterval(-37) }),
            ("5-processing", { $0.phase = .processing }),
            ("6-pasted", { $0.phase = .done(.pasted) }),
            ("7-nothing", { $0.phase = .done(.nothingHeard) }),
            ("8-failed", { $0.phase = .done(.failed("Speech engine not ready")) }),
        ]
        for (name, configure) in states {
            let model = AppModel()
            configure(model)
            let view = PillView(model: model, presence: presence)
                .frame(width: 420, height: 90)
                .background(Color(white: 0.55))
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            if let image = renderer.nsImage, let tiff = image.tiffRepresentation,
               let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                try? png.write(to: dir.appending(path: "\(name).png"))
            }
        }
        exit(0)
    }
}
#endif
