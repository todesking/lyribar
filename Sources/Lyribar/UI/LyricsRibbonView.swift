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
            updateHighlight()
        }
    }

    var playback: PlaybackState = .empty() {
        didSet {
            guard playback != oldValue else { return }
            updateScrolling()
        }
    }

    static let dimmedAlpha: Float = 0.7
    /// Every refresh blocks the main thread for some 10 ms, and the snapshots are rarely visible.
    static let snapshotInterval: TimeInterval = 1
    static let scrollAnimationKey = "scroll"

    private(set) var ribbon: LyricsRibbon?
    // Internal so tests can check the scrolling and the highlight.
    let ribbonLayer = CALayer()
    /// One per line; nil for interludes.
    private(set) var lineLayers: [CATextLayer?] = []
    private var textColor: CGColor?
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
            needsDisplay = true
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
        updateColors()
    }

    func offset(at now: Date) -> CGFloat {
        ribbon?.offset(at: playback.position(at: now), duration: playback.track?.duration ?? 0) ?? 0
    }

    private var anchorX: CGFloat { bounds.width * LyricsRibbon.anchorShare }

    /// Moves the model position; while the animation runs, only the snapshots show it.
    func updatePosition(now: Date) {
        BarTextLayer.withoutActions {
            ribbonLayer.position = CGPoint(
                x: BarTextLayer.pixelAligned(anchorX - offset(at: now), scale: BarTextLayer.scale(for: self)),
                y: 0)
        }
    }

    /// The scrolling of the whole track, to be started at `mediaTime` for the playback position at
    /// `now`. Nil when there is nothing to scroll.
    func scrollAnimation(now: Date, mediaTime: CFTimeInterval) -> CAKeyframeAnimation? {
        guard let ribbon else { return nil }
        let keyframes = ribbon.keyframes(duration: playback.track?.duration ?? 0)
        guard keyframes.count >= 2, let total = keyframes.last?.time, total > 0 else { return nil }

        let animation = CAKeyframeAnimation(keyPath: "position.x")
        animation.values = keyframes.map { anchorX - $0.x }
        animation.keyTimes = keyframes.map { NSNumber(value: $0.time / total) }
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
        updateHighlight()
        layoutLines()
        updateScrolling()
        needsDisplay = true
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

    private func updateHighlight() {
        BarTextLayer.withoutActions {
            for (index, layer) in lineLayers.enumerated() {
                layer?.opacity = index == currentIndex ? 1 : Self.dimmedAlpha
            }
        }
    }

    private func updateColors() {
        let color = BarTextLayer.labelColor(for: self)
        guard color != textColor else { return }
        textColor = color
        BarTextLayer.withoutActions {
            lineLayers.forEach { $0?.foregroundColor = color }
        }
    }

    private func updateScale() {
        let scale = BarTextLayer.scale(for: self)
        BarTextLayer.withoutActions {
            lineLayers.forEach { $0?.contentsScale = scale }
        }
    }

    /// Seeks, pauses and resyncs all arrive as a new `playback`, so the animation is simply rebuilt.
    private func updateScrolling() {
        updateTimer()
        let now = Date()
        ribbonLayer.removeAnimation(forKey: Self.scrollAnimationKey)
        updatePosition(now: now)
        guard isAnimating else { return }
        let mediaTime = ribbonLayer.convertTime(CACurrentMediaTime(), from: nil)
        if let animation = scrollAnimation(now: now, mediaTime: mediaTime) {
            ribbonLayer.add(animation, forKey: Self.scrollAnimationKey)
        }
    }

    private func updateTimer() {
        let shouldRun = wantsAnimation && window != nil
        if shouldRun, timer == nil {
            let timer = Timer(timeInterval: Self.snapshotInterval, repeats: true) { [weak self] timer in
                let alive = MainActor.assumeIsolated {
                    self?.updatePosition(now: Date())
                    self?.needsDisplay = true
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
