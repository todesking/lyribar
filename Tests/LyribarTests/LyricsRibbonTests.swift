import CoreGraphics
import Foundation
import Testing

@testable import Lyribar

struct LyricsRibbonTests {
    private let gap = LyricsRibbon.gap

    private func ribbon(_ entries: [(time: TimeInterval, width: CGFloat)]) -> LyricsRibbon {
        LyricsRibbon(
            lines: entries.map { LyricLine(time: $0.time, text: $0.width == 0 ? "" : "line") },
            widths: entries.map(\.width))
    }

    @Test func originsAccumulateWidthsAndGaps() {
        let ribbon = ribbon([(10, 100), (20, 50), (30, 70)])
        #expect(ribbon.origins == [0, 100 + gap, 150 + gap * 2, 220 + gap * 3])
    }

    @Test func emptyLineAdvancesByTheGapOnly() {
        let ribbon = ribbon([(10, 100), (20, 0), (30, 70)])
        #expect(ribbon.origins == [0, 100 + gap, 100 + gap * 2, 170 + gap * 3])
    }

    @Test func lineStartsAtTheAnchorAtItsTime() {
        let ribbon = ribbon([(10, 100), (20, 0), (30, 70)])
        for (index, line) in ribbon.lines.enumerated() {
            #expect(ribbon.offset(at: line.time, duration: 200) == ribbon.origins[index])
        }
    }

    @Test func interpolatesBetweenLines() {
        let ribbon = ribbon([(10, 100), (20, 50), (30, 70)])
        #expect(ribbon.offset(at: 15, duration: 200) == (ribbon.origins[0] + ribbon.origins[1]) / 2)
        #expect(ribbon.offset(at: 25, duration: 200) == (ribbon.origins[1] + ribbon.origins[2]) / 2)
    }

    @Test func linesSharingATimeJumpToTheLaterOne() {
        let ribbon = ribbon([(10, 100), (20, 50), (20, 60), (30, 70)])
        let offset = ribbon.offset(at: 20, duration: 200)
        #expect(offset.isFinite)
        #expect(offset == ribbon.origins[2])

        let before = ribbon.offset(at: 19.999, duration: 200)
        #expect(before.isFinite)
        #expect(before < ribbon.origins[1])
        #expect(ribbon.offset(at: 25, duration: 200) == (ribbon.origins[2] + ribbon.origins[3]) / 2)
    }

    @Test func everyLineSharingOneTimeStaysFinite() {
        let ribbon = ribbon([(0, 100), (0, 50)])
        #expect(ribbon.offset(at: 0, duration: 0) == ribbon.origins[1])
        #expect(ribbon.offset(at: 5, duration: 0).isFinite)
    }

    @Test func leadsInFromOneGapBeforeTheFirstLine() {
        let ribbon = ribbon([(10, 100), (20, 50)])
        #expect(ribbon.offset(at: 0, duration: 200) == -gap)
        #expect(ribbon.offset(at: 5, duration: 200) == -gap / 2)
        #expect(ribbon.offset(at: -3, duration: 200) == -gap)
    }

    @Test func noLeadInWhenTheFirstLineStartsAtZero() {
        let ribbon = ribbon([(0, 100), (20, 50)])
        #expect(ribbon.offset(at: 0, duration: 200) == 0)
        #expect(ribbon.offset(at: -3, duration: 200) == 0)
        #expect(ribbon.offset(at: 10, duration: 200) == ribbon.origins[1] / 2)
    }

    @Test func runsOutToTheEndOfTheRibbonAtTheDuration() {
        let ribbon = ribbon([(10, 100), (20, 50)])
        #expect(ribbon.offset(at: 110, duration: 200) == (ribbon.origins[1] + ribbon.origins[2]) / 2)
        #expect(ribbon.offset(at: 200, duration: 200) == ribbon.origins[2])
        #expect(ribbon.offset(at: 500, duration: 200) == ribbon.origins[2])
    }

    @Test func staysOnTheLastLineWhenTheDurationIsNotAfterIt() {
        let ribbon = ribbon([(10, 100), (20, 50)])
        #expect(ribbon.offset(at: 20, duration: 20) == ribbon.origins[1])
        #expect(ribbon.offset(at: 99, duration: 15) == ribbon.origins[1])
    }

    @Test func emptyLyricsHaveNoOffset() {
        let ribbon = ribbon([])
        #expect(ribbon.origins == [0])
        #expect(ribbon.offset(at: 10, duration: 200) == 0)
    }
}
