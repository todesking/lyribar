import Foundation

struct BarContent: Equatable {
    var lyric: String?
    var trackInfo: String?
}

extension TrackInfo {
    var displayText: String {
        artist.isEmpty ? title : "\(title) – \(artist)"
    }
}

/// The lyric is shown only while lyrics are found and the current line has text; it stays while paused.
/// Without a track (Spotify not running, or stopped) nothing is shown.
@MainActor
func barContent(
    state: PlaybackState,
    status: LyricsResolver.Status,
    lineIndex: Int?,
    settings: Settings
) -> BarContent {
    guard let track = state.track else { return BarContent() }

    var content = BarContent()
    if settings.showTrackInfo {
        content.trackInfo = track.displayText
    }
    if case .found(let lyrics, _) = status, let lineIndex, lyrics.lines.indices.contains(lineIndex) {
        let text = lyrics.lines[lineIndex].text
        if !text.allSatisfy(\.isWhitespace) {
            content.lyric = text
        }
    }
    return content
}

/// Index of the line to show for `state` at `now`, or nil when there are no lyrics to follow.
func currentLineIndex(state: PlaybackState, status: LyricsResolver.Status, now: Date) -> Int? {
    guard state.track != nil, case .found(let lyrics, _) = status else { return nil }
    return LineTracker.currentIndex(at: state.position(at: now), in: lyrics)
}
