import Foundation

/// Energy-based speech detection: trims silence at both ends and spots recordings with no speech at all
/// (which Whisper tends to "hear" as "Thank you.").
public enum Silence {
    /// Returns the samples with leading/trailing silence removed, or nil if nothing sounds like speech.
    public static func trim(_ samples: [Float], sampleRate: Double = AudioFormat.sampleRate) -> [Float]? {
        let frame = Int(sampleRate * 0.02)
        guard samples.count >= frame else { return nil }
        let rms = stride(from: 0, to: samples.count - frame + 1, by: frame).map { start -> Float in
            var sum: Float = 0
            for i in start..<start + frame { sum += samples[i] * samples[i] }
            return sqrt(sum / Float(frame))
        }
        let floor = rms.sorted()[rms.count / 10]
        // About -46 dBFS minimum, or 3.5× the room's noise floor, whichever is louder.
        let threshold = max(0.005, floor * 3.5)
        let loud = rms.indices.filter { rms[$0] > threshold }
        // Need at least ~100 ms of speech.
        guard loud.count >= 5, let first = loud.first, let last = loud.last else { return nil }
        let pad = Int(0.25 / 0.02)
        let start = max(0, first - pad) * frame
        let end = min(samples.count, (last + 1 + pad) * frame)
        return Array(samples[start..<end])
    }
}
