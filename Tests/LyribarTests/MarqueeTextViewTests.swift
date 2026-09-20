import AppKit
import Testing

@testable import Lyribar

@MainActor
struct MarqueeTextViewTests {
    private let track = TrackInfo(id: "spotify:track:abc", title: "Song", artist: "Artist", duration: 200)
    private let syncedAt = Date(timeIntervalSince1970: 1_000)
    private let longText = String(repeating: "a very long line of lyrics ", count: 20)

    // From 10 s to 30 s.
    private var longLine: CurrentLineContent { CurrentLineContent(text: longText, start: 10, end: 30) }
    private var distance: CGFloat { MarqueeTextView.width(of: longText) - 100 }

    private func state(playing: Bool, position: TimeInterval, at date: Date? = nil) -> PlaybackState {
        PlaybackState(track: track, isPlaying: playing, syncedPosition: position, syncedAt: date ?? syncedAt)
    }

    private func makeView() -> MarqueeTextView {
        MarqueeTextView(frame: NSRect(x: 0, y: 0, width: 100, height: 22))
    }

    /// The window is never shown; it only gives the view a window to be in.
    private func makeWindow(with view: MarqueeTextView) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 100, height: 22), styleMask: [.borderless],
            backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        window.contentView?.addSubview(view)
        return window
    }

    private func aligned(_ x: CGFloat, in view: MarqueeTextView) -> CGFloat {
        BarTextLayer.pixelAligned(x, scale: BarTextLayer.scale(for: view))
    }

    private func scrollAnimation(of view: MarqueeTextView) -> CABasicAnimation? {
        view.textLayer.animation(forKey: MarqueeTextView.scrollAnimationKey) as? CABasicAnimation
    }

    private func settleAnimation(of view: MarqueeTextView) -> CABasicAnimation? {
        view.textLayer.animation(forKey: MarqueeTextView.settleAnimationKey) as? CABasicAnimation
    }

    @Test func textGoesToTheLayer() {
        let view = makeView()
        view.line = CurrentLineContent(text: "la la", start: 10, end: 30)
        #expect(view.text == "la la")
        #expect(view.textLayer.string as? String == "la la")
        #expect(view.textLayer.bounds.width == MarqueeTextView.width(of: "la la"))

        view.line = nil
        #expect(view.text.isEmpty)
        #expect(view.textLayer.string as? String == "")
    }

    @Test func scrollAnimationPlaysTheWholeLineFromThePlaybackPosition() throws {
        let view = makeView()
        view.line = longLine
        view.playback = state(playing: true, position: 12)

        let animation = try #require(view.scrollAnimation(now: syncedAt.addingTimeInterval(3), mediaTime: 1_000))
        #expect(animation.keyPath == "position.x")
        #expect(animation.fromValue as? CGFloat == 0)
        #expect(animation.toValue as? CGFloat == aligned(-distance, in: view))
        #expect(animation.duration == 20)
        // 5 s into the line at media time 1000.
        #expect(animation.beginTime == 995)
        #expect(animation.fillMode == .both)
        #expect(!animation.isRemovedOnCompletion)
        #expect(!animation.isAdditive)
        var point = [Float](repeating: .nan, count: 2)
        animation.timingFunction?.getControlPoint(at: 1, values: &point)
        #expect(point == [0, 0])
        animation.timingFunction?.getControlPoint(at: 2, values: &point)
        #expect(point == [1, 1])
    }

    // Before the line the animation has not begun, and `fillMode` keeps the text at the start.
    @Test func scrollAnimationBeginsLaterForAPositionBeforeTheLine() throws {
        let view = makeView()
        view.line = longLine
        view.playback = state(playing: true, position: 4)
        let animation = try #require(view.scrollAnimation(now: syncedAt, mediaTime: 1_000))
        #expect(animation.beginTime == 1_006)
    }

    // Scrolling is an animation of the layer instead of redrawing the view.
    @Test func overflowingLineScrollsWhilePlayingInAWindow() throws {
        let view = makeView()
        let window = makeWindow(with: view)
        defer { window.close() }
        let now = Date()
        view.playback = state(playing: true, position: 15, at: now)
        view.line = longLine

        let animation = try #require(scrollAnimation(of: view))
        #expect(animation.keyPath == "position.x")
        #expect(animation.fromValue as? CGFloat == 0)
        #expect(animation.toValue as? CGFloat == aligned(-distance, in: view))
        #expect(animation.duration == 20)
        // Both clocks run at the same pace, so it does not matter when this is compared.
        let mediaTime = view.textLayer.convertTime(CACurrentMediaTime(), from: nil)
        let expected = mediaTime - (view.playback.position(at: Date()) - 10)
        #expect(abs(animation.beginTime - expected) < 0.05)
    }

    @Test func doesNotScrollOutsideAWindow() {
        let view = makeView()
        view.playback = state(playing: true, position: 15, at: Date())
        view.line = longLine
        #expect(scrollAnimation(of: view) == nil)
        #expect(view.textLayer.position.x < 0)

        let window = makeWindow(with: view)
        defer { window.close() }
        #expect(scrollAnimation(of: view) != nil)

        view.removeFromSuperview()
        #expect(scrollAnimation(of: view) == nil)
    }

    @Test func fittingLineStaysStill() {
        let view = makeView()
        let window = makeWindow(with: view)
        defer { window.close() }
        view.playback = state(playing: true, position: 15, at: Date())
        view.line = CurrentLineContent(text: "la", start: 10, end: 30)

        #expect(scrollAnimation(of: view) == nil)
        #expect(view.scrollAnimation(now: Date(), mediaTime: 1_000) == nil)
        #expect(view.textLayer.position.x == 0)
    }

    @Test func pausedLineRestsAtTheOffsetOfThePlaybackPosition() {
        let view = makeView()
        let window = makeWindow(with: view)
        defer { window.close() }
        view.playback = state(playing: false, position: 15)
        view.line = longLine

        #expect(scrollAnimation(of: view) == nil)
        #expect(view.offset(at: Date()) == distance / 4)
        #expect(view.textLayer.position.x == aligned(-distance / 4, in: view))

        view.playback = state(playing: false, position: 30)
        #expect(view.textLayer.position.x == aligned(-distance, in: view))
        view.playback = state(playing: false, position: 5)
        #expect(view.textLayer.position.x == 0)
    }

    @Test func lineWithoutLengthStaysStill() {
        let view = makeView()
        let window = makeWindow(with: view)
        defer { window.close() }
        view.playback = state(playing: true, position: 15, at: Date())
        for end in [10, 4] as [TimeInterval] {
            view.line = CurrentLineContent(text: longText, start: 10, end: end)
            #expect(scrollAnimation(of: view) == nil)
            #expect(view.textLayer.position.x == 0)
        }
    }

    @Test func pausingStopsTheScrollingAndResumingStartsItAgain() throws {
        let view = makeView()
        let window = makeWindow(with: view)
        defer { window.close() }
        let now = Date()
        view.line = longLine
        view.playback = state(playing: true, position: 15, at: now)
        #expect(scrollAnimation(of: view) != nil)

        view.playback = state(playing: false, position: 20, at: now)
        #expect(scrollAnimation(of: view) == nil)
        #expect(view.textLayer.position.x == aligned(-distance / 2, in: view))

        view.playback = state(playing: true, position: 20, at: now)
        #expect(scrollAnimation(of: view) != nil)
    }

    @Test func seekRebuildsTheAnimationAtTheNewPosition() throws {
        let view = makeView()
        let window = makeWindow(with: view)
        defer { window.close() }
        let now = Date()
        view.line = longLine
        view.playback = state(playing: true, position: 12, at: now)
        let before = try #require(scrollAnimation(of: view))

        view.playback = state(playing: true, position: 25, at: now)
        let after = try #require(scrollAnimation(of: view))
        #expect(after !== before)
        #expect(abs((before.beginTime - after.beginTime) - 13) < 0.05)
        let mediaTime = view.textLayer.convertTime(CACurrentMediaTime(), from: nil)
        #expect(abs(after.beginTime - (mediaTime - (view.playback.position(at: Date()) - 10))) < 0.05)
    }

    @Test func newLineRebuildsTheAnimationOverItsStretch() throws {
        let view = makeView()
        let window = makeWindow(with: view)
        defer { window.close() }
        view.playback = state(playing: true, position: 29, at: Date())
        view.line = longLine

        // The same text again, sung in another stretch.
        view.line = CurrentLineContent(text: longText, start: 30, end: 34)
        let animation = try #require(scrollAnimation(of: view))
        #expect(animation.duration == 4)
        let mediaTime = view.textLayer.convertTime(CACurrentMediaTime(), from: nil)
        #expect(abs(animation.beginTime - (mediaTime + 1)) < 0.05)
    }

    @Test func resizingRebuildsTheAnimation() throws {
        let view = makeView()
        let window = makeWindow(with: view)
        defer { window.close() }
        view.playback = state(playing: true, position: 15, at: Date())
        view.line = longLine

        view.setFrameSize(NSSize(width: 160, height: 22))
        let animation = try #require(scrollAnimation(of: view))
        #expect(animation.toValue as? CGFloat == aligned(-(distance - 60), in: view))

        view.setFrameSize(NSSize(width: 5_000, height: 22))
        #expect(scrollAnimation(of: view) == nil)
        #expect(view.textLayer.position.x == 0)
    }

    // A resync is a little off, and a pause arrives after the text has scrolled past it.
    @Test func smallCorrectionsOfTheSameLineGlide() throws {
        let view = makeView()
        let window = makeWindow(with: view)
        defer { window.close() }
        let now = Date()
        view.line = longLine
        view.playback = state(playing: false, position: 15, at: now)
        let restingX = view.textLayer.position.x
        view.shownX = { restingX - 6 }

        view.playback = state(playing: false, position: 15.1, at: now)
        let settle = try #require(settleAnimation(of: view))
        #expect(settle.isAdditive)
        let delta = try #require(settle.fromValue as? CGFloat)
        #expect(abs(delta - (restingX - 6 - view.textLayer.position.x)) < 0.001)
        #expect(settle.toValue as? CGFloat == 0)
        #expect(settle.duration == BarTextLayer.settleDuration)

        // While playing it is added to the scrolling.
        view.playback = state(playing: true, position: 15.1, at: now)
        #expect(settleAnimation(of: view) != nil)
        #expect(scrollAnimation(of: view) != nil)
    }

    @Test func seeksJump() {
        let view = makeView()
        let window = makeWindow(with: view)
        defer { window.close() }
        view.line = longLine
        view.playback = state(playing: false, position: 15)
        let restingX = view.textLayer.position.x
        view.shownX = { restingX - BarTextLayer.maxSettleDistance - 50 }

        view.playback = state(playing: false, position: 15.1)
        #expect(settleAnimation(of: view) == nil)
    }

    // Going back to the start for the next line is not a correction, however short the way is.
    @Test func newLineJumpsToItsStart() {
        let view = makeView()
        let window = makeWindow(with: view)
        defer { window.close() }
        view.playback = state(playing: true, position: 30, at: Date())
        view.line = CurrentLineContent(text: longText, start: 10, end: 30)
        view.shownX = { -6 }

        view.line = CurrentLineContent(text: longText + "!", start: 30, end: 40)
        #expect(scrollAnimation(of: view) != nil)
        #expect(settleAnimation(of: view) == nil)

        // Neither for the same text in another stretch.
        view.line = CurrentLineContent(text: longText + "!", start: 40, end: 50)
        #expect(settleAnimation(of: view) == nil)

        // A glide that is under way ends with the line.
        view.playback = state(playing: true, position: 30.1, at: Date())
        #expect(settleAnimation(of: view) != nil)
        view.line = CurrentLineContent(text: "next", start: 50, end: 60)
        #expect(settleAnimation(of: view) == nil)
    }

    // An invalidation makes AppKit snapshot the status bar button some nine times.
    @Test func redrawsOnlyWhenTheRestingTextMoves() {
        let view = makeView()
        let window = makeWindow(with: view)
        defer { window.close() }
        let now = Date()
        view.playback = state(playing: true, position: 12, at: now)
        var requests = view.redrawRequests
        view.line = longLine
        #expect(view.redrawRequests == requests + 1)

        // Resyncs and seeks while scrolling leave the snapshots alone.
        requests = view.redrawRequests
        let modelX = view.textLayer.position.x
        view.playback = state(playing: true, position: 13, at: now)
        view.playback = state(playing: true, position: 25, at: now)
        #expect(view.redrawRequests == requests)
        #expect(view.textLayer.position.x == modelX)

        // Nothing else refreshes them once the text rests.
        view.playback = state(playing: false, position: 26, at: now)
        #expect(view.redrawRequests == requests + 1)
        view.playback = state(playing: false, position: 20, at: now)
        #expect(view.redrawRequests == requests + 2)
        view.playback = state(playing: false, position: 20, at: now.addingTimeInterval(1))
        #expect(view.redrawRequests == requests + 2)

        view.playback = state(playing: true, position: 20, at: now)
        #expect(view.redrawRequests == requests + 2)
    }

    @Test func clicksFallThrough() {
        let view = makeView()
        #expect(view.hitTest(NSPoint(x: 10, y: 10)) == nil)
    }
}
