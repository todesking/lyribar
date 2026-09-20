import AppKit

/// Shows the lyrics ribbon scrolled to the playback position: the current line in the label color,
/// the lines around it dimmed.
///
/// The lines are text layers on one ribbon layer, see `BarTextLayer`. While playing, one keyframe
/// animation over the whole track scrolls that layer, so the scrolling does not depend on the main
/// thread. A slow timer only refreshes the snapshots AppKit keeps of the status bar button, which it
/// shows while switching Spaces; they are rendered from the model position, not from the animation.
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
    static let settleDuration: TimeInterval = 0.25
    /// Farther than that is a seek.
    static let maxSettleDistance: CGFloat = 80
    static let spaceSettleDuration: TimeInterval = 0.4
    /// Found by eye on macOS 27: shorter and the glide is over before the live layers are back.
    static let spaceFreezeDuration: TimeInterval = 0.5
    /// A snapshot replaced while it is shown is one more jump.
    static let snapshotHoldAfterSpaceChange: TimeInterval = 0.5

    private(set) var ribbon: LyricsRibbon?
    // Internal so tests can check the scrolling and the highlight.
    let ribbonLayer = CALayer()
    /// One per line; nil for interludes.
    private(set) var lineLayers: [CATextLayer?] = []
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
        if let animation = settleAnimation(from: delta, duration: Self.spaceSettleDuration, limit: .infinity) {
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
        animation.duration = total
        animation.beginTime = mediaTime - playback.position(at: now)
        animation.fillMode = .both
        animation.isRemovedOnCompletion = false
        return animation
    }

    private func rebuild() {
        lineLayers.forEach { $0?.removeFromSuperlayer() }
        if let lyrics {
            let sizes = lyrics.lines.map { line -> CGSize in
                // Interludes take no room besides the gap.
                guard !line.text.allSatisfy(\.isWhitespace) else { return .zero }
                return NSAttributedString(string: line.text, attributes: [.font: MarqueeTextView.font]).size()
            }
            ribbon = LyricsRibbon(lines: lyrics.lines, widths: sizes.map { ceil($0.width) })
            lineLayers = zip(lyrics.lines, sizes).map { line, size in
                guard size.width > 0 else { return nil }
                let layer = BarTextLayer.make()
                BarTextLayer.setText(line.text, size: size, on: layer)
                ribbonLayer.addSublayer(layer)
                return layer
            }
        } else {
            ribbon = nil
            lineLayers = []
        }
        textColor = nil
        updateScale()
        updateColors()
        layoutLines()
        updateScrolling()
        refreshSnapshots(now: Date())
    }

    private func layoutLines() {
        guard let ribbon else { return }
        BarTextLayer.withoutActions {
            for (index, layer) in lineLayers.enumerated() {
                guard let layer else { continue }
                layer.position = CGPoint(
                    x: ribbon.origins[index], y: ((bounds.height - layer.bounds.height) / 2).rounded())
            }
        }
    }

    /// The lines are dimmed by their color: a layer with an `opacity` is composited through an
    /// offscreen buffer in every snapshot, even when it is scrolled out of sight.
    private func updateColors(of indices: [Int?]) {
        guard let textColor else { return }
        let dimmed = BarTextLayer.dimmed(textColor)
        BarTextLayer.withoutActions {
            for case let index? in indices where lineLayers.indices.contains(index) {
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
        updateColors(of: Array(lineLayers.indices))
        return true
    }

    private func updateScale() {
        let scale = BarTextLayer.scale(for: self)
        BarTextLayer.withoutActions {
            lineLayers.forEach { $0?.contentsScale = scale }
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
                refreshSnapshots(now: now)
            }
        } else {
            updatePosition(now: now)
            // Nothing refreshes the snapshots while the ribbon rests.
            if wasScrolling || ribbonLayer.position != oldPosition {
                refreshSnapshots(now: now)
            }
        }
        if let spaceChange, now < spaceChange.at.addingTimeInterval(Self.spaceFreezeDuration) {
            addSpaceChangeAnimations(now: now)
        } else if let shownX, let animation = settleAnimation(from: shownX - positionX(at: now)) {
            ribbonLayer.add(animation, forKey: Self.settleAnimationKey)
        }
    }

    /// A pause arrives late, so the ribbon has scrolled past the position it reports; resyncs are a
    /// little off too. Small corrections glide instead of jumping. Nil for seeks and for no correction.
    func settleAnimation(
        from delta: CGFloat, duration: TimeInterval = settleDuration, limit: CGFloat = maxSettleDistance
    ) -> CABasicAnimation? {
        guard delta != 0, abs(delta) <= limit else { return nil }
        let animation = CABasicAnimation(keyPath: "position.x")
        animation.isAdditive = true
        animation.fromValue = delta
        animation.toValue = 0
        animation.duration = duration
        animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
        return animation
    }

    /// A snapshot is shown at some time during the interval it is valid for, so while scrolling it
    /// aims at the middle: that halves how far off it can be.
    private func refreshSnapshots(now: Date) {
        updatePosition(now: isAnimating ? now.addingTimeInterval(Self.snapshotInterval / 2) : now)
        snapshotX = ribbonLayer.position.x
        snapshotRefreshes += 1
        needsDisplay = true
    }

    private func updateTimer() {
        let shouldRun = wantsAnimation && window != nil
        if shouldRun, timer == nil {
            let timer = Timer(timeInterval: Self.snapshotInterval, repeats: true) { [weak self] timer in
                let alive = MainActor.assumeIsolated {
                    if let self, Date() >= self.snapshotHoldUntil {
                        self.refreshSnapshots(now: Date())
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
