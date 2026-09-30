import Foundation

/// Turns raw press/release events of the dictation key into recording actions.
///
/// - Hold: press starts recording, release stops and transcribes.
/// - Double-tap: a quick tap followed by a second press locks recording on; the next press finishes.
/// - A single quick tap with no follow-up is discarded.
public struct HotkeyGesture: Sendable {
    public enum Action: Equatable, Sendable {
        case none
        case start
        case finish
        case cancel
        case locked
        /// Call `timeout(at:)` at this time if nothing else happens.
        case scheduleTimeout(TimeInterval)
    }

    enum State: Equatable {
        case idle
        case holding(since: TimeInterval)
        case awaitingSecondTap(releasedAt: TimeInterval)
        case locked
        case waitingForRelease
    }

    public var tapThreshold: TimeInterval = 0.25
    public var doubleTapWindow: TimeInterval = 0.35
    private(set) var state: State = .idle

    public init() {}

    public var isRecording: Bool {
        switch state {
        case .holding, .awaitingSecondTap, .locked: true
        case .idle, .waitingForRelease: false
        }
    }

    public mutating func press(at t: TimeInterval) -> Action {
        switch state {
        case .idle:
            state = .holding(since: t)
            return .start
        case .awaitingSecondTap(let releasedAt) where t - releasedAt <= doubleTapWindow:
            state = .locked
            return .locked
        case .awaitingSecondTap:
            state = .holding(since: t)
            return .start
        case .locked:
            state = .waitingForRelease
            return .finish
        case .holding, .waitingForRelease:
            return .none
        }
    }

    public mutating func release(at t: TimeInterval) -> Action {
        switch state {
        case .holding(let since) where t - since < tapThreshold:
            state = .awaitingSecondTap(releasedAt: t)
            return .scheduleTimeout(t + doubleTapWindow)
        case .holding:
            state = .idle
            return .finish
        case .waitingForRelease:
            state = .idle
            return .none
        case .idle, .awaitingSecondTap, .locked:
            return .none
        }
    }

    public mutating func timeout(at t: TimeInterval) -> Action {
        guard case .awaitingSecondTap(let releasedAt) = state, t - releasedAt >= doubleTapWindow else { return .none }
        state = .idle
        return .cancel
    }

    /// Abort from outside (e.g. Escape pressed or an error).
    public mutating func reset() { state = .idle }
}
