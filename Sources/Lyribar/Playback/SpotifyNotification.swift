import Foundation

enum SpotifyNotification {
    static let name = Notification.Name("com.spotify.client.PlaybackStateChanged")

    // userInfo keys of com.spotify.client.PlaybackStateChanged, confirmed with Spotify 1.2.99.
    // Every notification carries: Track ID (String, "spotify:track:..."), Name, Artist, Album,
    // Album Artist (String), Duration (NSNumber, milliseconds), Playback Position (NSNumber,
    // fractional seconds), Player State (String: "Playing" / "Paused"; "Stopped" is handled but was
    // never observed), Disc Number, Track Number, Popularity, Play Count (NSNumber), Has Artwork (Bool).
    // Duration right after a track change can be provisional (222000, then 222027 for the same track).
    // Seeking does not post a notification.
    enum Key {
        static let trackID = "Track ID"
        static let title = "Name"
        static let artist = "Artist"
        static let durationMs = "Duration"
        static let position = "Playback Position"
        static let playerState = "Player State"
    }

    /// Returns nil when any required key is missing, so the caller can fall back to an AppleScript snapshot.
    static func playbackState(from userInfo: [AnyHashable: Any]?, now: Date) -> PlaybackState? {
        guard let userInfo, let playerState = userInfo[Key.playerState] as? String else { return nil }
        let isPlaying: Bool
        switch playerState {
        case "Playing": isPlaying = true
        case "Paused": isPlaying = false
        case "Stopped": return .empty(at: now)
        default: return nil
        }
        guard let id = userInfo[Key.trackID] as? String,
            let title = userInfo[Key.title] as? String,
            let artist = userInfo[Key.artist] as? String,
            let durationMs = (userInfo[Key.durationMs] as? NSNumber)?.doubleValue,
            let position = (userInfo[Key.position] as? NSNumber)?.doubleValue
        else { return nil }
        let track = TrackInfo(id: id, title: title, artist: artist, duration: durationMs / 1000)
        return PlaybackState(track: track, isPlaying: isPlaying, syncedPosition: position, syncedAt: now)
    }
}
