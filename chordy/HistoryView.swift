import ChordyCore
import SwiftUI

struct HistoryView: View {
    @Bindable var model: AppModel
    @State private var selection: HistoryEntry.ID?
    @State private var search = ""

    private var entries: [HistoryEntry] {
        guard !search.isEmpty else { return model.history }
        return model.history.filter { $0.text.localizedCaseInsensitiveContains(search) || $0.raw.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                ForEach(entries) { entry in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.preview).lineLimit(2)
                        Text("\(entry.date.formatted(.relative(presentation: .named))) · \(entry.mode)\(entry.app.map { " · \($0)" } ?? "")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                    .tag(entry.id)
                    .contextMenu {
                        Button("Copy") { model.copyToClipboard(entry.text) }
                        Button("Copy Raw") { model.copyToClipboard(entry.raw) }
                        Divider()
                        Button("Delete", role: .destructive) { model.deleteHistory([entry.id]) }
                    }
                }
                .onDelete { offsets in model.deleteHistory(Set(offsets.map { entries[$0].id })) }
            }
            .searchable(text: $search, placement: .sidebar)
            .navigationSplitViewColumnWidth(min: 220, ideal: 260)
            .overlay {
                if model.history.isEmpty {
                    ContentUnavailableView(
                        "No dictations yet",
                        systemImage: "waveform",
                        description: Text(model.historyRetention == .never ? "History is turned off in Settings." : "Kept for \(model.historyRetention.label.lowercased()).")
                    )
                }
            }
        } detail: {
            if let entry = model.history.first(where: { $0.id == selection }) {
                HistoryDetail(model: model, entry: entry)
            } else {
                ContentUnavailableView("Pick a dictation", systemImage: "text.bubble")
            }
        }
        .frame(minWidth: 640, minHeight: 400)
        .onAppear { selection = selection ?? model.history.first?.id }
    }
}

private struct HistoryDetail: View {
    let model: AppModel
    let entry: HistoryEntry
    @State private var showDiff = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text(entry.date.formatted(date: .abbreviated, time: .shortened))
                    Text("·")
                    Text(entry.mode)
                    if let app = entry.app {
                        Text("·")
                        Text(app)
                    }
                }
                .font(.callout)
                .foregroundStyle(.secondary)

                GroupBox {
                    Group {
                        if showDiff { DiffText(old: entry.raw, new: entry.text) } else { Text(entry.text) }
                    }
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(6)
                } label: {
                    HStack {
                        Text("Pasted")
                        Spacer()
                        Toggle("Show changes", isOn: $showDiff)
                            .toggleStyle(.switch)
                            .controlSize(.mini)
                    }
                }

                GroupBox("What you said") {
                    Text(entry.raw)
                        .textSelection(.enabled)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(6)
                }

                HStack {
                    Button("Copy") { model.copyToClipboard(entry.text) }
                    Button("Copy Raw") { model.copyToClipboard(entry.raw) }
                    Spacer()
                    Button("Delete", role: .destructive) { model.deleteHistory([entry.id]) }
                }
            }
            .padding(20)
        }
    }
}

/// Removed words struck through in red, added words highlighted in green.
struct DiffText: View {
    let old: String
    let new: String

    var body: some View {
        WordDiff.diff(old, new).reduce(Text("")) { text, segment in
            switch segment.kind {
            case .same:
                text + Text(segment.text + " ")
            case .removed:
                text + Text(segment.text).strikethrough().foregroundColor(.red.opacity(0.75)) + Text(" ")
            case .added:
                text + Text(segment.text).foregroundColor(.green).bold() + Text(" ")
            }
        }
    }
}
