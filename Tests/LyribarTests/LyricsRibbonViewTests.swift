import AppKit
import Testing

@testable import Lyribar

@MainActor
struct LyricsRibbonViewTests {
    private let track = TrackInfo(id: "spotify:track:abc", title: "Song", artist: "Artist", duration: 200)
    private let syncedAt = Date(timeIntervalSince1970: 1_000)
    private let lyrics = SyncedLyrics(lines: [
        LyricLine(time: 10, text: "first"),
        LyricLine(time: 20, text: "  "),
        LyricLine(time: 30, text: "third"),
    ])

    private func state(playing: Bool, position: TimeInterval = 0) -> PlaybackState {
        PlaybackState(track: track, isPlaying: playing, syncedPosition: position, syncedAt: syncedAt)
    }

    @Test func measuresTheLinesOfTheLyrics() throws {
        let view = LyricsRibbonView(frame: NSRect(x: 0, y: 0, width: 200, height: 22))
        view.lyrics = lyrics

        let ribbon = try #require(view.ribbon)
        #expect(ribbon.lines == lyrics.lines)
        #expect(ribbon.widths[0] == MarqueeTextView.width(of: "first"))
        #expect(ribbon.widths[1] == 0)
        #expect(ribbon.widths[2] == MarqueeTextView.width(of: "third"))

        view.lyrics = nil
        #expect(view.ribbon == nil)
    }

    @Test func offsetFollowsThePlaybackPosition() throws {
        let view = LyricsRibbonView(frame: NSRect(x: 0, y: 0, width: 200, height: 22))
        view.lyrics = lyrics
        view.playback = state(playing: true, position: 5)
        let ribbon = try #require(view.ribbon)

        #expect(view.offset(at: syncedAt.addingTimeInterval(5)) == ribbon.origins[0])
        #expect(view.offset(at: syncedAt.addingTimeInterval(25)) == ribbon.origins[2])
        // The track duration ends the ribbon.
        #expect(view.offset(at: syncedAt.addingTimeInterval(500)) == ribbon.origins[3])
    }

    @Test func offsetStaysWhilePaused() throws {
        let view = LyricsRibbonView(frame: NSRect(x: 0, y: 0, width: 200, height: 22))
        view.lyrics = lyrics
        view.playback = state(playing: false, position: 30)
        let ribbon = try #require(view.ribbon)

        #expect(view.offset(at: syncedAt) == ribbon.origins[2])
        #expect(view.offset(at: syncedAt.addingTimeInterval(60)) == ribbon.origins[2])
    }

    // Scrolling moves the layer instead of redrawing the view.
    @Test func ribbonLayerFollowsTheOffset() throws {
        let view = LyricsRibbonView(frame: NSRect(x: 0, y: 0, width: 200, height: 22))
        view.lyrics = lyrics
        view.playback = state(playing: true, position: 5)
        let ribbon = try #require(view.ribbon)
        let anchor = 200 * LyricsRibbon.anchorShare

        view.updatePosition(now: syncedAt.addingTimeInterval(5))
        #expect(view.ribbonLayer.position.x == anchor - ribbon.origins[0])
        view.updatePosition(now: syncedAt.addingTimeInterval(25))
        #expect(view.ribbonLayer.position.x == anchor - ribbon.origins[2])
    }

    @Test func scrollAnimationPlaysTheWholeTrackFromThePlaybackPosition() throws {
        let view = LyricsRibbonView(frame: NSRect(x: 0, y: 0, width: 200, height: 22))
        view.lyrics = lyrics
        view.playback = state(playing: true, position: 5)
        let ribbon = try #require(view.ribbon)
        let anchor = 200 * LyricsRibbon.anchorShare

        let animation = try #require(view.scrollAnimation(now: syncedAt.addingTimeInterval(7), mediaTime: 1_000))
        #expect(animation.keyPath == "position.x")
        #expect(animation.duration == 200)
        // 12 s into the track at media time 1000.
        #expect(animation.beginTime == 988)
        #expect(animation.keyTimes == [0, 0.05, 0.1, 0.15, 1])
        let values = try #require(animation.values as? [CGFloat])
        #expect(values == [
            anchor - (ribbon.origins[0] - LyricsRibbon.gap), anchor - ribbon.origins[0], anchor - ribbon.origins[1],
            anchor - ribbon.origins[2], anchor - ribbon.origins[3],
        ])

        view.lyrics = nil
        #expect(view.scrollAnimation(now: syncedAt, mediaTime: 1_000) == nil)
    }

    @Test func linesAreLayersAndOnlyTheCurrentOneIsNotDimmed() throws {
        let view = LyricsRibbonView(frame: NSRect(x: 0, y: 0, width: 200, height: 22))
        view.lyrics = lyrics
        view.currentIndex = 2
        let ribbon = try #require(view.ribbon)

        #expect(view.lineLayers.count == 3)
        #expect(view.lineLayers[1] == nil)
        let first = try #require(view.lineLayers[0])
        let third = try #require(view.lineLayers[2])
        #expect(first.string as? String == "first")
        #expect(third.position.x == ribbon.origins[2])
        // Dimmed by the color: an opacity makes every snapshot composite the layer offscreen.
        let color = try #require(third.foregroundColor)
        #expect(first.foregroundColor == BarTextLayer.dimmed(color))
        #expect(color.alpha > BarTextLayer.dimmed(color).alpha)
        #expect(first.opacity == 1)

        view.currentIndex = 0
        #expect(first.foregroundColor == color)
        #expect(third.foregroundColor == BarTextLayer.dimmed(color))

        view.lyrics = nil
        #expect(view.lineLayers.isEmpty)
        #expect(view.ribbonLayer.sublayers?.isEmpty ?? true)
    }

    @Test func animatesOnlyWhilePlayingWithLyrics() {
        let view = LyricsRibbonView(frame: NSRect(x: 0, y: 0, width: 200, height: 22))
        #expect(!view.wantsAnimation)

        view.playback = state(playing: true)
        #expect(!view.wantsAnimation)

        view.lyrics = lyrics
        #expect(view.wantsAnimation)

        view.playback = state(playing: false)
        #expect(!view.wantsAnimation)

        view.playback = state(playing: true)
        view.lyrics = nil
        #expect(!view.wantsAnimation)
    }

    // The window is never shown; it only gives the view a window to be in.
    @Test func timerRunsOnlyInsideAWindow() {
        let view = LyricsRibbonView(frame: NSRect(x: 0, y: 0, width: 200, height: 22))
        view.lyrics = lyrics
        view.playback = state(playing: true)
        #expect(!view.isAnimating)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 22), styleMask: [.borderless],
            backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        window.contentView?.addSubview(view)
        #expect(view.isAnimating)
        #expect(view.ribbonLayer.animation(forKey: LyricsRibbonView.scrollAnimationKey) != nil)

        view.playback = state(playing: false)
        #expect(!view.isAnimating)
        #expect(view.ribbonLayer.animation(forKey: LyricsRibbonView.scrollAnimationKey) == nil)

        view.playback = state(playing: true)
        #expect(view.isAnimating)
        #expect(view.ribbonLayer.animation(forKey: LyricsRibbonView.scrollAnimationKey) != nil)

        view.removeFromSuperview()
        #expect(!view.isAnimating)
        #expect(view.ribbonLayer.animation(forKey: LyricsRibbonView.scrollAnimationKey) == nil)
    }

    // While resting nothing else refreshes the snapshots AppKit shows when switching Spaces.
    @Test func stoppingRefreshesTheSnapshots() {
        let view = LyricsRibbonView(frame: NSRect(x: 0, y: 0, width: 200, height: 22))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 22), styleMask: [.borderless],
            backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        window.contentView?.addSubview(view)
        view.lyrics = lyrics
        view.playback = state(playing: true, position: 5)

        var refreshes = view.snapshotRefreshes
        view.playback = state(playing: true, position: 6)
        #expect(view.snapshotRefreshes == refreshes)

        view.playback = state(playing: false, position: 7)
        #expect(view.snapshotRefreshes == refreshes + 1)

        view.playback = state(playing: false, position: 25)
        #expect(view.snapshotRefreshes == refreshes + 2)

        refreshes = view.snapshotRefreshes
        view.playback = PlaybackState(
            track: track, isPlaying: false, syncedPosition: 25, syncedAt: syncedAt.addingTimeInterval(1))
        #expect(view.snapshotRefreshes == refreshes)
    }

    // The snapshot shown during the switch aims half an interval ahead of its refresh.
    @Test func spaceChangeGlidesFromTheSnapshotPosition() throws {
        let view = LyricsRibbonView(frame: NSRect(x: 0, y: 0, width: 200, height: 22))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 22), styleMask: [.borderless],
            backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        window.contentView?.addSubview(view)
        view.lyrics = lyrics
        let now = Date()
        view.playback = PlaybackState(track: track, isPlaying: true, syncedPosition: 12, syncedAt: now)
        let snapshotX = view.ribbonLayer.position.x

        view.activeSpaceDidChange(now: now.addingTimeInterval(0.8))
        let freeze = try #require(
            view.ribbonLayer.animation(forKey: LyricsRibbonView.freezeAnimationKey) as? CABasicAnimation)
        #expect(freeze.fromValue as? CGFloat == snapshotX)
        #expect(freeze.toValue as? CGFloat == snapshotX)
        #expect(abs(freeze.duration - LyricsRibbonView.spaceFreezeDuration) < 0.001)

        // The glide starts after the freeze, from the snapshot to the position at that time.
        let settle = try #require(
            view.ribbonLayer.animation(forKey: LyricsRibbonView.settleAnimationKey) as? CABasicAnimation)
        view.updatePosition(now: now.addingTimeInterval(0.8 + LyricsRibbonView.spaceFreezeDuration))
        let delta = try #require(settle.fromValue as? CGFloat)
        #expect(abs(delta - (snapshotX - view.ribbonLayer.position.x)) < 0.01)
        #expect(delta > 0)
        #expect(settle.duration == LyricsRibbonView.spaceSettleDuration)
        #expect(abs(settle.beginTime - (freeze.beginTime + freeze.duration)) < 0.001)

        view.playback = PlaybackState(track: track, isPlaying: false, syncedPosition: 13, syncedAt: now)
        view.ribbonLayer.removeAllAnimations()
        view.activeSpaceDidChange(now: now.addingTimeInterval(2))
        #expect(view.ribbonLayer.animation(forKey: LyricsRibbonView.settleAnimationKey) == nil)
    }

    @Test func smallCorrectionsGlideAndSeeksJump() throws {
        let view = LyricsRibbonView(frame: NSRect(x: 0, y: 0, width: 200, height: 22))

        let animation = try #require(view.settleAnimation(from: -8))
        #expect(animation.keyPath == "position.x")
        #expect(animation.isAdditive)
        #expect(animation.fromValue as? CGFloat == -8)
        #expect(animation.toValue as? CGFloat == 0)
        #expect(animation.duration == LyricsRibbonView.settleDuration)

        #expect(view.settleAnimation(from: 0) == nil)
        #expect(view.settleAnimation(from: LyricsRibbonView.maxSettleDistance + 1) == nil)
        #expect(view.settleAnimation(from: -LyricsRibbonView.maxSettleDistance - 1) == nil)
        #expect(view.settleAnimation(from: 500, limit: .infinity) != nil)
    }

    @Test func clicksFallThrough() {
        let view = LyricsRibbonView(frame: NSRect(x: 0, y: 0, width: 200, height: 22))
        #expect(view.hitTest(NSPoint(x: 10, y: 10)) == nil)
        #expect(view.clipsToBounds)
    }

    // AppKit swaps the appearance and puts it back for every snapshot of the status bar button.
    @Test func appearanceSwappedAndPutBackLeavesTheLayersAlone() async throws {
        let view = LyricsRibbonView(frame: NSRect(x: 0, y: 0, width: 200, height: 22))
        view.appearance = NSAppearance(named: .darkAqua)
        view.lyrics = lyrics
        view.currentIndex = 2
        await mainQueueTurn()
        let third = try #require(view.lineLayers[2])
        let dark = try #require(third.foregroundColor)
        let refreshes = view.snapshotRefreshes

        view.appearance = NSAppearance(named: .aqua)
        view.appearance = NSAppearance(named: .darkAqua)
        #expect(third.foregroundColor == dark)
        await mainQueueTurn()
        #expect(third.foregroundColor == dark)
        #expect(view.snapshotRefreshes == refreshes)

        view.appearance = NSAppearance(named: .aqua)
        #expect(third.foregroundColor == dark)
        await mainQueueTurn()
        #expect(third.foregroundColor != dark)
        #expect(view.lineLayers[0]?.foregroundColor == third.foregroundColor.map(BarTextLayer.dimmed))
        #expect(view.snapshotRefreshes == refreshes + 1)
    }

    private func mainQueueTurn() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
    }
}
