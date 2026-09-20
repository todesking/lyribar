import CoreGraphics
import Testing
@testable import Lyribar

struct MarqueeAnimationTests {
    // 60pt overflow over a line from 10 s to 14 s.
    private func offset(_ position: Double) -> CGFloat {
        MarqueeAnimation.offset(position: position, start: 10, end: 14, textWidth: 160, availableWidth: 100)
    }

    @Test func staysStillWhenTextFits() {
        for position in [5, 12, 20] as [Double] {
            #expect(
                MarqueeAnimation.offset(position: position, start: 10, end: 14, textWidth: 80, availableWidth: 100)
                    == 0)
            #expect(
                MarqueeAnimation.offset(position: position, start: 10, end: 14, textWidth: 100, availableWidth: 100)
                    == 0)
        }
    }

    @Test func startsAtTheLeftEdge() {
        #expect(offset(0) == 0)
        #expect(offset(9.9) == 0)
        #expect(offset(10) == 0)
    }

    @Test func endsWithTheEndOfTheTextAtTheRightEdge() {
        #expect(offset(14) == 60)
        #expect(offset(15) == 60)
        #expect(offset(1_000) == 60)
    }

    @Test func restsAtBothEndsOfTheLine() {
        #expect(offset(10.15) == 0)
        #expect(offset(10.3) == 0)
        #expect(offset(10.4) > 0)
        #expect(offset(13.6) < 60)
        #expect(offset(13.7) == 60)
        #expect(offset(13.85) == 60)
    }

    // Over the 3.4 s between the rests.
    @Test func scrollsAtASteadyPaceInBetween() {
        #expect(abs(offset(11.15) - 15) < 0.001)
        #expect(abs(offset(12) - 30) < 0.001)
        #expect(abs(offset(12.85) - 45) < 0.001)
    }

    @Test func scrollStretchLeavesTheRestsOut() throws {
        let stretch = try #require(MarqueeAnimation.scrollStretch(start: 10, end: 14))
        #expect(abs(stretch.lowerBound - 10.3) < 0.001)
        #expect(abs(stretch.upperBound - 13.7) < 0.001)
        #expect(MarqueeAnimation.scrollStretch(start: 10, end: 10) == nil)
        #expect(MarqueeAnimation.scrollStretch(start: 10, end: 4) == nil)
    }

    // A line too short for both rests scrolls for half of its length.
    @Test func shortLineShortensTheRests() throws {
        let stretch = try #require(MarqueeAnimation.scrollStretch(start: 10, end: 10.2))
        #expect(abs(stretch.lowerBound - 10.05) < 0.001)
        #expect(abs(stretch.upperBound - 10.15) < 0.001)
        let middle = MarqueeAnimation.offset(
            position: 10.1, start: 10, end: 10.2, textWidth: 160, availableWidth: 100)
        #expect(abs(middle - 30) < 0.001)
    }

    @Test func staysStillWhenTheLineHasNoLength() {
        for position in [5, 10, 12, 20] as [Double] {
            #expect(
                MarqueeAnimation.offset(position: position, start: 10, end: 10, textWidth: 160, availableWidth: 100)
                    == 0)
            #expect(
                MarqueeAnimation.offset(position: position, start: 10, end: 4, textWidth: 160, availableWidth: 100)
                    == 0)
        }
    }

    @Test func neverScrollsPastTheEnds() {
        for step in 0..<400 {
            let value = offset(Double(step) * 0.05)
            #expect(value >= 0 && value <= 60)
        }
    }
}
