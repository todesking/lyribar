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

    // The scroll animation plays the keyframes, so they must describe the same motion as `offset`.
    @Test func keyframesInterpolateToTheOffset() {
        func interpolate(_ keyframes: [(time: TimeInterval, x: CGFloat)], at position: TimeInterval) -> CGFloat {
            guard let first = keyframes.first, let last = keyframes.last else { return 0 }
            if position <= first.time { return first.x }
            if position >= last.time { return last.x }
            // Of keyframes sharing a time, the later one.
            let next = keyframes.firstIndex { $0.time > position }!
            let (from, to) = (keyframes[next - 1], keyframes[next])
            return from.x + (to.x - from.x) * CGFloat((position - from.time) / (to.time - from.time))
        }

        let cases: [(LyricsRibbon, TimeInterval)] = [
            (ribbon([(10, 100), (20, 0), (30, 70)]), 200),
            (ribbon([(0, 100), (20, 50)]), 200),
            (ribbon([(10, 100), (20, 50), (20, 60), (30, 70)]), 200),
            (ribbon([(10, 100), (20, 50)]), 15),
        ]
        for (ribbon, duration) in cases {
            let keyframes = ribbon.keyframes(duration: duration)
            #expect(keyframes.first?.time == 0)
            #expect(keyframes.map(\.time) == keyframes.map(\.time).sorted())
            for step in 0...120 {
                let position = TimeInterval(step) * 2
                let expected = ribbon.offset(at: position, duration: duration)
                #expect(abs(interpolate(keyframes, at: position) - expected) < 0.0001)
            }
        }
        #expect(ribbon([]).keyframes(duration: 200).isEmpty)
    }

    @Test func emptyLyricsHaveNoOffset() {
        let ribbon = ribbon([])
        #expect(ribbon.origins == [0])
        #expect(ribbon.offset(at: 10, duration: 200) == 0)
    }

    @Test func visibleLinesAreTheOnesIntersectingTheViewport() {
        // Origins: 0, 124, 198 (empty), 222, 316.
        let ribbon = ribbon([(10, 100), (20, 50), (25, 0), (30, 70)])
        // Anchor at 100: the first line starts there, the second one at 224, the last one at 322.
        let atFirst = ribbon.visibleLines(offset: 0, viewportWidth: 200)
        #expect(atFirst.map(\.index) == [0])
        #expect(atFirst.map(\.x) == [100])

        // The first line has scrolled out to the left; the empty line is never listed.
        let atLast = ribbon.visibleLines(offset: 222, viewportWidth: 200)
        #expect(atLast.map(\.index) == [1, 3])
        #expect(atLast.map(\.x) == [2, 100])
    }

    @Test func linesTouchingTheViewportEdgesAreNotVisible() {
        let ribbon = ribbon([(10, 100), (20, 50)])
        // The first line ends exactly at the left edge; the second one starts at 100 - 200 + 124 = 24.
        #expect(ribbon.visibleLines(offset: 200, viewportWidth: 200).map(\.index) == [1])
        // The second line starts exactly at the right edge: 100 + 124 - 24 = 200.
        #expect(ribbon.visibleLines(offset: 24, viewportWidth: 200).map(\.index) == [0])
    }
}
