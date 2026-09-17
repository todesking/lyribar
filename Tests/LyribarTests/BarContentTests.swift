import Foundation
import Testing
@testable import Lyribar

@MainActor
struct BarContentTests {
    private struct StubError: Error {}

    private let track = TrackInfo(id: "spotify:track:abc", title: "Song", artist: "Artist", duration: 200)
    private let syncedAt = Date(timeIntervalSince1970: 1_000)
    private let lyrics = SyncedLyrics(lines: [
        LyricLine(time: 10, text: "first"),
        LyricLine(time: 20, text: ""),
        LyricLine(time: 30, text: "third"),
    ])

    private func makeSettings(showTrackInfo: Bool = true) -> Settings {
        let suite = "LyribarTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let settings = Settings(defaults: defaults)
        settings.showTrackInfo = showTrackInfo
        defaults.removePersistentDomain(forName: suite)
        return settings
    }

    private func state(playing: Bool = true, position: TimeInterval = 0) -> PlaybackState {
        PlaybackState(track: track, isPlaying: playing, syncedPosition: position, syncedAt: syncedAt)
    }

    private var found: LyricsResolver.Status { .found(lyrics, source: "lrclib") }

    @Test func showsCurrentLineAndTrackInfoWhilePlaying() {
        let content = barContent(state: state(), status: found, lineIndex: 0, settings: makeSettings())
        #expect(content == BarContent(lyric: "first", trackInfo: "Song – Artist"))
    }

    @Test func keepsCurrentLineWhilePaused() {
        let content = barContent(state: state(playing: false), status: found, lineIndex: 2, settings: makeSettings())
        #expect(content == BarContent(lyric: "third", trackInfo: "Song – Artist"))
    }

    @Test func hidesLyricForEmptyLine() {
        let content = barContent(state: state(), status: found, lineIndex: 1, settings: makeSettings())
        #expect(content == BarContent(lyric: nil, trackInfo: "Song – Artist"))
    }

    @Test func hidesLyricForWhitespaceOnlyLine() {
        let blank = SyncedLyrics(lines: [LyricLine(time: 0, text: "  ")])
        let content = barContent(
            state: state(), status: .found(blank, source: "lrclib"), lineIndex: 0, settings: makeSettings())
        #expect(content.lyric == nil)
    }

    @Test func hidesLyricBeforeFirstLine() {
        let content = barContent(state: state(), status: found, lineIndex: nil, settings: makeSettings())
        #expect(content == BarContent(lyric: nil, trackInfo: "Song – Artist"))
    }

    @Test func hidesLyricForOutOfRangeIndex() {
        let content = barContent(state: state(), status: found, lineIndex: 3, settings: makeSettings())
        #expect(content.lyric == nil)
    }

    @Test func hidesLyricUnlessFound() {
        let statuses: [LyricsResolver.Status] = [.idle, .loading, .notFound, .failed(StubError())]
        for status in statuses {
            let content = barContent(state: state(), status: status, lineIndex: 0, settings: makeSettings())
            #expect(content == BarContent(lyric: nil, trackInfo: "Song – Artist"))
        }
    }

    @Test func emptyWithoutTrack() {
        let content = barContent(
            state: .empty(at: syncedAt), status: found, lineIndex: 0, settings: makeSettings())
        #expect(content == BarContent())
    }

    @Test func hidesTrackInfoWhenDisabled() {
        let content = barContent(
            state: state(), status: found, lineIndex: 0, settings: makeSettings(showTrackInfo: false))
        #expect(content == BarContent(lyric: "first", trackInfo: nil))
    }

    @Test func trackInfoOmitsSeparatorWithoutArtist() {
        let noArtist = TrackInfo(id: "spotify:episode:1", title: "Episode", artist: "", duration: 100)
        #expect(noArtist.displayText == "Episode")
    }

    @Test func lineIndexFollowsInterpolatedPosition() {
        let playing = state(position: 5)
        #expect(currentLineIndex(state: playing, status: found, now: syncedAt) == nil)
        #expect(currentLineIndex(state: playing, status: found, now: syncedAt.addingTimeInterval(5)) == 0)
        #expect(currentLineIndex(state: playing, status: found, now: syncedAt.addingTimeInterval(26)) == 2)
    }

    @Test func lineIndexStaysWhilePaused() {
        let paused = state(playing: false, position: 12)
        #expect(currentLineIndex(state: paused, status: found, now: syncedAt.addingTimeInterval(60)) == 0)
    }

    @Test func lineIndexIsNilWithoutLyricsOrTrack() {
        #expect(currentLineIndex(state: state(position: 15), status: .loading, now: syncedAt) == nil)
        #expect(currentLineIndex(state: .empty(at: syncedAt), status: found, now: syncedAt) == nil)
    }
}
