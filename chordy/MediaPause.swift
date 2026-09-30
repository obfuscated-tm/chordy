import AppKit

/// Pauses Music and Spotify while dictating and resumes whatever it paused.
/// Only talks to players that are already running, so it never launches one.
final class MediaPause {
    private static let players = [
        (bundleID: "com.apple.Music", name: "Music"),
        (bundleID: "com.spotify.client", name: "Spotify"),
    ]

    private let queue = DispatchQueue(label: "chordy.media")
    private var paused: [String] = []

    func pause() {
        let running = Self.players.filter { !NSRunningApplication.runningApplications(withBundleIdentifier: $0.bundleID).isEmpty }
        guard !running.isEmpty else { return }
        queue.async {
            for player in running {
                let script = """
                tell application "\(player.name)"
                    if player state is playing then
                        pause
                        return "paused"
                    end if
                end tell
                """
                if Self.run(script) == "paused" { self.paused.append(player.name) }
            }
        }
    }

    func resume() {
        queue.async {
            for name in self.paused { _ = Self.run("tell application \"\(name)\" to play") }
            self.paused = []
        }
    }

    private static func run(_ source: String) -> String? {
        var error: NSDictionary?
        return NSAppleScript(source: source)?.executeAndReturnError(&error).stringValue
    }
}
