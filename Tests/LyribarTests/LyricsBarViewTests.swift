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

    @Test func clicksFallThrough() {
        let view = LyricsBarView(frame: NSRect(x: 0, y: 0, width: 0, height: 22))
        view.update(content: BarContent(lyric: "la la", trackInfo: "Song – Artist"), maxWidth: 300)
        view.layoutSubtreeIfNeeded()
        #expect(view.hitTest(NSPoint(x: 10, y: 10)) == nil)
    }
}
