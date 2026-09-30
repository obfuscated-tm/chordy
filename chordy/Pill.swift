import AppKit
import ChordyCore
import SwiftUI

extension Color {
    static let chordy = Color(red: 1.0, green: 0.45, blue: 0.38)
    static let chordyMuted = Color(white: 0.72)
}

@Observable
final class PillPresence {
    var visible = false
}

/// The floating pill at the bottom of the screen while dictating.
final class PillController {
    private var panel: NSPanel?
    private weak var model: AppModel?
    private let presence = PillPresence()
    private var hideGeneration = 0

    private static let panelSize = NSSize(width: 420, height: 90)

    func attach(to model: AppModel) {
        self.model = model
    }

    func show() {
        guard let model else { return }
        hideGeneration += 1
        let panel = panel ?? makePanel(model: model)
        self.panel = panel
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        if let frame = screen?.visibleFrame, !presence.visible {
            panel.setFrameOrigin(NSPoint(x: frame.midX - Self.panelSize.width / 2, y: frame.minY + 8))
        }
        panel.orderFrontRegardless()
        withAnimation(.spring(duration: 0.35, bounce: 0.3)) { presence.visible = true }
    }

    /// The pill ignores the mouse except while it offers "↩ Raw".
    func setInteractive(_ interactive: Bool) {
        panel?.ignoresMouseEvents = !interactive
    }

    func hide(completion: @escaping () -> Void = {}) {
        guard presence.visible else { return completion() }
        hideGeneration += 1
        let generation = hideGeneration
        withAnimation(.easeIn(duration: 0.18)) { presence.visible = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self, generation == self.hideGeneration else { return }
            self.panel?.orderOut(nil)
            completion()
        }
    }

    private func makePanel(model: AppModel) -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: Self.panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        let host = ClickThroughHostingView(rootView: PillView(model: model, presence: presence))
        host.sizingOptions = []
        panel.contentView = host
        return panel
    }
}

/// Lets the first click on the pill press its button without activating Chordy.
private final class ClickThroughHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

struct PillView: View {
    let model: AppModel
    let presence: PillPresence

    var body: some View {
        VStack {
            Spacer(minLength: 0)
            PillContent(model: model)
                .padding(.horizontal, 14)
                .frame(height: 40)
                .background {
                    Capsule()
                        .fill(Color(white: 0.07).opacity(0.94))
                        .overlay(Capsule().strokeBorder(.white.opacity(0.12), lineWidth: 0.5))
                        .shadow(color: .black.opacity(0.35), radius: 12, y: 4)
                }
                .scaleEffect(presence.visible ? 1 : 0.8, anchor: .bottom)
                .opacity(presence.visible ? 1 : 0)
                .offset(y: presence.visible ? 0 : 10)
                .padding(.bottom, 18)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .environment(\.colorScheme, .dark)
    }
}

private struct PillContent: View {
    let model: AppModel

    private var tint: Color { model.activeMode.level == .raw ? .chordyMuted : .chordy }

    var body: some View {
        HStack(spacing: 10) {
            switch model.phase {
            case .recording, .locked, .idle:
                leading
                VocalCords(level: model.level, style: .live, tint: tint)
                    .frame(width: 96, height: 24)
                trailing
            case .processing:
                VocalCords(level: 0, style: .thinking, tint: tint)
                    .frame(width: 96, height: 24)
                Text(model.activeMode.level.usesLLM ? "Cleaning up" : "Transcribing")
                    .modifier(PillLabel())
            case .done(let outcome):
                OutcomeView(outcome: outcome, undo: model.undoToRaw)
            }
        }
        .fixedSize()
        .animation(.spring(duration: 0.35, bounce: 0.2), value: model.phase)
        .transition(.blurReplace)
    }

    @ViewBuilder private var leading: some View {
        if model.phase == .locked {
            Image(systemName: "lock.fill")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(tint)
                .transition(.scale.combined(with: .opacity))
        } else {
            Circle()
                .fill(tint)
                .frame(width: 8, height: 8)
                .scaleEffect(1 + CGFloat(model.level) * 0.6)
                .shadow(color: tint.opacity(0.8), radius: 4 + CGFloat(model.level) * 6)
                .animation(.easeOut(duration: 0.1), value: model.level)
        }
    }

    @ViewBuilder private var trailing: some View {
        if model.phase == .locked, let start = model.recordingStartedAt {
            TimelineView(.periodic(from: start, by: 1)) { context in
                let seconds = max(0, Int(context.date.timeIntervalSince(start)))
                Text(String(format: "%d:%02d", seconds / 60, seconds % 60))
                    .monospacedDigit()
                    .modifier(PillLabel())
            }
        } else {
            HStack(spacing: 4) {
                Image(systemName: model.activeMode.symbol).font(.system(size: 10, weight: .semibold))
                Text(model.modeName)
            }
            .modifier(PillLabel())
        }
    }
}

private struct OutcomeView: View {
    let outcome: AppModel.Outcome
    let undo: () -> Void

    var body: some View {
        let (symbol, color, text): (String, Color, String) = switch outcome {
        case .pasted: ("checkmark.circle.fill", .green, "Pasted")
        case .nothingHeard: ("waveform.slash", .chordyMuted, "Didn't catch that")
        case .cancelled: ("xmark.circle.fill", .chordyMuted, "Cancelled")
        case .failed(let message): ("exclamationmark.triangle.fill", .orange, message)
        }
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(color)
                .symbolEffect(.bounce, value: text)
            Text(text).modifier(PillLabel(emphasized: true))
            if outcome == .pasted(undoable: true) {
                Button(action: undo) {
                    Label("Raw", systemImage: "arrow.uturn.backward")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.9))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(.white.opacity(0.14)))
                }
                .buttonStyle(.plain)
                .help("Replace with exactly what you said")
            }
        }
    }
}

private struct PillLabel: ViewModifier {
    var emphasized = false

    func body(content: Content) -> some View {
        content
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundStyle(.white.opacity(emphasized ? 0.95 : 0.7))
            .lineLimit(1)
    }
}

/// Bars mirrored around the centre line with a bell-shaped envelope, like vibrating vocal cords.
/// Live: swells with the voice. Thinking: a gentle wave travels across while transcribing.
struct VocalCords: View {
    enum Style { case live, thinking }

    let level: Float
    let style: Style
    let tint: Color

    private let bars = 21

    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            Canvas { ctx, size in
                let spacing = size.width / CGFloat(bars)
                let barWidth = max(2, spacing * 0.5)
                let maxHeight = size.height
                for i in 0..<bars {
                    let x = Double(i) / Double(bars - 1)
                    let envelope = exp(-pow((x - 0.5) / 0.3, 2))
                    let height: Double
                    let opacity: Double
                    switch style {
                    case .live:
                        let wobble = 0.65 + 0.35 * sin(t * 11 + Double(i) * 0.9) * cos(t * 4.7 + Double(i) * 0.31)
                        let amplitude = 0.08 + 0.92 * Double(level)
                        height = 3 + (maxHeight - 3) * envelope * amplitude * wobble
                        opacity = 0.45 + 0.55 * envelope
                    case .thinking:
                        let wave = 0.5 + 0.5 * sin(t * 6 - Double(i) * 0.6)
                        height = 3 + maxHeight * 0.42 * envelope * wave
                        opacity = 0.3 + 0.5 * wave * envelope
                    }
                    let rect = CGRect(
                        x: CGFloat(i) * spacing + (spacing - barWidth) / 2,
                        y: (maxHeight - height) / 2,
                        width: barWidth,
                        height: height
                    )
                    let color = Color.white.mix(with: tint, by: min(1, envelope * 1.2))
                    ctx.fill(Path(roundedRect: rect, cornerRadius: barWidth / 2), with: .color(color.opacity(opacity)))
                }
            }
        }
    }
}
