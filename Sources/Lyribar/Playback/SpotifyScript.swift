import AppKit

/// The outcome of one AppleScript snapshot. `.failed` is kept apart from `.notRunning` so that a
/// script error (Apple Event timeout, Automation denied, unexpected output) does not look like
/// "Spotify is gone" to the caller.
enum SpotifySnapshot: Equatable, Sendable {
    case state(PlaybackState)
    case notRunning
    case failed
}

// NSAppleScript is not Sendable; it is only touched from `queue`.
final class SpotifyScript: @unchecked Sendable {
    static let bundleIdentifier = "com.spotify.client"
    static let separator = "\u{1}"

    private static let source = """
        tell application "Spotify"
            set sep to character id 1
            set s to player state as text
            if s is "stopped" then return s
            set t to current track
            return s & sep & (id of t) & sep & (name of t) & sep & (artist of t) & sep & ((duration of t) as text) & sep & (player position as text)
        end tell
        """

    private let queue = DispatchQueue(label: "com.todesking.lyribar.spotify-script")
    private var script: NSAppleScript?

    static var isSpotifyRunning: Bool {
        NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == bundleIdentifier }
    }

    func snapshot() async -> SpotifySnapshot {
        await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: self.run())
            }
        }
    }

    private func run() -> SpotifySnapshot {
        // Sending an Apple Event to Spotify would launch it, so never do that unless it is running.
        guard Self.isSpotifyRunning else { return .notRunning }
        if script == nil {
            let compiled = NSAppleScript(source: Self.source)
            var error: NSDictionary?
            guard let compiled, compiled.compileAndReturnError(&error) else { return .failed }
            script = compiled
        }
        var error: NSDictionary?
        guard let output = script?.executeAndReturnError(&error).stringValue, error == nil else { return .failed }
        guard let state = Self.parse(output, now: Date()) else { return .failed }
        return .state(state)
    }

    static func parse(_ output: String, now: Date) -> PlaybackState? {
        let fields = output.components(separatedBy: separator)
        if fields == ["stopped"] {
            return .empty(at: now)
        }
        guard fields.count == 6,
            let durationMs = number(fields[4]),
            let position = number(fields[5])
        else { return nil }
        let isPlaying: Bool
        switch fields[0] {
        case "playing": isPlaying = true
        case "paused": isPlaying = false
        default: return nil
        }
        let track = TrackInfo(id: fields[1], title: fields[2], artist: fields[3], duration: durationMs / 1000)
        return PlaybackState(track: track, isPlaying: isPlaying, syncedPosition: position, syncedAt: now)
    }

    // AppleScript formats reals with the user's decimal separator.
    private static func number(_ text: String) -> Double? {
        Double(text.replacingOccurrences(of: ",", with: "."))
    }
}
