import ChordyCore
import SwiftUI

/// Settings → neo-plan: two switches, off until turned on, and the connection they need.
struct NeoPlanSettings: View {
    @Bindable var model: AppModel
    @State private var token = ""
    @State private var test: TestState = .idle

    enum TestState: Equatable { case idle, running, ok, failed(String) }

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $model.neoPlanAdd) {
                    Text("Add items by voice")
                    Text("“Chemistry quiz due Friday” → a new item in that class")
                }
                Toggle(isOn: $model.neoPlanMark) {
                    Text("Mark done and turned in by voice")
                    Text("“Done with problem set 4” · “Turned in the titration lab”")
                }
            } header: {
                Text("Voice to neo-plan")
            } footer: {
                Text("Both are off until you turn them on. Neither one pastes anything, and the shortcut below does nothing while both are off.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                LabeledContent {
                    ShortcutRecorder(
                        model: model,
                        binding: AppModel.neoPlanBinding,
                        shortcut: $model.neoPlanShortcut,
                        clearable: true
                    )
                } label: {
                    Text("Talk to neo-plan")
                    Text("Hold to talk, like Dictate")
                }
            } header: {
                Text("Shortcut")
            } footer: {
                if model.neoPlanEnabled, !model.neoPlanConnected {
                    Text("Add a token below first, or the shortcut has nowhere to send things.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            .disabled(!model.neoPlanEnabled)

            Section {
                TextField("Address", text: $model.neoPlanURL)
                    .textContentType(.URL)
                if model.neoPlanConnected {
                    LabeledContent("Token") {
                        HStack {
                            Label("Saved in your Keychain", systemImage: "key.fill")
                                .foregroundStyle(.secondary)
                            Button("Remove") {
                                model.saveNeoPlanToken(nil)
                                test = .idle
                            }
                        }
                    }
                } else {
                    LabeledContent("Token") {
                        HStack {
                            SecureField("np_…", text: $token)
                                .labelsHidden()
                                .frame(minWidth: 200)
                            Button("Save") {
                                model.saveNeoPlanToken(token.trimmingCharacters(in: .whitespacesAndNewlines))
                                token = ""
                                runTest()
                            }
                            .disabled(token.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                    }
                }
                HStack {
                    Button("Test Connection", action: runTest)
                        .disabled(!model.neoPlanConnected || test == .running)
                    switch test {
                    case .idle: EmptyView()
                    case .running: ProgressView().controlSize(.small)
                    case .ok: Label("Connected", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    case .failed(let message): Label(message, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    }
                }
                .font(.callout)
            } header: {
                Text("Connection")
            } footer: {
                Text("In neo-plan, open Settings → Extension → New token, and paste it here. Revoking it in neo-plan turns this off.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func runTest() {
        test = .running
        Task {
            let problem = await model.testNeoPlan()
            test = problem.map(TestState.failed) ?? .ok
        }
    }
}
