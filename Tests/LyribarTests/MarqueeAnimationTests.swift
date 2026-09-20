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

    @Test func scrollsAtASteadyPaceInBetween() {
        #expect(offset(11) == 15)
        #expect(offset(12) == 30)
        #expect(offset(13) == 45)
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
