@testable import ChordyCore
import Foundation
import Testing

@Suite struct ModeTests {
    @Test func resolvesByApp() {
        let modes = Mode.defaults
        #expect(Mode.resolve(in: modes, bundleID: "com.mitchellh.ghostty").builtIn == .terminal)
        #expect(Mode.resolve(in: modes, bundleID: "com.anthropic.claudefordesktop").builtIn == .prompt)
        #expect(Mode.resolve(in: modes, bundleID: "com.apple.Safari").builtIn == .standard)
        #expect(Mode.resolve(in: modes, bundleID: nil).builtIn == .standard)
    }

    @Test func builtInIDsAreStable() {
        #expect(Mode.builtIn(.essay).id == Mode.builtIn(.essay).id)
        #expect(Set(Mode.defaults.map(\.id)).count == Mode.BuiltIn.allCases.count)
    }

    @Test func modesRoundTripThroughJSON() throws {
        var mode = Mode.builtIn(.prompt)
        mode.shortcut = .combo(keyCode: 49, label: "Space", modifiers: [.option])
        let decoded = try JSONDecoder().decode(Mode.self, from: JSONEncoder().encode(mode))
        #expect(decoded == mode)
    }
}

@Suite struct VocabularyTests {
    let vocab = Vocabulary([
        VocabularyEntry(term: "Chordy", soundsLike: ["cordy", "cordie"]),
        VocabularyEntry(term: "GitHub"),
    ])

    @Test func fixesMishearingsAndCasing() {
        #expect(vocab.apply("open cordy and push to github") == "open Chordy and push to GitHub")
    }

    @Test func wholeWordsOnly() {
        #expect(vocab.apply("accordys githubber") == "accordys githubber")
    }

    @Test func snippetsMatchWholeUtteranceOnly() {
        let snippets = [Snippet(trigger: "my email", expansion: "me@example.com")]
        #expect(Snippet.match("My email.", in: snippets)?.expansion == "me@example.com")
        #expect(Snippet.match("send it to my email", in: snippets) == nil)
    }

    @Test func pipelineUsesSnippetsAndVocabulary() async {
        let options = Pipeline.Options(
            level: .tidy, devRules: false,
            vocabulary: vocab, snippets: [Snippet(trigger: "sign off", expansion: "Thanks,\nOwen")]
        )
        #expect(await Pipeline().process("Sign off!", options: options).text == "Thanks,\nOwen")
        #expect(await Pipeline().process("i love cordy", options: options).text == "I love Chordy")
    }

    @Test func rawModeIgnoresSnippets() async {
        let options = Pipeline.Options(level: .raw, devRules: false, snippets: [Snippet(trigger: "hi", expansion: "Hello!")])
        #expect(await Pipeline().process("hi", options: options).text == "hi")
    }
}

@Suite struct SilenceTests {
    func tone(_ seconds: Double, amplitude: Float) -> [Float] {
        (0..<Int(16_000 * seconds)).map { amplitude * sin(Float($0) * 0.2) }
    }

    @Test func silenceIsNil() {
        #expect(Silence.trim(tone(1.0, amplitude: 0.001)) == nil)
    }

    @Test func trimsQuietEdges() throws {
        let samples = tone(1.0, amplitude: 0.001) + tone(0.5, amplitude: 0.2) + tone(1.0, amplitude: 0.001)
        let trimmed = try #require(Silence.trim(samples))
        // 0.5 s of speech plus 0.25 s padding each side.
        #expect(abs(Double(trimmed.count) / 16_000 - 1.0) < 0.05)
    }
}

@Suite struct WordDiffTests {
    @Test func marksRemovedAndAdded() {
        let d = WordDiff.diff("so um I think we go", "I think we should go.")
        #expect(d == [
            .init(kind: .removed, text: "so um"),
            .init(kind: .same, text: "I think we"),
            .init(kind: .removed, text: "go"),
            .init(kind: .added, text: "should go."),
        ])
    }
}

@Suite struct EvalTests {
    @Test func similarityIgnoresCaseAndPunctuation() {
        #expect(Eval.similarity("Hello, world!", "hello world") == 1)
    }

    @Test func similarityPenalisesChanges() {
        let s = Eval.similarity("send it to Jane", "send it to John")
        #expect(s == 0.75)
    }

    @Test func casesFileParses() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Evals/cleanup.json")
        let cases = try JSONDecoder().decode([EvalCase].self, from: Data(contentsOf: url))
        #expect(cases.count >= 40)
    }
}

@Suite struct CorrectionGuardTests {
    @Test func allowsSelfCorrections() {
        #expect(DiffGuard.check(input: "let's meet at 3 no wait 4 pm", output: "Let's meet at 4 pm.", level: .clean).accepted)
    }

    @Test func stillRejectsSummaries() {
        #expect(!DiffGuard.check(input: "let's meet at the cafe on main street at noon", output: "Meet at noon.", level: .clean).accepted)
    }
}
