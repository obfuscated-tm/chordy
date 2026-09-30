import AppKit
import ChordyCore
import SwiftUI
import UniformTypeIdentifiers

struct ModesSettings: View {
    @Bindable var model: AppModel
    @State var selection: Mode.ID?

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                List(selection: $selection) {
                    ForEach(model.modes) { mode in
                        HStack(spacing: 8) {
                            Image(systemName: mode.symbol)
                                .frame(width: 18)
                                .foregroundStyle(Color.chordy)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(mode.name)
                                Text(Self.summary(of: mode))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        .padding(.vertical, 2)
                        .tag(mode.id)
                    }
                    .onMove { model.modes.move(fromOffsets: $0, toOffset: $1) }
                }
                Divider()
                HStack(spacing: 2) {
                    Button {
                        let mode = Mode(name: "New Mode", symbol: "text.cursor", level: .clean, devRules: true)
                        model.modes.append(mode)
                        selection = mode.id
                    } label: {
                        Image(systemName: "plus").frame(width: 22, height: 18)
                    }
                    Button {
                        guard let selection, let i = model.modes.firstIndex(where: { $0.id == selection }) else { return }
                        model.modes.remove(at: i)
                        self.selection = model.modes.first?.id
                    } label: {
                        Image(systemName: "minus").frame(width: 22, height: 18)
                    }
                    .disabled(selectedMode?.builtIn != nil)
                    .help("Built-in modes can't be deleted")
                    Spacer()
                    Menu {
                        Button("Reset Built-in Modes") { model.resetBuiltInModes() }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }
                .buttonStyle(.borderless)
                .padding(6)
            }
            .frame(width: 200)
            Divider()
            if let index = model.modes.firstIndex(where: { $0.id == selection }) {
                ModeEditor(model: model, mode: $model.modes[index])
                    .id(model.modes[index].id)
            } else {
                ContentUnavailableView("Pick a mode", systemImage: "slider.horizontal.3")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear { selection = selection ?? model.modes.first?.id }
    }

    private var selectedMode: Mode? { model.modes.first { $0.id == selection } }

    static func summary(of mode: Mode) -> String {
        var parts = [mode.level.name]
        if mode.builtIn == .standard {
            parts.append("all other apps")
        } else if !mode.apps.isEmpty {
            parts.append(mode.apps.count == 1 ? mode.apps[0].name : "\(mode.apps.count) apps")
        }
        if let shortcut = mode.shortcut { parts.append(shortcut.displayName) }
        return parts.joined(separator: " · ")
    }
}

private struct ModeEditor: View {
    let model: AppModel
    @Binding var mode: Mode
    @State private var showAdvanced = false

    private static let symbols = [
        "text.bubble", "sparkles", "terminal", "doc.text", "waveform", "text.cursor", "envelope",
        "bubble.left.and.bubble.right", "chevron.left.forwardslash.chevron.right", "graduationcap", "list.bullet", "pencil",
    ]

    var body: some View {
        Form {
            Section {
                HStack {
                    SymbolPicker(symbol: $mode.symbol, symbols: Self.symbols)
                    TextField("Name", text: $mode.name)
                        .textFieldStyle(.roundedBorder)
                }
                LabeledContent("Cleanup") {
                    CleanupSlider(level: $mode.level)
                }
                Toggle(isOn: $mode.devRules) {
                    Text("Coding rules")
                    Text("“at src slash app dot ts” → @src/app.ts, “camel case user name” → userName")
                }
                .disabled(mode.level == .raw)
            }

            Section {
                if mode.builtIn == .standard {
                    Text("Used in every app that no other mode claims.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(mode.apps) { app in
                        HStack {
                            AppIcon(bundleID: app.bundleID)
                            Text(app.name)
                            Spacer()
                            Button {
                                mode.apps.removeAll { $0 == app }
                            } label: {
                                Image(systemName: "minus.circle.fill").foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    HStack {
                        Menu("Add Running App") {
                            ForEach(runningApps) { app in
                                Button(app.name) { add(app) }
                            }
                        }
                        .fixedSize()
                        Button("Choose…", action: chooseApp)
                    }
                }
            } header: {
                Text("Automatically use in")
            }

            Section {
                LabeledContent {
                    ShortcutRecorder(model: model, binding: "mode:\(mode.id.uuidString)", shortcut: $mode.shortcut, clearable: true)
                        .padding(.trailing, mode.shortcut == nil ? 0 : 22)
                } label: {
                    Text("Shortcut")
                    Text("Always dictate in this mode, whatever app you're in")
                }
                TextField("Before", text: $mode.prefix, prompt: Text("nothing"))
                TextField("After", text: $mode.suffix, prompt: Text("nothing"))
            } header: {
                Text("Extras")
            } footer: {
                Text("Text added before and after every dictation, e.g. a trailing space.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                DisclosureGroup("Advanced", isExpanded: $showAdvanced) {
                    TextEditor(text: $mode.customInstructions)
                        .font(.body)
                        .frame(height: 70)
                        .overlay(alignment: .topLeading) {
                            if mode.customInstructions.isEmpty {
                                Text("Extra instructions for cleanup, e.g. “Use British spelling.”")
                                    .foregroundStyle(.tertiary)
                                    .padding(.leading, 5)
                                    .allowsHitTesting(false)
                            }
                        }
                    Text("Most people never need this. Only used from Clean upward.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }

    private var runningApps: [AppRef] {
        let taken = Set(mode.apps.map(\.bundleID))
        return NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app in
                guard let id = app.bundleIdentifier, id != Bundle.main.bundleIdentifier, !taken.contains(id) else { return nil }
                return AppRef(bundleID: id, name: app.localizedName ?? id)
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private func chooseApp() {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            guard let bundle = Bundle(url: url), let id = bundle.bundleIdentifier else { continue }
            let name = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
            add(AppRef(bundleID: id, name: name))
        }
    }

    /// An app belongs to one mode at a time, so adding it here removes it elsewhere.
    private func add(_ app: AppRef) {
        for i in model.modes.indices where model.modes[i].id != mode.id {
            model.modes[i].apps.removeAll { $0.bundleID == app.bundleID }
        }
        if !mode.apps.contains(where: { $0.bundleID == app.bundleID }) { mode.apps.append(app) }
    }
}

/// Icon-only items don't render in macOS menus, so the icons live in a popover grid.
private struct SymbolPicker: View {
    @Binding var symbol: String
    let symbols: [String]
    @State private var open = false

    var body: some View {
        Button { open.toggle() } label: {
            HStack(spacing: 4) {
                Image(systemName: symbol).frame(width: 18)
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold)).foregroundStyle(.secondary)
            }
        }
        .help("Choose an icon")
        .popover(isPresented: $open, arrowEdge: .bottom) {
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(32), spacing: 4), count: 6), spacing: 4) {
                ForEach(symbols, id: \.self) { candidate in
                    Button {
                        symbol = candidate
                        open = false
                    } label: {
                        Image(systemName: candidate)
                            .font(.system(size: 14))
                            .frame(width: 32, height: 32)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(candidate == symbol ? Color.chordy.opacity(0.25) : Color.primary.opacity(0.05))
                            )
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(10)
        }
    }
}

struct AppIcon: View {
    let bundleID: String

    var body: some View {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable()
                .frame(width: 18, height: 18)
        } else {
            Image(systemName: "app.dashed").frame(width: 18, height: 18)
        }
    }
}

struct DictionarySettings: View {
    @Bindable var model: AppModel

    var body: some View {
        Form {
            Section {
                ForEach($model.vocabulary.entries) { $entry in
                    HStack {
                        TextField("Word", text: $entry.term, prompt: Text("Chordy"))
                            .frame(width: 150)
                        TextField("Sounds like", text: Binding(
                            get: { entry.soundsLike.joined(separator: ", ") },
                            set: { entry.soundsLike = $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) } }
                        ), prompt: Text("cordy, cord e (optional)"))
                        RemoveButton { model.vocabulary.entries.removeAll { $0.id == entry.id } }
                    }
                    .labelsHidden()
                }
                Button("Add Word") { model.vocabulary.entries.append(VocabularyEntry(term: "")) }
            } header: {
                Text("Words")
            } footer: {
                Text("Names, jargon and project words. Chordy hints them to the speech engine and fixes the mis-hearings you list.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                ForEach($model.snippets) { $snippet in
                    HStack(alignment: .top) {
                        TextField("Say", text: $snippet.trigger, prompt: Text("my email"))
                            .frame(width: 150)
                        TextField("Paste", text: $snippet.expansion, prompt: Text("me@example.com"), axis: .vertical)
                            .lineLimit(1...4)
                        RemoveButton { model.snippets.removeAll { $0.id == snippet.id } }
                    }
                    .labelsHidden()
                }
                Button("Add Snippet") { model.snippets.append(Snippet(trigger: "", expansion: "")) }
            } header: {
                Text("Snippets")
            } footer: {
                Text("Say the phrase on its own and Chordy pastes the text instead. Not used in Raw mode.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct RemoveButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "minus.circle.fill").foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .padding(.top, 3)
    }
}
