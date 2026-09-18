import Foundation

/// Lyrics together with the name of the source they came from.
struct FetchedLyrics: Equatable, Sendable {
    let lyrics: SyncedLyrics
    let source: String
}

/// A remote source of synced lyrics. `nil` means the source has no synced lyrics for the track.
protocol LyricsProvider: Sendable {
    func fetch(_ track: TrackInfo) async throws -> FetchedLyrics?
}
