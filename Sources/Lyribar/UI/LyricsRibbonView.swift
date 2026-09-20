import AppKit

/// Shows the lyrics ribbon scrolled to the playback position: the current line in the label color,
/// the lines around it dimmed.
///
/// The lines are text layers on one ribbon layer, see `BarTextLayer`. While playing, one keyframe
/// animation over the whole track scrolls that layer, so the scrolling does not depend on the main
/// thread. A slow timer only refreshes the snapshots AppKit keeps of the status bar button, which it
/// shows while switching Spaces; they are rendered from the model position, not from the animation.
///
/// Only the lines that can come into view before the next refresh have a layer: every snapshot walks
/// all the layers of the ribbon, the clipped ones too.
@MainActor
final class LyricsRibbonView: NSView {
    var lyrics: SyncedLyrics? {
        didSet {
            guard lyrics != oldValue else { return }
            rebuild()
        }
    }

    var currentIndex: Int? {
        didSet {
            guard currentIndex != oldValue else { return }
            // No `needsDisplay`: the snapshots it triggers would stall the scrolling on every line.
            updateColors(of: [oldValue, currentIndex])
        }
    }

    var playback: PlaybackState = .empty() {
        didSet {
            guard playback != oldValue else { return }
            updateScrolling()
        }
    }

    /// Every refresh blocks the main thread for some 10 ms, and the snapshots are rarely visible.
    static let snapshotInterval: TimeInterval = 1
    static let scrollAnimationKey = "scroll"
    static let settleAnimationKey = "settle"
    static let freezeAnimationKey = "freeze"
    static let spaceSettleDuration: TimeInterval = 0.4
    /// Found by eye on macOS 27: shorter and the glide is over before the live layers are back.
    static let spaceFreezeDuration: TimeInterval = 0.5
    /// A snapshot replaced while it is shown is one more jump.
    static let snapshotHoldAfterSpaceChange: TimeInterval = 0.5
    static let attachSlack: TimeInterval = 1
    /// How far ahead lines are attached: the longest the next refresh can be away, which is one held
    /// back by a Space change, and the slack for a late timer.
    static let attachHorizon: TimeInterval =
        snapshotInterval + spaceFreezeDuration + snapshotHoldAfterSpaceChange + attachSlack
    /// Around the viewport, for the rounding of the position.
    static let attachMargin: CGFloat = 24

    private(set) var ribbon: LyricsRibbon?
    // Internal so tests can check the scrolling and the highlight.
    let ribbonLayer = CALayer()
    /// The attached lines by their index. Interludes are never attached.
    private(set) var lineLayers: [Int: CATextLayer] = [:]
    private var textSizes: [CGSize] = []
    // Internal for tests: `needsDisplay` cannot be reset in a window that is never shown.
    private(set) var snapshotRefreshes = 0
    /// Where the snapshots show the ribbon.
    private var snapshotX: CGFloat?
    private var snapshotHoldUntil = Date.distantPast
    private var spaceChange: (at: Date, x: CGFloat)?
    private var textColor: CGColor?
    private var colorUpdatePending = false
    private var timer: Timer?

    /// Whether the ribbon moves by itself; while it does not, it only moves on changes.
    var wantsAnimation: Bool { ribbon != nil && playback.isPlaying }
    var isAnimating: Bool { timer != nil }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        let host = CALayer()
        host.masksToBounds = true
        layer = host
        wantsLayer = true
        clipsToBounds = true

        ribbonLayer.anchorPoint = .zero
        host.addSublayer(ribbonLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func setFrameSize(_ newSize: NSSize) {
        let changed = newSize != frame.size
        super.setFrameSize(newSize)
        if changed {
            layoutLines()
            updateScrolling()
            refreshSnapshots(now: Date())
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateScale()
        updateScrolling()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        updateScale()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        guard !colorUpdatePending else { return }
        colorUpdatePending = true
        BarTextLayer.afterAppearanceSettled { [weak self] in
            guard let self else { return }
            colorUpdatePending = false
            if updateColors() {
                refreshSnapshots(now: Date())
            }
        }
    }

    func offset(at now: Date) -> CGFloat {
        ribbon?.offset(at: playback.position(at: now), duration: playback.track?.duration ?? 0) ?? 0
    }

    private var anchorX: CGFloat { bounds.width * LyricsRibbon.anchorShare }

    private func positionX(at now: Date) -> CGFloat {
        BarTextLayer.pixelAligned(anchorX - offset(at: now), scale: BarTextLayer.scale(for: self))
    }

    /// Moves the model position; while the animation runs, only the snapshots show it.
    func updatePosition(now: Date) {
        BarTextLayer.withoutActions {
            ribbonLayer.position = CGPoint(x: positionX(at: now), y: 0)
        }
    }

    /// AppKit shows a snapshot until a moment after the switch, so the ribbon comes back where the
    /// snapshot had it and glides to where it belongs.
    func activeSpaceDidChange(now: Date = Date()) {
        guard isAnimating, let snapshotX else { return }
        snapshotHoldUntil = now.addingTimeInterval(Self.spaceFreezeDuration + Self.snapshotHoldAfterSpaceChange)
        spaceChange = (at: now, x: snapshotX)
        addSpaceChangeAnimations(now: now)
        updateAttachedLines(now: now)
        let hold = snapshotHoldUntil
        DispatchQueue.main.asyncAfter(deadline: .now() + hold.timeIntervalSince(now)) { [weak self] in
            MainActor.assumeIsolated {
                // Catches up on the refresh that was held, unless another switch holds it again.
                guard let self, self.isAnimating, self.snapshotHoldUntil == hold else { return }
                self.refreshSnapshots(now: Date())
            }
        }
    }

    /// The live layers come back an unknown moment after the notification, so the ribbon waits at the
    /// snapshot position for about that long before it glides.
    private func addSpaceChangeAnimations(now: Date) {
        guard let spaceChange else { return }
        let freeze = max(0, spaceChange.at.addingTimeInterval(Self.spaceFreezeDuration).timeIntervalSince(now))
        let mediaTime = ribbonLayer.convertTime(CACurrentMediaTime(), from: nil)
        ribbonLayer.removeAnimation(forKey: Self.freezeAnimationKey)
        ribbonLayer.removeAnimation(forKey: Self.settleAnimationKey)
        if freeze > 0 {
            let animation = CABasicAnimation(keyPath: "position.x")
            animation.fromValue = spaceChange.x
            animation.toValue = spaceChange.x
            animation.beginTime = mediaTime
            animation.duration = freeze
            ribbonLayer.add(animation, forKey: Self.freezeAnimationKey)
        }
        let delta = spaceChange.x - positionX(at: now.addingTimeInterval(freeze))
        // Not a seek however far it is: the snapshot is older after a held refresh.
        if let animation = BarTextLayer.settleAnimation(from: delta, duration: Self.spaceSettleDuration, limit: .infinity) {
            animation.beginTime = mediaTime + freeze
            ribbonLayer.add(animation, forKey: Self.settleAnimationKey)
        }
    }

    /// The scrolling of the whole track, to be started at `mediaTime` for the playback position at
    /// `now`. Nil when there is nothing to scroll.
    func scrollAnimation(now: Date, mediaTime: CFTimeInterval) -> CAKeyframeAnimation? {
        guard let ribbon else { return nil }
        let curve = ribbon.curve(duration: playback.track?.duration ?? 0)
        guard curve.nodes.count >= 2, let total = curve.nodes.last?.time, total > 0 else { return nil }

        let animation = CAKeyframeAnimation(keyPath: "position.x")
        animation.values = curve.nodes.map { anchorX - $0.x }
        animation.keyTimes = curve.nodes.map { NSNumber(value: $0.time / total) }
        animation.calculationMode = .linear
        // The values stay at the nodes; the timing functions give each segment its eased pace.
        animation.timingFunctions = curve.slopes.map {
            CAMediaTimingFunction(controlPoints: 1 / 3, Float($0.start) / 3, 2 / 3, 1 - Float($0.end) / 3)
        }
        animation.duration = total
        animation.beginTime = mediaTime - playback.position(at: now)
        animation.fillMode = .both
        animation.isRemovedOnCompletion = false
        return animation
    }

    private func rebuild() {
        BarTextLayer.withoutActions {
            lineLayers.values.forEach { $0.removeFromSuperlayer() }
        }
        lineLayers = [:]
        if let lyrics {
            textSizes = lyrics.lines.map { line -> CGSize in
                // Interludes take no room besides the gap.
                guard !line.text.allSatisfy(\.isWhitespace) else { return .zero }
                return NSAttributedString(string: line.text, attributes: [.font: MarqueeTextView.font]).size()
            }
            ribbon = LyricsRibbon(lines: lyrics.lines, widths: textSizes.map { ceil($0.width) })
        } else {
            textSizes = []
            ribbon = nil
        }
        textColor = nil
        updateColors()
        updateScrolling()
        refreshSnapshots(now: Date())
    }

    /// Attaches the lines that can be in view before the next update and drops the other ones.
    /// `shownX` is where the ribbon is on screen, for when the animations were just replaced.
    /// Sublayers coming and going do not invalidate the view, so this costs no snapshots.
    func updateAttachedLines(now: Date, shownX: CGFloat? = nil) {
        guard let ribbon else { return }
        var wanted = Set<Int>()
        for stretch in attachedStretches(of: ribbon, now: now, shownX: shownX) {
            wanted.formUnion(ribbon.lines(in: stretch))
        }
        guard wanted != Set(lineLayers.keys) else { return }

        let scale = BarTextLayer.scale(for: self)
        let dimmed = textColor.map(BarTextLayer.dimmed)
        BarTextLayer.withoutActions {
            for (index, layer) in lineLayers where !wanted.contains(index) {
                layer.removeFromSuperlayer()
                lineLayers[index] = nil
            }
            for index in wanted where lineLayers[index] == nil {
                let layer = BarTextLayer.make()
                BarTextLayer.setText(ribbon.lines[index].text, size: textSizes[index], on: layer)
                layer.contentsScale = scale
                layer.foregroundColor = index == currentIndex ? textColor : dimmed
                layer.position = linePosition(index, of: layer, in: ribbon)
                ribbonLayer.addSublayer(layer)
                lineLayers[index] = layer
            }
        }
    }

    /// In ribbon x. The scrolling over the horizon, the model position the snapshots are rendered
    /// from, and the position on screen: part of the scrolling while the ribbon glides from there,
    /// a stretch of its own after a seek, so that the lines in between stay off.
    private func attachedStretches(
        of ribbon: LyricsRibbon, now: Date, shownX: CGFloat?
    ) -> [ClosedRange<CGFloat>] {
        let from = offset(at: now)
        var low = from
        var high = max(from, offset(at: now.addingTimeInterval(Self.attachHorizon)))
        var offsets = [anchorX - ribbonLayer.position.x]

        var glidingFrom: CGFloat?
        let spaceChangeEnd = spaceChange?.at.addingTimeInterval(Self.spaceFreezeDuration + Self.spaceSettleDuration)
        if let spaceChange, let spaceChangeEnd, now < spaceChangeEnd {
            glidingFrom = anchorX - spaceChange.x
        } else if let shownX = shownX ?? ribbonLayer.presentation()?.position.x {
            if abs(shownX - positionX(at: now)) <= BarTextLayer.maxSettleDistance {
                glidingFrom = anchorX - shownX
            } else {
                offsets.append(anchorX - shownX)
            }
        }
        if let glidingFrom {
            low = min(low, glidingFrom)
            // A glide from ahead is added to the scrolling, so it reaches past the end of it.
            high += max(0, glidingFrom - from)
        }

        return ([(low, high)] + offsets.map { ($0, $0) }).map { low, high in
            let lower = ribbon.viewport(offset: low, width: bounds.width).lowerBound - Self.attachMargin
            let upper = ribbon.viewport(offset: high, width: bounds.width).upperBound + Self.attachMargin
            return lower...upper
        }
    }

    private func linePosition(_ index: Int, of layer: CALayer, in ribbon: LyricsRibbon) -> CGPoint {
        CGPoint(x: ribbon.origins[index], y: ((bounds.height - layer.bounds.height) / 2).rounded())
    }

    private func layoutLines() {
        guard let ribbon else { return }
        BarTextLayer.withoutActions {
            for (index, layer) in lineLayers {
                layer.position = linePosition(index, of: layer, in: ribbon)
            }
        }
    }

    /// The lines are dimmed by their color: a layer with an `opacity` is composited through an
    /// offscreen buffer in every snapshot, even when it is scrolled out of sight.
    private func updateColors(of indices: [Int?]) {
        guard let textColor else { return }
        let dimmed = BarTextLayer.dimmed(textColor)
        BarTextLayer.withoutActions {
            for case let index? in indices {
                lineLayers[index]?.foregroundColor = index == currentIndex ? textColor : dimmed
            }
        }
    }

    /// Whether the color changed.
    @discardableResult
    private func updateColors() -> Bool {
        let color = BarTextLayer.labelColor(for: self)
        guard color != textColor else { return false }
        textColor = color
        updateColors(of: Array(lineLayers.keys))
        return true
    }

    private func updateScale() {
        let scale = BarTextLayer.scale(for: self)
        BarTextLayer.withoutActions {
            lineLayers.values.forEach { $0.contentsScale = scale }
        }
    }

    /// Seeks, pauses and resyncs all arrive as a new `playback`, so the animation is simply rebuilt.
    /// While it runs the model position is left to `refreshSnapshots`, so that it stays where the
    /// snapshots show the ribbon.
    private func updateScrolling() {
        updateTimer()
        let now = Date()
        let shownX = ribbonLayer.presentation()?.position.x
        let wasScrolling = ribbonLayer.animation(forKey: Self.scrollAnimationKey) != nil
        let oldPosition = ribbonLayer.position
        ribbonLayer.removeAnimation(forKey: Self.scrollAnimationKey)
        ribbonLayer.removeAnimation(forKey: Self.settleAnimationKey)
        if isAnimating {
            let mediaTime = ribbonLayer.convertTime(CACurrentMediaTime(), from: nil)
            if let animation = scrollAnimation(now: now, mediaTime: mediaTime) {
                ribbonLayer.add(animation, forKey: Self.scrollAnimationKey)
            }
            if !wasScrolling {
                refreshSnapshots(now: now, shownX: shownX)
            }
        } else {
            updatePosition(now: now)
            // Nothing refreshes the snapshots while the ribbon rests.
            if wasScrolling || ribbonLayer.position != oldPosition {
                refreshSnapshots(now: now, shownX: shownX)
            }
        }
        if let spaceChange, now < spaceChange.at.addingTimeInterval(Self.spaceFreezeDuration) {
            addSpaceChangeAnimations(now: now)
        } else if let shownX, let animation = BarTextLayer.settleAnimation(from: shownX - positionX(at: now)) {
            ribbonLayer.add(animation, forKey: Self.settleAnimationKey)
        }
        updateAttachedLines(now: now, shownX: shownX)
    }

    /// A snapshot is shown at some time during the interval it is valid for, so while scrolling it
    /// aims at the middle: that halves how far off it can be. Internal for tests.
    func refreshSnapshots(now: Date, shownX: CGFloat? = nil) {
        updatePosition(now: isAnimating ? now.addingTimeInterval(Self.snapshotInterval / 2) : now)
        snapshotX = ribbonLayer.position.x
        updateAttachedLines(now: now, shownX: shownX)
        snapshotRefreshes += 1
        needsDisplay = true
    }

    private func updateTimer() {
        let shouldRun = wantsAnimation && window != nil
        if shouldRun, timer == nil {
            let timer = Timer(timeInterval: Self.snapshotInterval, repeats: true) { [weak self] timer in
                let alive = MainActor.assumeIsolated {
                    if let self {
                        let now = Date()
                        if now >= self.snapshotHoldUntil {
                            self.refreshSnapshots(now: now)
                        } else {
                            self.updateAttachedLines(now: now)
                        }
                    }
                    return self != nil
                }
                if !alive {
                    timer.invalidate()
                }
            }
            // .common keeps the snapshots fresh while the menu is open.
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        } else if !shouldRun {
            timer?.invalidate()
            timer = nil
        }
    }
}
