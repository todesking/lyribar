import AppKit
import Testing

@testable import Lyribar

@MainActor
struct LyricsRibbonViewTests {
    private let track = TrackInfo(id: "spotify:track:abc", title: "Song", artist: "Artist", duration: 200)
    private let syncedAt = Date(timeIntervalSince1970: 1_000)
    private let lyrics = SyncedLyrics(lines: [
        LyricLine(time: 10, text: "first"),
        LyricLine(time: 20, text: "  "),
        LyricLine(time: 30, text: "third"),
    ])

    private func state(playing: Bool, position: TimeInterval = 0) -> PlaybackState {
        PlaybackState(track: track, isPlaying: playing, syncedPosition: position, syncedAt: syncedAt)
    }

    @Test func measuresTheLinesOfTheLyrics() throws {
        let view = LyricsRibbonView(frame: NSRect(x: 0, y: 0, width: 200, height: 22))
        view.lyrics = lyrics

        let ribbon = try #require(view.ribbon)
        #expect(ribbon.lines == lyrics.lines)
        #expect(ribbon.widths[0] == MarqueeTextView.width(of: "first"))
        #expect(ribbon.widths[1] == 0)
        #expect(ribbon.widths[2] == MarqueeTextView.width(of: "third"))

        view.lyrics = nil
        #expect(view.ribbon == nil)
    }

    @Test func offsetFollowsThePlaybackPosition() throws {
        let view = LyricsRibbonView(frame: NSRect(x: 0, y: 0, width: 200, height: 22))
        view.lyrics = lyrics
        view.playback = state(playing: true, position: 5)
        let ribbon = try #require(view.ribbon)

        #expect(view.offset(at: syncedAt.addingTimeInterval(5)) == ribbon.origins[0])
        #expect(view.offset(at: syncedAt.addingTimeInterval(25)) == ribbon.origins[2])
        // The track duration ends the ribbon.
        #expect(view.offset(at: syncedAt.addingTimeInterval(500)) == ribbon.origins[3])
    }

    @Test func offsetStaysWhilePaused() throws {
        let view = LyricsRibbonView(frame: NSRect(x: 0, y: 0, width: 200, height: 22))
        view.lyrics = lyrics
        view.playback = state(playing: false, position: 30)
        let ribbon = try #require(view.ribbon)

        #expect(view.offset(at: syncedAt) == ribbon.origins[2])
        #expect(view.offset(at: syncedAt.addingTimeInterval(60)) == ribbon.origins[2])
    }

    @Test func animatesOnlyWhilePlayingWithLyrics() {
        let view = LyricsRibbonView(frame: NSRect(x: 0, y: 0, width: 200, height: 22))
        #expect(!view.wantsAnimation)

        view.playback = state(playing: true)
        #expect(!view.wantsAnimation)

        view.lyrics = lyrics
        #expect(view.wantsAnimation)

        view.playback = state(playing: false)
        #expect(!view.wantsAnimation)

        view.playback = state(playing: true)
        view.lyrics = nil
        #expect(!view.wantsAnimation)
    }

    // The window is never shown; it only gives the view a window to be in.
    @Test func timerRunsOnlyInsideAWindow() {
        let view = LyricsRibbonView(frame: NSRect(x: 0, y: 0, width: 200, height: 22))
        view.lyrics = lyrics
        view.playback = state(playing: true)
        #expect(!view.isAnimating)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 22), styleMask: [.borderless],
            backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        window.contentView?.addSubview(view)
        #expect(view.isAnimating)

        view.playback = state(playing: false)
        #expect(!view.isAnimating)

        view.playback = state(playing: true)
        #expect(view.isAnimating)

        view.removeFromSuperview()
        #expect(!view.isAnimating)
    }

    @Test func clicksFallThrough() {
        let view = LyricsRibbonView(frame: NSRect(x: 0, y: 0, width: 200, height: 22))
        #expect(view.hitTest(NSPoint(x: 10, y: 10)) == nil)
        #expect(view.clipsToBounds)
    }
}
