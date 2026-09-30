import ChordyCore
import Foundation
import HuggingFace
import MLXHuggingFace
import MLXLLM
import MLXLMCommon
import Synchronization
import Tokenizers

/// Cleanup with a downloaded Qwen3 model running on the GPU through MLX.
public final class MLXCleaner: TextCleaner {
    public enum Model: String, Sendable, CaseIterable {
        case recommended = "mlx-community/Qwen3-4B-Instruct-2507-4bit"
        case lite = "mlx-community/Qwen3-1.7B-4bit"

        public var displayName: String {
            switch self {
            case .recommended: "Qwen3 4B"
            case .lite: "Qwen3 1.7B"
            }
        }

        /// The 1.7B checkpoint is a hybrid thinking model; thinking only adds latency here.
        var additionalContext: [String: any Sendable]? {
            self == .lite ? ["enable_thinking": false] : nil
        }
    }

    public let model: Model
    public var name: String { "\(model.displayName) (MLX)" }
    public var isAvailable: Bool { container.withLock { $0 != nil } }

    private let container = Mutex<ModelContainer?>(nil)

    public init(model: Model) {
        self.model = model
    }

    /// Downloads the model on first use (Hugging Face cache), then loads it into memory.
    public func prepare(progress: @escaping @Sendable (Double) -> Void) async throws {
        if isAvailable { return }
        let configuration = ModelConfiguration(id: model.rawValue)
        do {
            let loaded = try await #huggingFaceLoadModelContainer(configuration: configuration) { p in
                progress(p.fractionCompleted)
            }
            container.withLock { $0 = loaded }
        } catch {
            throw ChordyError.engineUnavailable(WhisperTranscriber.explain(error))
        }
    }

    public func clean(_ text: String, level: CleanupLevel, context: CleanupContext) async throws -> String {
        guard let loaded = container.withLock({ $0 }) else {
            throw ChordyError.engineUnavailable("\(name) isn't loaded")
        }
        // A fresh session per line so earlier dictations never leak into the next one.
        let session = ChatSession(
            loaded,
            instructions: CleanupPrompt.instructions(for: level, context: context),
            generateParameters: GenerateParameters(
                maxTokens: max(64, text.count / 2),
                temperature: 0
            ),
            additionalContext: model.additionalContext
        )
        let reply = try await session.respond(to: CleanupPrompt.userMessage(text))
        return Self.stripThinking(reply).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func stripThinking(_ text: String) -> String {
        guard let end = text.range(of: "</think>") else { return text }
        return String(text[end.upperBound...])
    }
}
