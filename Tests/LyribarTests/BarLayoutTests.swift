import CoreGraphics
import Testing
@testable import Lyribar

struct BarLayoutTests {
    private let icon: CGFloat = 18

    private func width(_ range: ClosedRange<CGFloat>?) -> CGFloat? {
        range.map { $0.upperBound - $0.lowerBound }
    }

    @Test func iconOnly() {
        let layout = BarLayout.compute(lyricWidth: nil, trackInfoWidth: nil, iconWidth: icon, maxWidth: 300)
        #expect(layout.lyric == nil)
        #expect(layout.trackInfo == nil)
        #expect(layout.icon == 6...24)
        #expect(layout.totalWidth == 30)
    }

    @Test func shrinksToShortContent() {
        let layout = BarLayout.compute(lyricWidth: 50, trackInfoWidth: 80, iconWidth: icon, maxWidth: 300)
        #expect(layout.lyric == 6...56)
        #expect(layout.trackInfo == 64...144)
        #expect(layout.icon == 152...170)
        #expect(layout.totalWidth == 176)
    }

    @Test func longLyricIsCappedAtMaxWidth() {
        let layout = BarLayout.compute(lyricWidth: 1_000, trackInfoWidth: nil, iconWidth: icon, maxWidth: 300)
        #expect(width(layout.lyric) == 262)
        #expect(layout.totalWidth == 300)
    }

    @Test func longTrackInfoIsCappedAtMaxWidth() {
        let layout = BarLayout.compute(lyricWidth: nil, trackInfoWidth: 1_000, iconWidth: icon, maxWidth: 300)
        #expect(width(layout.trackInfo) == 262)
        #expect(layout.totalWidth == 300)
    }

    @Test func longLyricLeavesAShareToTrackInfo() {
        let layout = BarLayout.compute(lyricWidth: 400, trackInfoWidth: 150, iconWidth: icon, maxWidth: 300)
        #expect(width(layout.trackInfo) == 101)
        #expect(width(layout.lyric) == 153)
        #expect(layout.totalWidth == 300)
    }

    @Test func trackInfoTakesWhatAShortLyricLeaves() {
        let layout = BarLayout.compute(lyricWidth: 60, trackInfoWidth: 500, iconWidth: icon, maxWidth: 300)
        #expect(width(layout.lyric) == 60)
        #expect(width(layout.trackInfo) == 194)
        #expect(layout.totalWidth == 300)
    }

    @Test func neverExceedsMaxWidth() {
        for maxWidth in stride(from: CGFloat(30), through: 600, by: 7) {
            for lyric in [nil, 10, 120.5, 900] as [CGFloat?] {
                for track in [nil, 10, 120.5, 900] as [CGFloat?] {
                    let layout = BarLayout.compute(
                        lyricWidth: lyric, trackInfoWidth: track, iconWidth: icon, maxWidth: maxWidth)
                    #expect(layout.totalWidth <= maxWidth)
                    #expect(layout.icon.upperBound + BarLayout.padding == layout.totalWidth)
                }
            }
        }
    }

    @Test func keepsIconWhenMaxWidthIsTooSmall() {
        let layout = BarLayout.compute(lyricWidth: 100, trackInfoWidth: 100, iconWidth: icon, maxWidth: 10)
        #expect(layout.lyric == nil)
        #expect(layout.trackInfo == nil)
        #expect(layout.totalWidth == 30)
    }

    private func reserved(lyric: CGFloat?, track: CGFloat? = 150, maxWidth: CGFloat = 300) -> BarLayout {
        BarLayout.compute(
            lyricWidth: lyric, trackInfoWidth: track, iconWidth: icon, maxWidth: maxWidth,
            reservesLyricWidth: true)
    }

    @Test func reservedLayoutIsTheSameForEveryLine() {
        let layouts = ([nil, 10, 200, 2_000] as [CGFloat?]).map { reserved(lyric: $0) }
        for layout in layouts {
            #expect(layout.totalWidth == 300)
            #expect(layout == layouts[0])
        }
        #expect(width(layouts[0].lyric) == 153)
        #expect(width(layouts[0].trackInfo) == 101)
        #expect(layouts[0].icon.upperBound + BarLayout.padding == 300)
    }

    @Test func reservedLayoutWithoutTrackInfoGivesTheRestToTheLyric() {
        let layout = reserved(lyric: nil, track: nil)
        #expect(width(layout.lyric) == 262)
        #expect(layout.trackInfo == nil)
        #expect(layout.totalWidth == 300)
    }

    @Test func reservedLayoutTruncatesLongTrackInfoToItsShare() {
        let layout = reserved(lyric: 10, track: 1_000)
        #expect(width(layout.trackInfo) == 101)
        #expect(width(layout.lyric) == 153)
        #expect(layout.totalWidth == 300)
    }

    @Test func reservedLayoutKeepsTheWidthWhenNothingIsLeftForTheLyric() {
        let layout = reserved(lyric: 100, maxWidth: 35)
        #expect(layout.lyric == nil)
        #expect(layout.trackInfo == nil)
        #expect(layout.totalWidth == 35)
        #expect(layout.icon == 11...29)
    }

    @Test func reservedLayoutKeepsIconWhenMaxWidthIsTooSmall() {
        let layout = reserved(lyric: 100, maxWidth: 10)
        #expect(layout.lyric == nil)
        #expect(layout.trackInfo == nil)
        #expect(layout.totalWidth == 30)
    }

    @Test func reservedLayoutAlwaysFillsMaxWidth() {
        for maxWidth in stride(from: CGFloat(30), through: 600, by: 7) {
            for lyric in [nil, 10, 120.5, 900] as [CGFloat?] {
                for track in [nil, 10, 120.5, 900] as [CGFloat?] {
                    let layout = BarLayout.compute(
                        lyricWidth: lyric, trackInfoWidth: track, iconWidth: icon, maxWidth: maxWidth,
                        reservesLyricWidth: true)
                    #expect(layout.totalWidth == max(maxWidth, 30))
                    #expect(layout.icon.upperBound + BarLayout.padding == layout.totalWidth)
                    // The reserved layout must not depend on the current line.
                    #expect(
                        layout
                            == BarLayout.compute(
                                lyricWidth: nil, trackInfoWidth: track, iconWidth: icon, maxWidth: maxWidth,
                                reservesLyricWidth: true))
                }
            }
        }
    }
}
