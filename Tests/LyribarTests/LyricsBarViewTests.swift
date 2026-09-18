import AppKit
import Testing
@testable import Lyribar

@MainActor
struct LyricsBarViewTests {
    private let longText = String(repeating: "a very long line of lyrics ", count: 20)

    @Test func iconOnlyWithoutContent() {
        let view = LyricsBarView(frame: NSRect(x: 0, y: 0, width: 0, height: 22))
        #expect(view.preferredWidth == BarLayout.padding * 2 + LyricsBarView.iconWidth)
        #expect(view.frame.width == view.preferredWidth)
    }

    @Test func widthIsCappedAtMaxWidth() {
        let view = LyricsBarView(frame: NSRect(x: 0, y: 0, width: 0, height: 22))
        view.update(content: BarContent(lyric: longText, trackInfo: longText), maxWidth: 300)
        #expect(view.preferredWidth == 300)
        #expect(view.frame.width == 300)
    }

    @Test func shrinksForShortContent() {
        let view = LyricsBarView(frame: NSRect(x: 0, y: 0, width: 0, height: 22))
        view.update(content: BarContent(lyric: "la la", trackInfo: "Song – Artist"), maxWidth: 300)
        #expect(view.preferredWidth < 300)
        #expect(view.preferredWidth > BarLayout.padding * 2 + LyricsBarView.iconWidth)
    }

    @Test func keepsMaxWidthWhileTheLyricWidthIsReserved() {
        let view = LyricsBarView(frame: NSRect(x: 0, y: 0, width: 0, height: 22))
        var widths: [CGFloat] = []
        var lyricWidths: [CGFloat?] = []
        for lyric in [nil, "la la", longText] as [String?] {
            view.update(
                content: BarContent(lyric: lyric, trackInfo: "Song – Artist", reservesLyricWidth: true),
                maxWidth: 300)
            widths.append(view.preferredWidth)
            lyricWidths.append(view.layoutResult.lyric.map { $0.upperBound - $0.lowerBound })
            #expect(view.frame.width == 300)
        }
        #expect(widths == [300, 300, 300])
        #expect(lyricWidths[0] == lyricWidths[1])
        #expect(lyricWidths[1] == lyricWidths[2])
    }

    // Between lines the area stays, so the track info does not move either.
    @Test func reservedLyricAreaIsShownForAnEmptyLine() {
        let view = LyricsBarView(frame: NSRect(x: 0, y: 0, width: 0, height: 22))
        view.update(
            content: BarContent(lyric: nil, trackInfo: "Song – Artist", reservesLyricWidth: true), maxWidth: 300)
        #expect(view.layoutResult.lyric != nil)
    }

    private let lyrics = SyncedLyrics(lines: [
        LyricLine(time: 10, text: "first"),
        LyricLine(time: 20, text: ""),
        LyricLine(time: 30, text: "third"),
    ])

    private func lyricFrame(of view: LyricsBarView) throws -> NSRect {
        let range = try #require(view.layoutResult.lyric)
        return NSRect(x: range.lowerBound, y: 0, width: range.upperBound - range.lowerBound, height: 22)
    }

    @Test func ribbonTakesTheLyricAreaAndHidesTheMarquee() throws {
        let view = LyricsBarView(frame: NSRect(x: 0, y: 0, width: 0, height: 22))
        view.update(
            content: BarContent(
                ribbon: RibbonContent(lyrics: lyrics, currentIndex: 2), trackInfo: "Song – Artist",
                reservesLyricWidth: true),
            maxWidth: 300)
        view.layoutSubtreeIfNeeded()

        #expect(view.preferredWidth == 300)
        #expect(view.ribbonView.frame == (try lyricFrame(of: view)))
        #expect(!view.ribbonView.isHidden)
        #expect(view.marquee.isHidden)
        #expect(view.ribbonView.lyrics == lyrics)
        #expect(view.ribbonView.currentIndex == 2)
    }

    @Test func marqueeTakesTheLyricAreaInTheCurrentLineMode() throws {
        let view = LyricsBarView(frame: NSRect(x: 0, y: 0, width: 0, height: 22))
        view.update(
            content: BarContent(lyric: "la la", trackInfo: "Song – Artist", reservesLyricWidth: true),
            maxWidth: 300)
        view.layoutSubtreeIfNeeded()

        #expect(view.marquee.frame == (try lyricFrame(of: view)))
        #expect(!view.marquee.isHidden)
        #expect(view.ribbonView.isHidden)
        #expect(view.ribbonView.lyrics == nil)
    }

    // The lyric area is the same in both modes, so switching does not move anything else.
    @Test func lyricAreaIsTheSameInBothModes() {
        let view = LyricsBarView(frame: NSRect(x: 0, y: 0, width: 0, height: 22))
        view.update(
            content: BarContent(
                ribbon: RibbonContent(lyrics: lyrics, currentIndex: 0), trackInfo: "Song – Artist",
                reservesLyricWidth: true),
            maxWidth: 300)
        let scrolling = view.layoutResult

        view.update(
            content: BarContent(lyric: longText, trackInfo: "Song – Artist", reservesLyricWidth: true),
            maxWidth: 300)
        #expect(view.layoutResult == scrolling)
    }

    @Test func ribbonIsHiddenOnceTheLyricsAreGone() {
        let view = LyricsBarView(frame: NSRect(x: 0, y: 0, width: 0, height: 22))
        view.update(
            content: BarContent(
                ribbon: RibbonContent(lyrics: lyrics, currentIndex: 0), reservesLyricWidth: true),
            maxWidth: 300)
        view.layoutSubtreeIfNeeded()
        view.update(content: BarContent(trackInfo: "Song – Artist"), maxWidth: 300)
        view.layoutSubtreeIfNeeded()

        #expect(view.ribbonView.isHidden)
        #expect(view.ribbonView.lyrics == nil)
        #expect(!view.ribbonView.wantsAnimation)
    }

    @Test func playbackReachesTheRibbonView() {
        let view = LyricsBarView(frame: NSRect(x: 0, y: 0, width: 0, height: 22))
        let track = TrackInfo(id: "spotify:track:abc", title: "Song", artist: "Artist", duration: 200)
        let state = PlaybackState(
            track: track, isPlaying: true, syncedPosition: 12, syncedAt: Date(timeIntervalSince1970: 1_000))
        view.playback = state
        #expect(view.ribbonView.playback == state)
    }

    @Test func clicksFallThrough() {
        let view = LyricsBarView(frame: NSRect(x: 0, y: 0, width: 0, height: 22))
        view.update(content: BarContent(lyric: "la la", trackInfo: "Song – Artist"), maxWidth: 300)
        view.layoutSubtreeIfNeeded()
        #expect(view.hitTest(NSPoint(x: 10, y: 10)) == nil)
    }
}
