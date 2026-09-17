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

    @Test func clicksFallThrough() {
        let view = LyricsBarView(frame: NSRect(x: 0, y: 0, width: 0, height: 22))
        view.update(content: BarContent(lyric: "la la", trackInfo: "Song – Artist"), maxWidth: 300)
        view.layoutSubtreeIfNeeded()
        #expect(view.hitTest(NSPoint(x: 10, y: 10)) == nil)
    }
}
