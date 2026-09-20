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

    // The keyframes stay on the line boundaries; the pace in between comes from the timing functions.
    @Test func scrollAnimationTimesEverySegmentWithTheCurveSlopes() throws {
        let view = LyricsRibbonView(frame: NSRect(x: 0, y: 0, width: 200, height: 22))
        view.lyrics = lyrics
        view.playback = state(playing: true, position: 5)
        let ribbon = try #require(view.ribbon)
        let curve = ribbon.curve(duration: track.duration)

        let animation = try #require(view.scrollAnimation(now: syncedAt, mediaTime: 1_000))
        let values = try #require(animation.values as? [CGFloat])
        let functions = try #require(animation.timingFunctions)
        #expect(animation.calculationMode == .linear)
        #expect(functions.count == values.count - 1)
        #expect(functions.count == curve.slopes.count)

        var point = [Float](repeating: .nan, count: 2)
        for (index, function) in functions.enumerated() {
            function.getControlPoint(at: 1, values: &point)
            #expect(abs(point[0] - 1.0 / 3) < 0.000_01)
            #expect(abs(point[1] - Float(curve.slopes[index].start) / 3) < 0.000_01)
            function.getControlPoint(at: 2, values: &point)
            #expect(abs(point[0] - 2.0 / 3) < 0.000_01)
            #expect(abs(point[1] - (1 - Float(curve.slopes[index].end) / 3)) < 0.000_01)
        }

        // The track starts and ends at a standstill, so those two handles sit on the ends.
        functions.first?.getControlPoint(at: 1, values: &point)
        #expect(point[1] == 0)
        functions.last?.getControlPoint(at: 2, values: &point)
        #expect(point[1] == 1)
    }

    @Test func linesAreLayersAndOnlyTheCurrentOneIsNotDimmed() throws {
        let view = LyricsRibbonView(frame: NSRect(x: 0, y: 0, width: 200, height: 22))
        view.lyrics = lyrics
        // Resting on the interlude, with both lines in view.
        view.playback = state(playing: false, position: 20)
        view.currentIndex = 2
        let ribbon = try #require(view.ribbon)

        #expect(view.lineLayers.keys.sorted() == [0, 2])
        #expect(view.ribbonLayer.sublayers?.count == 2)
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

    // A hundred lines of two seconds each, every tenth one an interlude.
    private let longTrack = TrackInfo(id: "spotify:track:long", title: "Long", artist: "Artist", duration: 300)
    private let longLyrics = SyncedLyrics(
        lines: (0..<100).map { index -> LyricLine in
            let text = index % 10 == 9 ? " " : "line number \(index) of the song"
            return LyricLine(time: TimeInterval(index) * 2 + 2, text: text)
        })

    private func longState(position: TimeInterval, at date: Date, playing: Bool = true) -> PlaybackState {
        PlaybackState(track: longTrack, isPlaying: playing, syncedPosition: position, syncedAt: date)
    }

    private func attached(_ view: LyricsRibbonView) -> Set<Int> {
        Set(view.lineLayers.keys)
    }

    /// The lines in the viewport when the ribbon is scrolled to `offset`.
    private func visible(_ view: LyricsRibbonView, offset: CGFloat) throws -> Set<Int> {
        let ribbon = try #require(view.ribbon)
        return Set(ribbon.lines(in: ribbon.viewport(offset: offset, width: view.bounds.width)))
    }

    private func visible(_ view: LyricsRibbonView, at date: Date) throws -> Set<Int> {
        try visible(view, offset: view.offset(at: date))
    }

    @Test func onlyTheLinesAroundTheViewportAreAttached() throws {
        let view = LyricsRibbonView(frame: NSRect(x: 0, y: 0, width: 200, height: 22))
        let now = Date()
        view.playback = longState(position: 100, at: now)
        view.lyrics = longLyrics

        let inView = try visible(view, at: now)
        #expect(!inView.isEmpty)
        #expect(inView.isSubset(of: attached(view)))
        #expect(view.lineLayers.count < 10)
        #expect(view.ribbonLayer.sublayers?.count == view.lineLayers.count)

        view.lyrics = nil
        #expect(view.lineLayers.isEmpty)
        #expect(view.ribbonLayer.sublayers?.isEmpty ?? true)
    }

    @Test func linesComingIntoViewWithinTheHorizonAreAttached() throws {
        let view = LyricsRibbonView(frame: NSRect(x: 0, y: 0, width: 200, height: 22))
        let now = Date()
        view.lyrics = longLyrics
        // Across lines and an interlude.
        for position in stride(from: TimeInterval(90), to: 104, by: 0.7) {
            view.playback = longState(position: position, at: now)
            view.updateAttachedLines(now: now)

            for step in stride(from: 0, through: LyricsRibbonView.attachHorizon, by: 0.05) {
                let inView = try visible(view, at: now.addingTimeInterval(step))
                #expect(inView.isSubset(of: attached(view)), "\(step) s after \(position) s")
            }
            #expect(view.lineLayers.count < 10)
        }
    }

    @Test func pausedRibbonAttachesOnlyWhatIsInView() throws {
        let view = LyricsRibbonView(frame: NSRect(x: 0, y: 0, width: 200, height: 22))
        let now = Date()
        view.lyrics = longLyrics
        view.playback = longState(position: 100, at: now, playing: false)

        let ribbon = try #require(view.ribbon)
        let viewport = ribbon.viewport(offset: view.offset(at: now), width: 200)
        let margin = LyricsRibbonView.attachMargin
        let around = ribbon.lines(in: (viewport.lowerBound - margin)...(viewport.upperBound + margin))
        #expect(attached(view) == Set(around))
        #expect(try visible(view, at: now).isSubset(of: attached(view)))

        // Nothing moves, however late the next update is.
        view.updateAttachedLines(now: now.addingTimeInterval(60))
        #expect(attached(view) == Set(around))
    }

    @Test func farSeekAttachesTheNewPlaceWithoutTheLinesInBetween() throws {
        let view = LyricsRibbonView(frame: NSRect(x: 0, y: 0, width: 200, height: 22))
        let now = Date()
        view.lyrics = longLyrics
        view.playback = longState(position: 40, at: now)
        let before = try visible(view, at: now)
        let shownX = view.ribbonLayer.position.x

        view.playback = longState(position: 160, at: now)
        let after = try visible(view, at: now)
        #expect(before.isDisjoint(with: after))
        #expect(after.isSubset(of: attached(view)))
        #expect(view.lineLayers.count < 10)

        // Until the next commit the ribbon is still on screen where it was.
        view.updateAttachedLines(now: now, shownX: shownX)
        #expect(before.isSubset(of: attached(view)))
        #expect(after.isSubset(of: attached(view)))
        #expect(view.lineLayers.count < 20)
        #expect(attached(view).isDisjoint(with: 30..<70))

        // The next refresh finds the ribbon at the new place only.
        view.refreshSnapshots(now: now)
        #expect(attached(view).isDisjoint(with: before))
        #expect(after.isSubset(of: attached(view)))
    }

    // A correction glides over everything between the two places.
    @Test func linesPassedWhileSettlingAreAttached() throws {
        let view = LyricsRibbonView(frame: NSRect(x: 0, y: 0, width: 40, height: 22))
        let now = Date()
        view.lyrics = longLyrics
        view.playback = longState(position: 100, at: now, playing: false)
        let offset = view.offset(at: now)
        let modelX = view.ribbonLayer.position.x

        for delta in [BarTextLayer.maxSettleDistance, -BarTextLayer.maxSettleDistance] {
            view.updateAttachedLines(now: now, shownX: modelX + delta)
            for step in stride(from: CGFloat(0), through: 1, by: 0.05) {
                let inView = try visible(view, offset: offset - delta * step)
                #expect(inView.isSubset(of: attached(view)), "\(delta) pt, \(step) of the way")
            }
        }
    }

    // A glide from ahead is added to the scrolling, so it can end up past the end of the horizon.
    @Test func glideFromAheadReachesPastTheHorizon() throws {
        let view = LyricsRibbonView(frame: NSRect(x: 0, y: 0, width: 200, height: 22))
        let now = Date()
        view.lyrics = longLyrics
        // Short of the limit: the view rests at its own, slightly later, idea of now.
        let ahead = BarTextLayer.maxSettleDistance - 2
        for position in stride(from: TimeInterval(100), to: 104, by: 0.25) {
            view.playback = longState(position: position, at: now)
            view.updateAttachedLines(now: now, shownX: view.ribbonLayer.position.x - ahead)
            let end = view.offset(at: now.addingTimeInterval(LyricsRibbonView.attachHorizon))
            #expect(try visible(view, offset: end + ahead).isSubset(of: attached(view)), "at \(position) s")
        }
    }

    // While scrolling in a window a new playback refreshes no snapshots, and still attaches.
    @Test func seekWhileScrollingAttachesWithoutRefreshingTheSnapshots() throws {
        let view = LyricsRibbonView(frame: NSRect(x: 0, y: 0, width: 200, height: 22))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 22), styleMask: [.borderless],
            backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        window.contentView?.addSubview(view)
        view.lyrics = longLyrics
        let now = Date()
        view.playback = longState(position: 40, at: now)
        let refreshes = view.snapshotRefreshes

        view.playback = longState(position: 160, at: now)
        #expect(view.snapshotRefreshes == refreshes)
        for step in stride(from: 0.1, through: LyricsRibbonView.attachHorizon, by: 0.1) {
            let inView = try visible(view, at: now.addingTimeInterval(step))
            #expect(inView.isSubset(of: attached(view)), "after \(step) s")
        }
        // The lines the snapshots show stay too, but nothing in between.
        #expect(view.lineLayers.count < 20)
        #expect(attached(view).isDisjoint(with: 30..<70))
    }

    @Test func refreshingTheSnapshotsMovesTheAttachedLinesAlong() throws {
        let view = LyricsRibbonView(frame: NSRect(x: 0, y: 0, width: 200, height: 22))
        let now = Date()
        view.lyrics = longLyrics
        view.playback = longState(position: 100, at: now)
        let before = try visible(view, at: now)
        #expect(before.isSubset(of: attached(view)))
        let refreshes = view.snapshotRefreshes

        let later = now.addingTimeInterval(20)
        view.refreshSnapshots(now: later)
        let after = try visible(view, at: later)
        #expect(after.isSubset(of: attached(view)))
        #expect(attached(view).isDisjoint(with: before))
        #expect(view.lineLayers.count < 10)
        #expect(view.ribbonLayer.sublayers?.count == view.lineLayers.count)
        #expect(view.snapshotRefreshes == refreshes + 1)
    }

    @Test func newlyAttachedLinesGetTheirColorPlaceAndScale() throws {
        let view = LyricsRibbonView(frame: NSRect(x: 0, y: 0, width: 200, height: 22))
        let now = Date()
        view.lyrics = longLyrics
        view.playback = longState(position: 100, at: now)
        let ribbon = try #require(view.ribbon)
        let later = now.addingTimeInterval(20)
        let current = try #require(try visible(view, at: later).min())
        #expect(view.lineLayers[current] == nil)

        // Not attached yet, so there is nothing to color.
        view.currentIndex = current
        view.updateAttachedLines(now: later)

        let color = BarTextLayer.labelColor(for: view)
        #expect(view.lineLayers.count > 1)
        for (index, layer) in view.lineLayers {
            #expect(layer.string as? String == longLyrics.lines[index].text)
            #expect(layer.position.x == ribbon.origins[index])
            #expect(layer.position.y == ((22 - layer.bounds.height) / 2).rounded())
            #expect(layer.bounds.width == ribbon.widths[index])
            #expect(layer.contentsScale == BarTextLayer.scale(for: view))
            #expect(layer.foregroundColor == (index == current ? color : BarTextLayer.dimmed(color)))
            #expect(layer.superlayer === view.ribbonLayer)
        }
        #expect(view.lineLayers[current] != nil)

        // The highlight moves among the attached lines, and ignores the other ones.
        let next = try #require(view.lineLayers.keys.filter { $0 != current }.min())
        view.currentIndex = next
        #expect(view.lineLayers[current]?.foregroundColor == BarTextLayer.dimmed(color))
        #expect(view.lineLayers[next]?.foregroundColor == color)
        view.currentIndex = 0
        #expect(view.lineLayers[0] == nil)
        #expect(view.lineLayers[next]?.foregroundColor == BarTextLayer.dimmed(color))
    }

    @Test func resizingLaysOutTheAttachedLines() throws {
        let view = LyricsRibbonView(frame: NSRect(x: 0, y: 0, width: 200, height: 22))
        let now = Date()
        view.lyrics = longLyrics
        view.playback = longState(position: 100, at: now, playing: false)
        let narrow = attached(view)

        view.setFrameSize(NSSize(width: 600, height: 30))
        #expect(try visible(view, at: now).isSubset(of: attached(view)))
        #expect(attached(view).count > narrow.count)
        for layer in view.lineLayers.values {
            #expect(layer.position.y == ((30 - layer.bounds.height) / 2).rounded())
        }
    }

    // An invalidation makes AppKit snapshot the status bar button some nine times.
    @Test func attachingLinesDoesNotRefreshTheSnapshots() throws {
        let view = LyricsRibbonView(frame: NSRect(x: 0, y: 0, width: 200, height: 22))
        let now = Date()
        view.lyrics = longLyrics
        view.playback = longState(position: 100, at: now)
        let before = attached(view)
        let refreshes = view.snapshotRefreshes

        let later = now.addingTimeInterval(20)
        view.updateAttachedLines(now: later)
        #expect(attached(view) != before)
        #expect(try visible(view, at: later).isSubset(of: attached(view)))
        // The snapshots still show the ribbon where it was, so those lines stay.
        #expect(try visible(view, at: now).isSubset(of: attached(view)))
        #expect(view.snapshotRefreshes == refreshes)
    }

    // The ribbon waits where the snapshot had it and glides from there.
    @Test func spaceChangeKeepsTheLinesOfTheSnapshotAttached() throws {
        let view = LyricsRibbonView(frame: NSRect(x: 0, y: 0, width: 200, height: 22))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 22), styleMask: [.borderless],
            backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        window.contentView?.addSubview(view)
        view.lyrics = longLyrics
        let now = Date()
        view.playback = longState(position: 100, at: now)
        let snapshotOffset = 200 * LyricsRibbon.anchorShare - view.ribbonLayer.position.x
        let refreshes = view.snapshotRefreshes

        // A refresh was held back, so the snapshot is a few lines old.
        let change = now.addingTimeInterval(8)
        view.activeSpaceDidChange(now: change)
        #expect(view.snapshotRefreshes == refreshes)
        #expect(try visible(view, offset: snapshotOffset).isSubset(of: attached(view)))
        let glide = view.offset(at: change) - snapshotOffset
        for step in stride(from: CGFloat(0), through: 1, by: 0.02) {
            let inView = try visible(view, offset: snapshotOffset + glide * step)
            #expect(inView.isSubset(of: attached(view)), "\(step) of the way")
        }
        for step in stride(from: 0, through: LyricsRibbonView.attachHorizon, by: 0.05) {
            let inView = try visible(view, at: change.addingTimeInterval(step))
            #expect(inView.isSubset(of: attached(view)), "after \(step) s")
        }

        // Once the glide is over the lines behind go.
        let after = change.addingTimeInterval(
            LyricsRibbonView.spaceFreezeDuration + LyricsRibbonView.spaceSettleDuration)
        view.refreshSnapshots(now: after)
        #expect(try attached(view).isDisjoint(with: visible(view, offset: snapshotOffset)))
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
        let animation = try #require(BarTextLayer.settleAnimation(from: -8))
        #expect(animation.keyPath == "position.x")
        #expect(animation.isAdditive)
        #expect(animation.fromValue as? CGFloat == -8)
        #expect(animation.toValue as? CGFloat == 0)
        #expect(animation.duration == BarTextLayer.settleDuration)

        #expect(BarTextLayer.settleAnimation(from: 0) == nil)
        #expect(BarTextLayer.settleAnimation(from: BarTextLayer.maxSettleDistance + 1) == nil)
        #expect(BarTextLayer.settleAnimation(from: -BarTextLayer.maxSettleDistance - 1) == nil)
        #expect(BarTextLayer.settleAnimation(from: 500, limit: .infinity) != nil)
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
        view.playback = state(playing: false, position: 20)
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
