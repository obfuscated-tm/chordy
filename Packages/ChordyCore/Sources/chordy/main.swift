import ChordyCore
import Foundation

let usage = """
usage:
  chordy transcribe <audio-file> [--engine apple|whisper|whisper-lite] [--level 0-4]
  chordy process "<text>" [--level 0-4] [--no-dev]
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

let level = option("--level").flatMap(Int.init).flatMap(CleanupLevel.init(rawValue:)) ?? .clean
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
        let raw = try await transcriber.transcribe(samples)
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
default:
    fail(usage)
}
