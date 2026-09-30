#if DEBUG && canImport(ChordyMLX)
import ChordyCore
import ChordyMLX
import Foundation

/// `Chordy --mlx-eval <cases.json> [recommended|lite]` runs the eval set through the MLX cleaner.
/// Lives in the app because MLX needs the Metal library that only the Xcode build bundles.
enum MLXEvalHook {
    static func runIfRequested() {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--mlx-eval"), i + 1 < args.count else { return }
        let path = URL(fileURLWithPath: args[i + 1])
        let model: MLXCleaner.Model = args.dropFirst(i + 2).first == "recommended" ? .recommended : .lite
        var done = false
        Task.detached {
            await run(path: path, model: model)
            done = true
        }
        while !done { RunLoop.main.run(until: Date().addingTimeInterval(0.1)) }
        exit(0)
    }

    private static func run(path: URL, model: MLXCleaner.Model) async {
        let cleaner = MLXCleaner(model: model)
        do {
            let clock = ContinuousClock()
            let start = clock.now
            try await cleaner.prepare { p in FileHandle.standardError.write(Data("\rloading \(cleaner.name) \(Int(p * 100))%".utf8)) }
            print("\nloaded in \(clock.now - start)")
            let cases = try JSONDecoder().decode([EvalCase].self, from: Data(contentsOf: path))
            let pipeline = Pipeline(cleaner: cleaner)
            var exact = 0, rejected = 0, sim = 0.0
            let t0 = clock.now
            for c in cases {
                let r = await pipeline.process(c.input, options: .init(level: c.level, devRules: true))
                let s = Eval.similarity(r.text, c.expect)
                sim += s
                if Eval.exact(r.text, c.expect) { exact += 1 }
                if r.guardRejected { rejected += 1 }
                if s < 0.8 || r.guardRejected {
                    print("✗ [\(c.level.rawValue)] \(c.note ?? "") sim \(String(format: "%.2f", s))\(r.guardRejected ? " (guard)" : "")\n    want: \(c.expect)\n    got:  \(r.text)")
                }
            }
            print("\(cleaner.name): \(exact)/\(cases.count) exact, similarity \(String(format: "%.2f", sim / Double(cases.count))), guard rejected \(rejected), time \(clock.now - t0)")
        } catch {
            print("failed: \(error.localizedDescription)")
        }
    }
}
#endif
