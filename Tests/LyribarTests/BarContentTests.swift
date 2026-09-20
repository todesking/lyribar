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

    private func makeSettings(
        showTrackInfo: Bool = true, mode: LyricsDisplayMode = .currentLine
    ) -> Settings {
        let suite = "LyribarTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let settings = Settings(defaults: defaults)
        settings.showTrackInfo = showTrackInfo
        settings.lyricsDisplayMode = mode
        defaults.removePersistentDomain(forName: suite)
        return settings
    }

    private func state(playing: Bool = true, position: TimeInterval = 0) -> PlaybackState {
        PlaybackState(track: track, isPlaying: playing, syncedPosition: position, syncedAt: syncedAt)
    }

    private var found: LyricsResolver.Status { .found(lyrics, source: "lrclib") }

    private let first = CurrentLineContent(text: "first", start: 10, end: 20)
    private let third = CurrentLineContent(text: "third", start: 30, end: 200)

    @Test func showsCurrentLineAndTrackInfoWhilePlaying() {
        let content = barContent(state: state(), status: found, lineIndex: 0, settings: makeSettings())
        #expect(content == BarContent(lyric: first, trackInfo: "Song – Artist", reservesLyricWidth: true))
    }

    @Test func keepsCurrentLineWhilePaused() {
        let content = barContent(state: state(playing: false), status: found, lineIndex: 2, settings: makeSettings())
        #expect(content == BarContent(lyric: third, trackInfo: "Song – Artist", reservesLyricWidth: true))
    }

    // An interlude ends the line like any other line does.
    @Test func lineEndsWhereTheNextLineStarts() {
        let content = barContent(state: state(), status: found, lineIndex: 0, settings: makeSettings())
        #expect(content.lyric?.start == 10)
        #expect(content.lyric?.end == 20)
    }

    @Test func lastLineEndsWithTheTrack() {
        let content = barContent(state: state(), status: found, lineIndex: 2, settings: makeSettings())
        #expect(content.lyric?.start == 30)
        #expect(content.lyric?.end == track.duration)
    }

    // The marquee follows the stretch, so a repeated line is new content.
    @Test func sameTextInAnotherStretchIsDifferentContent() {
        let repeated = SyncedLyrics(lines: [LyricLine(time: 10, text: "la"), LyricLine(time: 20, text: "la")])
        let contents = [0, 1].map {
            barContent(
                state: state(), status: .found(repeated, source: "lrclib"), lineIndex: $0, settings: makeSettings())
        }
        #expect(contents[0].lyric?.text == contents[1].lyric?.text)
        #expect(contents[0] != contents[1])
    }

    @Test func hidesLyricForEmptyLine() {
        let content = barContent(state: state(), status: found, lineIndex: 1, settings: makeSettings())
        #expect(content == BarContent(lyric: nil, trackInfo: "Song – Artist", reservesLyricWidth: true))
    }

    @Test func hidesLyricForWhitespaceOnlyLine() {
        let blank = SyncedLyrics(lines: [LyricLine(time: 0, text: "  ")])
        let content = barContent(
            state: state(), status: .found(blank, source: "lrclib"), lineIndex: 0, settings: makeSettings())
        #expect(content.lyric == nil)
    }

    @Test func hidesLyricBeforeFirstLine() {
        let content = barContent(state: state(), status: found, lineIndex: nil, settings: makeSettings())
        #expect(content == BarContent(lyric: nil, trackInfo: "Song – Artist", reservesLyricWidth: true))
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

    // The width stays reserved for every line of a track whose lyrics were found.
    @Test func reservesLyricWidthWhileFound() {
        for lineIndex in [nil, 0, 1, 2, 3] as [Int?] {
            let content = barContent(state: state(), status: found, lineIndex: lineIndex, settings: makeSettings())
            #expect(content.reservesLyricWidth)
        }
    }

    @Test func doesNotReserveLyricWidthUnlessFound() {
        let statuses: [LyricsResolver.Status] = [.idle, .loading, .notFound, .failed(StubError())]
        for status in statuses {
            let content = barContent(state: state(), status: status, lineIndex: 0, settings: makeSettings())
            #expect(!content.reservesLyricWidth)
        }
    }

    @Test func scrollingModeHandsOverTheWholeLyrics() {
        for lineIndex in [nil, 0, 1, 2] as [Int?] {
            let content = barContent(
                state: state(), status: found, lineIndex: lineIndex, settings: makeSettings(mode: .scrolling))
            #expect(content.ribbon == RibbonContent(lyrics: lyrics, currentIndex: lineIndex))
            #expect(content.lyric == nil)
            #expect(content.trackInfo == "Song – Artist")
            #expect(content.reservesLyricWidth)
        }
    }

    @Test func scrollingModeKeepsTheRibbonWhilePaused() {
        let content = barContent(
            state: state(playing: false), status: found, lineIndex: 2, settings: makeSettings(mode: .scrolling))
        #expect(content.ribbon == RibbonContent(lyrics: lyrics, currentIndex: 2))
    }

    @Test func currentLineModeHasNoRibbon() {
        let content = barContent(
            state: state(), status: found, lineIndex: 0, settings: makeSettings(mode: .currentLine))
        #expect(content.lyric == first)
        #expect(content.ribbon == nil)
    }

    @Test func noRibbonUnlessFound() {
        let statuses: [LyricsResolver.Status] = [.idle, .loading, .notFound, .failed(StubError())]
        for status in statuses {
            let content = barContent(
                state: state(), status: status, lineIndex: 0, settings: makeSettings(mode: .scrolling))
            #expect(content == BarContent(trackInfo: "Song – Artist"))
        }
    }

    @Test func noRibbonWithoutTrack() {
        let content = barContent(
            state: .empty(at: syncedAt), status: found, lineIndex: 0, settings: makeSettings(mode: .scrolling))
        #expect(content == BarContent())
    }

    @Test func emptyWithoutTrack() {
        let content = barContent(
            state: .empty(at: syncedAt), status: found, lineIndex: 0, settings: makeSettings())
        #expect(content == BarContent())
        #expect(!content.reservesLyricWidth)
    }

    @Test func hidesTrackInfoWhenDisabled() {
        let content = barContent(
            state: state(), status: found, lineIndex: 0, settings: makeSettings(showTrackInfo: false))
        #expect(content == BarContent(lyric: first, trackInfo: nil, reservesLyricWidth: true))
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
