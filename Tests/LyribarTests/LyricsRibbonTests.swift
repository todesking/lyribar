import CoreGraphics
import Foundation
import Testing

@testable import Lyribar

struct LyricsRibbonTests {
    private let gap = LyricsRibbon.gap
    /// Uneven lines, an interlude that only advances by the gap, and two lines sharing a time.
    private let uneven: [(time: TimeInterval, width: CGFloat)] = [
        (3, 40), (7.5, 220), (9, 0), (26, 90), (26, 130), (31.25, 60),
    ]
    private let unevenDuration: TimeInterval = 48

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
        let cases: [([(time: TimeInterval, width: CGFloat)], TimeInterval)] = [
            ([(10, 100), (20, 0), (30, 70)], 200), (uneven, unevenDuration),
        ]
        for (entries, duration) in cases {
            let ribbon = ribbon(entries)
            for (index, line) in ribbon.lines.enumerated() {
                // Of lines sharing a time, only the later one is at the anchor at that time.
                guard index == ribbon.lines.count - 1 || ribbon.lines[index + 1].time != line.time else { continue }
                #expect(ribbon.offset(at: line.time, duration: duration) == ribbon.origins[index])
            }
        }
    }

    // The ribbon starts and ends a line at the speed it passes the line boundary with, so it leaves
    // the first node and reaches the last one at a standstill.
    @Test func easesOutOfTheFirstLineAndIntoTheLastOne() {
        // Nodes (0, 0), (10, 100), (20, 200): both segments run at 100 pt / 10 s, so the boundary
        // speed is the same 10 pt/s and the halfway points are 12.5 pt off the straight line.
        let even = ribbon([(0, 100 - gap), (10, 100 - gap)])
        #expect(even.origins == [0, 100, 200])
        #expect(even.offset(at: 5, duration: 20) == 37.5)
        #expect(even.offset(at: 15, duration: 20) == 162.5)

        // Nodes (0, 0), (10, 100), (20, 400): 10 pt/s meets 30 pt/s, so the boundary speed is the
        // harmonic mean 15 pt/s and the slow segment gets the larger share of the easing.
        let faster = ribbon([(0, 100 - gap), (10, 300 - gap)])
        #expect(faster.origins == [0, 100, 400])
        #expect(faster.offset(at: 5, duration: 20) == 31.25)
        #expect(faster.offset(at: 15, duration: 20) == 268.75)
    }

    @Test func linesSharingATimeJumpToTheLaterOne() {
        let ribbon = ribbon([(10, 100), (20, 50), (20, 60), (30, 70)])
        let offset = ribbon.offset(at: 20, duration: 200)
        #expect(offset.isFinite)
        #expect(offset == ribbon.origins[2])

        let before = ribbon.offset(at: 19.999, duration: 200)
        #expect(before.isFinite)
        #expect(before < ribbon.origins[1])

        let after = ribbon.offset(at: 25, duration: 200)
        #expect(after > ribbon.origins[2])
        #expect(after < ribbon.origins[3])
    }

    @Test func everyLineSharingOneTimeStaysFinite() {
        let ribbon = ribbon([(0, 100), (0, 50)])
        #expect(ribbon.offset(at: 0, duration: 0) == ribbon.origins[1])
        #expect(ribbon.offset(at: 5, duration: 0).isFinite)
    }

    @Test func leadsInFromOneGapBeforeTheFirstLine() {
        let ribbon = ribbon([(10, 100), (20, 50)])
        #expect(ribbon.offset(at: 0, duration: 200) == -gap)
        #expect(ribbon.offset(at: -3, duration: 200) == -gap)
        // Starting from a standstill, the lead-in is behind the straight line at its halfway point.
        let halfway = ribbon.offset(at: 5, duration: 200)
        #expect(halfway > -gap)
        #expect(halfway < -gap / 2)
    }

    @Test func noLeadInWhenTheFirstLineStartsAtZero() {
        let ribbon = ribbon([(0, 100), (20, 50)])
        #expect(ribbon.offset(at: 0, duration: 200) == 0)
        #expect(ribbon.offset(at: -3, duration: 200) == 0)
        let halfway = ribbon.offset(at: 10, duration: 200)
        #expect(halfway > 0)
        #expect(halfway < ribbon.origins[1] / 2)
    }

    @Test func runsOutToTheEndOfTheRibbonAtTheDuration() {
        let ribbon = ribbon([(10, 100), (20, 50)])
        let halfway = ribbon.offset(at: 110, duration: 200)
        #expect(halfway > ribbon.origins[1])
        #expect(halfway < ribbon.origins[2])
        #expect(ribbon.offset(at: 200, duration: 200) == ribbon.origins[2])
        #expect(ribbon.offset(at: 500, duration: 200) == ribbon.origins[2])
    }

    @Test func staysOnTheLastLineWhenTheDurationIsNotAfterIt() {
        let ribbon = ribbon([(10, 100), (20, 50)])
        #expect(ribbon.offset(at: 20, duration: 20) == ribbon.origins[1])
        #expect(ribbon.offset(at: 99, duration: 15) == ribbon.origins[1])
    }

    @Test func theScrollNeverGoesBackwards() {
        let ribbon = ribbon(uneven)
        let curve = ribbon.curve(duration: unevenDuration)
        // A segment stays monotone as long as both its slopes are within 0…3.
        #expect(curve.slopes.allSatisfy { $0.start >= 0 && $0.start <= 2 && $0.end >= 0 && $0.end <= 2 })

        var previous = -CGFloat.infinity
        var wentBack: TimeInterval?
        for step in 0...Int((unevenDuration + 2) * 100) {
            let position = TimeInterval(step) / 100 - 1
            let x = ribbon.offset(at: position, duration: unevenDuration)
            if x < previous, wentBack == nil {
                wentBack = position
            }
            previous = x
        }
        #expect(wentBack == nil)
    }

    @Test func theSpeedIsTheSameOnBothSidesOfALineBoundary() {
        let ribbon = ribbon(uneven)
        let curve = ribbon.curve(duration: unevenDuration)
        let step = 0.000_01

        func offset(_ position: TimeInterval) -> CGFloat {
            ribbon.offset(at: position, duration: unevenDuration)
        }
        // A secant just short of the node: at the node itself the ribbon may jump to a later line.
        func speedBefore(_ time: TimeInterval) -> CGFloat {
            (offset(time - step) - offset(time - 2 * step)) / CGFloat(step)
        }
        func speedAfter(_ time: TimeInterval) -> CGFloat {
            (offset(time + 2 * step) - offset(time + step)) / CGFloat(step)
        }
        func averageSpeed(_ segment: Int) -> CGFloat? {
            let span = curve.nodes[segment + 1].time - curve.nodes[segment].time
            guard span > 0 else { return nil }
            return (curve.nodes[segment + 1].x - curve.nodes[segment].x) / CGFloat(span)
        }

        for index in 1..<curve.nodes.count - 1 {
            let time = curve.nodes[index].time
            // Nodes sharing a time are one boundary; it is measured at the later of them.
            guard curve.nodes[index + 1].time != time else { continue }
            var before: CGFloat?
            for segment in (0..<index).reversed() where before == nil {
                before = averageSpeed(segment)
            }
            var after: CGFloat?
            for segment in index..<curve.slopes.count where after == nil {
                after = averageSpeed(segment)
            }
            let expected = 2 * (before ?? 0) * (after ?? 0) / ((before ?? 0) + (after ?? 0))
            #expect(expected > 0)
            #expect(abs(speedBefore(time) - expected) < 0.01 * expected + 0.01)
            #expect(abs(speedAfter(time) - expected) < 0.01 * expected + 0.01)
        }

        // The track starts and ends at a standstill.
        #expect(abs(speedAfter(curve.nodes[0].time)) < 0.01)
        #expect(abs(speedBefore(unevenDuration)) < 0.01)
    }

    // The scroll animation plays the nodes with one cubic Bezier timing function per segment, so the
    // offset must be that same Bezier: solved for u at the wanted x, as Core Animation does.
    @Test func theCurveIsTheBezierOfItsSlopes() {
        func axis(_ u: CGFloat, _ first: CGFloat, _ second: CGFloat) -> CGFloat {
            let rest = 1 - u
            return 3 * rest * rest * u * first + 3 * rest * u * u * second + u * u * u
        }
        func bezier(_ time: CGFloat, _ first: CGFloat, _ second: CGFloat) -> CGFloat {
            var low: CGFloat = 0
            var high: CGFloat = 1
            for _ in 0..<80 {
                let middle = (low + high) / 2
                if axis(middle, 1.0 / 3, 2.0 / 3) < time {
                    low = middle
                } else {
                    high = middle
                }
            }
            return axis((low + high) / 2, first, second)
        }
        func played(_ curve: LyricsRibbon.Curve, at position: TimeInterval) -> CGFloat {
            guard let first = curve.nodes.first, let last = curve.nodes.last else { return 0 }
            if position >= last.time { return last.x }
            if position < first.time { return first.x }
            // Of nodes sharing a time, the later one.
            let next = curve.nodes.firstIndex { $0.time > position }!
            let (from, to) = (curve.nodes[next - 1], curve.nodes[next])
            let slopes = curve.slopes[next - 1]
            let time = CGFloat((position - from.time) / (to.time - from.time))
            return from.x + (to.x - from.x) * bezier(time, slopes.start / 3, 1 - slopes.end / 3)
        }

        let cases: [(LyricsRibbon, TimeInterval)] = [
            (ribbon(uneven), unevenDuration),
            (ribbon([(10, 100), (20, 0), (30, 70)]), 200),
            (ribbon([(0, 100), (20, 50)]), 200),
            (ribbon([(10, 100), (20, 50), (20, 60), (30, 70)]), 200),
            (ribbon([(10, 100), (20, 50)]), 15),
        ]
        for (index, (ribbon, duration)) in cases.enumerated() {
            let curve = ribbon.curve(duration: duration)
            #expect(curve.nodes.first?.time == 0)
            #expect(curve.nodes.map(\.time) == curve.nodes.map(\.time).sorted())
            #expect(curve.slopes.count == curve.nodes.count - 1)
            var worst: CGFloat = 0
            for step in 0...Int((duration + 2) * 20) {
                let position = TimeInterval(step) / 20 - 1
                worst = max(worst, abs(played(curve, at: position) - ribbon.offset(at: position, duration: duration)))
            }
            #expect(worst < 0.0001, "case \(index)")
        }
        #expect(ribbon([]).curve(duration: 200).nodes.isEmpty)
    }

    @Test func theBoundarySpeedIsTheHarmonicMeanOfTheNeighbours() {
        #expect(LyricsRibbon.Curve.boundarySpeed(before: 10, after: 30) == 15)
        #expect(LyricsRibbon.Curve.boundarySpeed(before: 8, after: 8) == 8)
        // At most twice the slower side, which is what keeps the slow segment monotone.
        #expect(LyricsRibbon.Curve.boundarySpeed(before: 1, after: 1_000) < 2)
        // Nil stands for no segment to take a speed from: the ends of the track.
        #expect(LyricsRibbon.Curve.boundarySpeed(before: nil, after: 30) == 0)
        #expect(LyricsRibbon.Curve.boundarySpeed(before: 10, after: nil) == 0)
        #expect(LyricsRibbon.Curve.boundarySpeed(before: 0, after: 30) == 0)
    }

    @Test func emptyLyricsHaveNoOffset() {
        let ribbon = ribbon([])
        #expect(ribbon.origins == [0])
        #expect(ribbon.offset(at: 10, duration: 200) == 0)
    }

    @Test func viewportIsTheStretchAroundTheOffset() {
        let ribbon = ribbon([(10, 100), (20, 50)])
        // The anchor sits in the middle, so the offset does too.
        #expect(ribbon.viewport(offset: 222, width: 200) == 122...322)
        #expect(ribbon.viewport(offset: 0, width: 200) == -100...100)
        #expect(ribbon.viewport(offset: 50, width: 0) == 50...50)
    }

    @Test func linesInAStretchAreTheOnesIntersectingIt() {
        // Lines at 0..<100, 124..<174, an interlude at 198, 222..<292; the ribbon ends at 316.
        let ribbon = ribbon([(10, 100), (20, 50), (25, 0), (30, 70)])
        #expect(ribbon.lines(in: -100...100) == [0])
        // The interlude is never listed, not even when the stretch holds nothing else.
        #expect(ribbon.lines(in: 122...322) == [1, 3])
        #expect(ribbon.lines(in: 180...210) == [])
        #expect(ribbon.lines(in: -1_000...1_000) == [0, 1, 3])
        // A stretch inside one line, down to a single point.
        #expect(ribbon.lines(in: 130...140) == [1])
        #expect(ribbon.lines(in: 130...130) == [1])
    }

    @Test func linesTouchingTheEndsOfAStretchAreNotInIt() {
        let ribbon = ribbon([(10, 100), (20, 50), (25, 0), (30, 70)])
        // The first line ends at 100 and the second one starts at 124.
        #expect(ribbon.lines(in: 100...124) == [])
        #expect(ribbon.lines(in: 99.5...124.5) == [0, 1])
        #expect(ribbon.lines(in: 100...222) == [1])
        #expect(ribbon.lines(in: 174...222.5) == [3])
        // A point on the start of a line is not inside it.
        #expect(ribbon.lines(in: 124...124) == [])
    }

    @Test func noLinesOutsideTheRibbonOrWithoutLyrics() {
        let ribbon = ribbon([(10, 100), (20, 50), (25, 0), (30, 70)])
        #expect(ribbon.lines(in: -500...0) == [])
        #expect(ribbon.lines(in: -500...0.5) == [0])
        #expect(ribbon.lines(in: 292...900) == [])
        #expect(ribbon.lines(in: 291.5...900) == [3])

        let empty = LyricsRibbon(lines: [], widths: [])
        #expect(empty.lines(in: -1_000...1_000) == [])
        let interludes = self.ribbon([(10, 0), (20, 0)])
        #expect(interludes.lines(in: -1_000...1_000) == [])
    }

    // The bisection has to agree with looking at every line.
    @Test func linesInAStretchMatchABruteForceScan() {
        let ribbon = ribbon((0..<40).map { (TimeInterval($0), CGFloat([0, 35, 120, 60][$0 % 4])) })
        for start in stride(from: CGFloat(-60), through: ribbon.origins[40] + 60, by: 17) {
            for length in [CGFloat(0), 1, 50, 400] {
                let expected = ribbon.lines.indices.filter {
                    ribbon.widths[$0] > 0 && ribbon.origins[$0] < start + length
                        && ribbon.origins[$0] + ribbon.widths[$0] > start
                }
                #expect(ribbon.lines(in: start...(start + length)) == expected)
            }
        }
    }
}
