import Foundation

public protocol Transcriber: AnyObject, Sendable {
    var name: String { get }
    /// Downloads and loads whatever the engine needs. Progress is 0–1.
    func prepare(progress: @escaping @Sendable (Double) -> Void) async throws
    /// `hints` are vocabulary terms the engine should favour (names, jargon).
    func transcribe(_ samples: [Float], hints: [String]) async throws -> String
}
