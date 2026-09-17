import CoreGraphics
import Testing
@testable import Lyribar

struct MarqueeAnimationTests {
    // 60pt overflow: 1s rest, 2s scroll, 1s rest.
    private func offset(_ elapsed: Double) -> CGFloat {
        MarqueeAnimation.offset(elapsed: elapsed, textWidth: 160, availableWidth: 100)
    }

    @Test func staysStillWhenTextFits() {
        #expect(MarqueeAnimation.offset(elapsed: 5, textWidth: 80, availableWidth: 100) == 0)
        #expect(MarqueeAnimation.offset(elapsed: 5, textWidth: 100, availableWidth: 100) == 0)
    }

    @Test func restsAtTheStart() {
        #expect(offset(0) == 0)
        #expect(offset(0.9) == 0)
    }

    @Test func scrollsAtThirtyPointsPerSecond() {
        #expect(offset(1.5) == 15)
        #expect(offset(2) == 30)
    }

    @Test func restsAtTheEnd() {
        #expect(offset(3) == 60)
        #expect(offset(3.9) == 60)
    }

    @Test func returnsToTheStartAndRepeats() {
        #expect(offset(4.5) == 0)
        #expect(offset(6) == 30)
    }

    @Test func neverScrollsPastTheEnd() {
        for step in 0..<400 {
            let value = offset(Double(step) * 0.05)
            #expect(value >= 0 && value <= 60)
        }
    }
}
