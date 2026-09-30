@preconcurrency import AVFoundation
import Foundation
import Speech

/// Built-in tier: Apple's on-device SpeechAnalyzer. No Hugging Face download; Apple installs the locale assets.
public final class AppleSpeechTranscriber: Transcriber, @unchecked Sendable {
    public let name = "Apple Speech (built-in)"
    private let requestedLocale: Locale
    private var locale: Locale?

    public init(locale: Locale = Locale(identifier: "en-US")) {
        self.requestedLocale = locale
    }

    public func prepare(progress: @escaping @Sendable (Double) -> Void) async throws {
        guard let supported = await SpeechTranscriber.supportedLocale(equivalentTo: requestedLocale) else {
            throw ChordyError.engineUnavailable("Apple Speech doesn't support \(requestedLocale.identifier).")
        }
        locale = supported
        let module = SpeechTranscriber(locale: supported, preset: .transcription)
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [module]) {
            let observation = request.progress.observe(\.fractionCompleted) { p, _ in progress(p.fractionCompleted) }
            defer { observation.invalidate() }
            try await request.downloadAndInstall()
        }
        progress(1)
    }

    public func transcribe(_ samples: [Float]) async throws -> String {
        if locale == nil { try await prepare { _ in } }
        guard let locale, !samples.isEmpty, let buffer = AudioFormat.buffer(from: samples) else { return "" }

        let module = SpeechTranscriber(locale: locale, preset: .transcription)
        let analyzer = SpeechAnalyzer(modules: [module])
        let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [module]) ?? AudioFormat.format
        let input = try AudioFormat.convert(buffer, to: format)

        let collector = Task {
            var text = ""
            for try await result in module.results where result.isFinal {
                text += String(result.text.characters)
            }
            return text
        }

        let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
        continuation.yield(AnalyzerInput(buffer: input))
        continuation.finish()
        if let end = try await analyzer.analyzeSequence(stream) {
            try await analyzer.finalizeAndFinish(through: end)
        } else {
            await analyzer.cancelAndFinishNow()
        }
        return try await collector.value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
