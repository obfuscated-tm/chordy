import ChordyCore
import Foundation

let usage = """
usage:
  chordy transcribe <audio-file> [--engine apple|whisper|whisper-lite] [--level 0-4]
  chordy process "<text>" [--level 0-4] [--no-dev]
  chordy mics
  chordy eval [cases.json] [--level 0-4] [--verbose]
"""

var args = Array(CommandLine.arguments.dropFirst())

func option(_ name: String) -> String? {
    guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
    let value = args[i + 1]
    args.removeSubrange(i...i + 1)
    return value
}

func flag(_ name: String) -> Bool {
    guard let i = args.firstIndex(of: name) else { return false }
    args.remove(at: i)
    return true
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

let levelFilter = option("--level").flatMap(Int.init).flatMap(CleanupLevel.init(rawValue:))
let verbose = flag("--verbose")
let level = levelFilter ?? .clean
let engineName = option("--engine") ?? "apple"
let devRules = !flag("--no-dev")
let pipeline = Pipeline(cleaner: AppleIntelligenceCleaner())

guard let command = args.first else { fail(usage) }

switch command {
case "transcribe":
    guard args.count >= 2 else { fail(usage) }
    let transcriber: any Transcriber = switch engineName {
    case "whisper": WhisperTranscriber(model: .recommended)
    case "whisper-lite": WhisperTranscriber(model: .lite)
    default: AppleSpeechTranscriber()
    }
    do {
        let samples = try AudioFormat.loadSamples(from: URL(fileURLWithPath: args[1]))
        let clock = ContinuousClock()
        let prepStart = clock.now
        try await transcriber.prepare { p in FileHandle.standardError.write(Data("\rpreparing \(transcriber.name): \(Int(p * 100))%".utf8)) }
        FileHandle.standardError.write(Data("\n".utf8))
        let t0 = clock.now
        let raw = try await transcriber.transcribe(samples, hints: [])
        let t1 = clock.now
        let result = await pipeline.process(raw, level: level, devRules: devRules)
        let t2 = clock.now
        print("raw:     \(raw)")
        print("final:   \(result.text)")
        print("timing:  prepare \(t0 - prepStart), transcribe \(t1 - t0), cleanup \(t2 - t1) (llm: \(result.usedLLM), rejected: \(result.guardRejected))")
    } catch {
        fail("error: \(error.localizedDescription)")
    }
case "process":
    guard args.count >= 2 else { fail(usage) }
    let result = await pipeline.process(args[1], level: level, devRules: devRules)
    print(result.text)
    if result.guardRejected { FileHandle.standardError.write(Data("(LLM output rejected by diff guard)\n".utf8)) }
case "eval":
    let defaultPath = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "Evals/cleanup.json")
    let path = args.count >= 2 ? URL(fileURLWithPath: args[1]) : defaultPath
    let cleaner = AppleIntelligenceCleaner()
    guard cleaner.isAvailable else { fail("Apple Intelligence isn't available, so LLM levels can't be evaluated.") }
    let cases: [EvalCase]
    do { cases = try JSONDecoder().decode([EvalCase].self, from: Data(contentsOf: path)) } catch { fail("can't read \(path.path): \(error)") }

    struct Tally { var count = 0, exact = 0, rejected = 0; var similarity = 0.0 }
    var tallies: [CleanupLevel: Tally] = [:]
    let clock = ContinuousClock()
    var totalTime = Duration.zero
    for c in cases where levelFilter == nil || c.level == levelFilter {
        let start = clock.now
        let result = await pipeline.process(c.input, options: .init(level: c.level, devRules: true))
        totalTime += clock.now - start
        let sim = Eval.similarity(result.text, c.expect)
        let exact = Eval.exact(result.text, c.expect)
        tallies[c.level, default: Tally()].count += 1
        tallies[c.level, default: Tally()].similarity += sim
        if exact { tallies[c.level, default: Tally()].exact += 1 }
        if result.guardRejected { tallies[c.level, default: Tally()].rejected += 1 }
        if verbose || sim < 0.8 {
            let mark = exact ? "✓" : sim >= 0.8 ? "~" : "✗"
            print("\(mark) [\(c.level.rawValue)] \(c.note ?? "")  sim \(String(format: "%.2f", sim))\(result.guardRejected ? "  (guard rejected)" : "")")
            print("    in:     \(c.input.replacingOccurrences(of: "\n", with: "⏎"))")
            print("    want:   \(c.expect.replacingOccurrences(of: "\n", with: "⏎"))")
            print("    got:    \(result.text.replacingOccurrences(of: "\n", with: "⏎"))")
        }
    }
    func row(_ name: String, _ t: Tally) -> String {
        name.padding(toLength: 10, withPad: " ", startingAt: 0)
            + String(format: " %5d  %5d  %10.2f  %14d", t.count, t.exact, t.similarity / Double(max(t.count, 1)), t.rejected)
    }
    print("\nlevel      cases  exact  similarity  guard-rejected")
    var all = Tally()
    for level in CleanupLevel.allCases {
        guard let t = tallies[level] else { continue }
        print(row(level.name, t))
        all.count += t.count; all.exact += t.exact; all.similarity += t.similarity; all.rejected += t.rejected
    }
    print(row("all", all))
    print("cleaner: \(cleaner.name), total time \(totalTime)")
case "mics":
    for device in AudioInputDevice.all() { print("\(device.name)  [\(device.id)]") }
default:
    fail(usage)
}
