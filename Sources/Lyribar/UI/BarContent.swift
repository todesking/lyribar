import Foundation

struct RibbonContent: Equatable {
    var lyrics: SyncedLyrics
    var currentIndex: Int?
}

struct BarContent: Equatable {
    /// The current line, in the current line mode.
    var lyric: String?
    /// Every line, in the scrolling mode. At most one of `lyric` and `ribbon` is set.
    var ribbon: RibbonContent?
    var trackInfo: String?
    /// Keep room for the lyric even when the current line is empty or missing, so that the bar does
    /// not jitter between lines while the track has lyrics.
    var reservesLyricWidth = false
}

extension TrackInfo {
    var displayText: String {
        artist.isEmpty ? title : "\(title) – \(artist)"
    }
}

/// The lyric is shown only while lyrics are found and the current line has text; it stays while paused.
/// In the scrolling mode the whole lyrics are handed over instead, whatever the current line is.
/// While the lyrics of the current track are found, the lyric width stays reserved even between lines.
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
    if case .found(let lyrics, _) = status {
        content.reservesLyricWidth = true
        switch settings.lyricsDisplayMode {
        case .scrolling:
            content.ribbon = RibbonContent(lyrics: lyrics, currentIndex: lineIndex)
        case .currentLine:
            if let lineIndex, lyrics.lines.indices.contains(lineIndex) {
                let text = lyrics.lines[lineIndex].text
                if !text.allSatisfy(\.isWhitespace) {
                    content.lyric = text
                }
            }
        }
    }
    return content
}

/// Index of the line to show for `state` at `now`, or nil when there are no lyrics to follow.
func currentLineIndex(state: PlaybackState, status: LyricsResolver.Status, now: Date) -> Int? {
    guard state.track != nil, case .found(let lyrics, _) = status else { return nil }
    return LineTracker.currentIndex(at: state.position(at: now), in: lyrics)
}

/// The resolver follows track changes slightly after the playback state does; until it catches up,
/// its status still describes the previous track and must not be shown.
func effectiveStatus(
    state: PlaybackState, resolvedTrack: TrackInfo?, status: LyricsResolver.Status
) -> LyricsResolver.Status {
    guard let track = state.track else { return .idle }
    return track.isSameTrack(as: resolvedTrack) ? status : .loading
}
