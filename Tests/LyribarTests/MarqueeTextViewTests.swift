import AppKit
import Testing

@testable import Lyribar

@MainActor
struct MarqueeTextViewTests {
    private let longText = String(repeating: "a very long line of lyrics ", count: 20)

    @Test func textGoesToTheLayer() {
        let view = MarqueeTextView(frame: NSRect(x: 0, y: 0, width: 100, height: 22))
        view.text = "la la"
        #expect(view.textLayer.string as? String == "la la")
        #expect(view.textLayer.bounds.width == MarqueeTextView.width(of: "la la"))
    }

    // Scrolling moves the layer instead of redrawing the view.
    @Test func overflowingTextScrollsTheLayer() {
        let view = MarqueeTextView(frame: NSRect(x: 0, y: 0, width: 100, height: 22))
        view.text = longText
        #expect(view.textLayer.position.x == 0)

        view.updatePosition(now: Date().addingTimeInterval(MarqueeAnimation.pause + 1))
        #expect(view.textLayer.position.x < 0)
    }

    @Test func fittingTextStaysStill() {
        let view = MarqueeTextView(frame: NSRect(x: 0, y: 0, width: 100, height: 22))
        view.text = "la"
        view.updatePosition(now: Date().addingTimeInterval(MarqueeAnimation.pause + 1))
        #expect(view.textLayer.position.x == 0)
    }

    @Test func clicksFallThrough() {
        let view = MarqueeTextView(frame: NSRect(x: 0, y: 0, width: 100, height: 22))
        #expect(view.hitTest(NSPoint(x: 10, y: 10)) == nil)
    }
}
