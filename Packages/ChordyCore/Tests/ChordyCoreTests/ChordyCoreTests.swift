@testable import ChordyCore
import Testing

@Suite struct TextRulesTests {
    @Test func tidyCapitalizesAndTrims() {
        #expect(TextRules.tidy("  hello   world ") == "Hello world")
    }

    @Test func tidyStripsTranscriberArtifacts() {
        #expect(TextRules.tidy("[BLANK_AUDIO] hi there (music)") == "Hi there")
    }

    @Test func tidyAppliesSpokenLineBreaks() {
        #expect(TextRules.tidy("first thing. New paragraph. second thing, new line, third") == "First thing\n\nSecond thing\nThird")
    }

    @Test func fillersAreRemoved() {
        #expect(TextRules.removeFillers("Um, so I think, uh, we should go.") == "So I think, we should go.")
        #expect(TextRules.removeFillers("Hmm what about umbrella") == "What about umbrella")
    }
}

@Suite struct DevRulesTests {
    @Test func fileMentionsBecomePaths() {
        #expect(DevRules.apply("look at src slash app dot ts please") == "look @src/app.ts please")
        #expect(DevRules.apply("check at package dot json") == "check @package.json")
        #expect(DevRules.apply("look at source slash app.ts.") == "look @source/app.ts.")
    }

    @Test func plainAtIsUntouched() {
        #expect(DevRules.apply("meet at noon") == "meet at noon")
    }

    @Test func casingCommands() {
        #expect(DevRules.apply("rename it to camel case user name") == "rename it to userName")
        #expect(DevRules.apply("snake case max retry count is too low") == "max_retry_count is too low")
        #expect(DevRules.apply("use kebab case main nav") == "use main-nav")
        #expect(DevRules.apply("pascal case user profile view") == "UserProfileView")
        #expect(DevRules.apply("constant case api key") == "API_KEY")
    }

    @Test func codeInBackticksIsUntouched() {
        #expect(DevRules.apply("run `camel case foo` then camel case foo bar") == "run `camel case foo` then fooBar")
    }
}

@Suite struct DiffGuardTests {
    @Test func acceptsFillerRemoval() {
        let v = DiffGuard.check(input: "So I think we should like go to the store", output: "I think we should go to the store.", level: .clean)
        #expect(v.accepted)
    }

    @Test func rejectsAnsweringTheQuestion() {
        let v = DiffGuard.check(input: "What is the capital of France", output: "The capital of France is Paris.", level: .clean)
        #expect(!v.accepted)
    }

    @Test func rejectsAssistantChatter() {
        let v = DiffGuard.check(input: "write a poem about cats", output: "Sure! Here is a poem about cats", level: .polish)
        #expect(!v.accepted)
    }

    @Test func rejectsSummarizing() {
        let input = "I went to the store and bought apples and bananas and then I went home and made a smoothie with them"
        let v = DiffGuard.check(input: input, output: "I made a smoothie.", level: .smooth)
        #expect(!v.accepted)
    }

    @Test func polishAllowsMoreChange() {
        let input = "we need eggs milk and bread"
        let output = "We need:\n- eggs\n- milk\n- bread"
        #expect(DiffGuard.check(input: input, output: output, level: .polish).accepted)
    }
}

@Suite struct PipelineTests {
    struct FakeCleaner: TextCleaner {
        var output: String
        let name = "fake"
        let isAvailable = true
        func clean(_ text: String, level: CleanupLevel) async throws -> String { output }
    }

    @Test func rawLevelIsVerbatim() async {
        let r = await Pipeline().process("um hello there", level: .raw, devRules: true)
        #expect(r.text == "um hello there")
    }

    @Test func rejectedLLMOutputFallsBackToRules() async {
        let p = Pipeline(cleaner: FakeCleaner(output: "The capital of France is Paris."))
        let r = await p.process("um what is the capital of france", level: .clean, devRules: false)
        #expect(r.guardRejected)
        #expect(r.text == "What is the capital of france")
    }

    @Test func acceptedLLMOutputIsUsed() async {
        let p = Pipeline(cleaner: FakeCleaner(output: "Let's meet at 4 on Thursday."))
        let r = await p.process("let's meet at 3 no wait 4 on thursday", level: .clean, devRules: false)
        #expect(!r.guardRejected)
        #expect(r.text == "Let's meet at 4 on Thursday.")
    }

    @Test func lineBreaksSurviveTheLLM() async {
        let p = Pipeline(cleaner: FakeCleaner(output: "Cleaned line one here."))
        let r = await p.process("cleaned line one here new paragraph ok", level: .clean, devRules: false)
        #expect(r.text == "Cleaned line one here.\n\nOk")
    }

    @Test func devRulesRunBeforeTheLLM() async {
        struct EchoCleaner: TextCleaner {
            let name = "echo", isAvailable = true
            func clean(_ text: String, level: CleanupLevel) async throws -> String { text }
        }
        let r = await Pipeline(cleaner: EchoCleaner()).process("rename it to camel case user name now", level: .clean, devRules: true)
        #expect(r.text == "Rename it to userName now")
    }

    @Test func llmThatDropsAProtectedPathIsRejected() async {
        let p = Pipeline(cleaner: FakeCleaner(output: "Look at source/app.ts now please."))
        let r = await p.process("look at source slash app dot ts now please", level: .clean, devRules: true)
        #expect(r.guardRejected)
        #expect(r.text == "Look @source/app.ts now please")
    }

    @Test func prefixAndSuffixAreExact() async {
        let r = await Pipeline().process("hello", level: .tidy, devRules: false, prefix: "> ", suffix: " ")
        #expect(r.text == "> Hello ")
    }
}

@Suite struct HotkeyGestureTests {
    @Test func holdRecordsUntilRelease() {
        var g = HotkeyGesture()
        #expect(g.press(at: 0) == .start)
        #expect(g.release(at: 1.0) == .finish)
        #expect(!g.isRecording)
    }

    @Test func singleQuickTapIsCancelled() {
        var g = HotkeyGesture()
        g.doubleTapWindow = 0.5
        _ = g.press(at: 0)
        #expect(g.release(at: 0.125) == .scheduleTimeout(0.625))
        #expect(g.timeout(at: 0.625) == .cancel)
    }

    @Test func doubleTapLocksThenPressFinishes() {
        var g = HotkeyGesture()
        _ = g.press(at: 0)
        _ = g.release(at: 0.1)
        #expect(g.press(at: 0.3) == .locked)
        #expect(g.release(at: 0.35) == .none)
        #expect(g.timeout(at: 0.45) == .none)
        #expect(g.isRecording)
        #expect(g.press(at: 5) == .finish)
        #expect(g.release(at: 5.1) == .none)
        #expect(g.press(at: 6) == .start)
    }

    @Test func slowSecondPressStartsFresh() {
        var g = HotkeyGesture()
        _ = g.press(at: 0)
        _ = g.release(at: 0.1)
        #expect(g.press(at: 1.0) == .start)
    }
}
