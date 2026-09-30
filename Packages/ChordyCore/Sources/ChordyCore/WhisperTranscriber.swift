import Foundation
import WhisperKit

/// Downloaded tier: WhisperKit (Core ML) with models from Hugging Face.
public actor WhisperTranscriber: Transcriber {
    public enum Model: String, CaseIterable, Sendable {
        /// ~630 MB, best accuracy/speed balance.
        case recommended = "openai_whisper-large-v3-v20240930_turbo_632MB"
        /// ~250 MB, English only, for older or 8 GB Macs.
        case lite = "openai_whisper-small.en"
    }

    public nonisolated let name: String
    public let model: Model
    public let downloadBase: URL
    private var kit: WhisperKit?

    public init(model: Model = .recommended, downloadBase: URL = WhisperTranscriber.defaultDownloadBase) {
        self.model = model
        self.downloadBase = downloadBase
        self.name = "Whisper (\(model == .recommended ? "large-v3 turbo" : "small.en"))"
    }

    public static var defaultDownloadBase: URL {
        URL.applicationSupportDirectory.appending(path: "Chordy/models", directoryHint: .isDirectory)
    }

    /// Where the Hub client places the model; checked so an offline launch doesn't need the network.
    public var localModelFolder: URL {
        downloadBase.appending(path: "models/argmaxinc/whisperkit-coreml/\(model.rawValue)", directoryHint: .isDirectory)
    }

    public var isDownloaded: Bool {
        FileManager.default.fileExists(atPath: localModelFolder.appending(path: "AudioEncoder.mlmodelc").path)
    }

    public func prepare(progress: @escaping @Sendable (Double) -> Void) async throws {
        if kit != nil { return }
        let folder: URL
        if isDownloaded {
            folder = localModelFolder
        } else {
            do {
                folder = try await WhisperKit.download(variant: model.rawValue, downloadBase: downloadBase) { p in
                    progress(p.fractionCompleted * 0.9)
                }
            } catch {
                throw ChordyError.modelDownloadFailed(Self.explain(error))
            }
        }
        let config = WhisperKitConfig(modelFolder: folder.path, verbose: false, logLevel: .error, prewarm: true, load: true, download: false)
        kit = try await WhisperKit(config)
        progress(1)
    }

    public func transcribe(_ samples: [Float]) async throws -> String {
        if kit == nil { try await prepare { _ in } }
        guard let kit, !samples.isEmpty else { return "" }
        let options = DecodingOptions(language: "en", skipSpecialTokens: true, withoutTimestamps: true)
        let results = try await kit.transcribe(audioArray: samples, decodeOptions: options)
        return results.map(\.text).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func explain(_ error: Error) -> String {
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain, [-1202, -1201, -1203, -1204, -1205, -1206].contains(ns.code) {
            return "Couldn't download the Whisper model: huggingface.co's certificate was rejected. A network filter (school or work) is probably intercepting it. Try another network; Chordy uses Apple Speech until then."
        }
        if ns.domain == NSURLErrorDomain {
            return "Couldn't download the Whisper model (\(ns.localizedDescription)). Chordy uses Apple Speech until it can."
        }
        return "Couldn't download the Whisper model: \(error.localizedDescription)"
    }
}
