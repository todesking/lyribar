import Foundation

/// A remote source of synced lyrics. `nil` means the source has no synced lyrics for the track.
protocol LyricsProvider: Sendable {
    func fetch(_ track: TrackInfo) async throws -> SyncedLyrics?
}
