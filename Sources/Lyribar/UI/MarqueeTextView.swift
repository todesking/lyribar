import AppKit

/// Scroll offset of an overflowing line as a function of the playback position: the start of the
/// text is at the left edge when the line starts, the end of it at the right edge when the line ends,
/// at a steady pace in between.
enum MarqueeAnimation {
    static func offset(
        position: TimeInterval, start: TimeInterval, end: TimeInterval, textWidth: CGFloat, availableWidth: CGFloat
    ) -> CGFloat {
        let distance = textWidth - availableWidth
        guard distance > 0, end > start else { return 0 }
        let progress = min(max((position - start) / (end - start), 0), 1)
        return distance * CGFloat(progress)
    }
}

/// The text is a layer and scrolling only moves it, see `BarTextLayer`. While playing, one animation
/// over the stretch of the line scrolls that layer, so the scrolling does not depend on the main
/// thread.
@MainActor
final class MarqueeTextView: NSView {
    static let scrollAnimationKey = "scroll"
    static let settleAnimationKey = "settle"

    static var font: NSFont { NSFont.menuBarFont(ofSize: 0) }

    static func width(of text: String) -> CGFloat {
        ceil(NSAttributedString(string: text, attributes: [.font: font]).size().width)
    }

    var line: CurrentLineContent? {
        didSet {
            guard line != oldValue else { return }
            if text != oldValue?.text ?? "" {
                textSize = NSAttributedString(string: text, attributes: [.font: Self.font]).size()
                BarTextLayer.withoutActions {
                    BarTextLayer.setText(text, size: textSize, on: textLayer)
                }
            }
            updateColor()
            // Going back to the start of the next line is a jump, however short the way is.
            updateScrolling(redraws: true, glides: false)
        }
    }

    var text: String { line?.text ?? "" }

    var playback: PlaybackState = .empty() {
        didSet {
            guard playback != oldValue else { return }
            updateScrolling()
        }
    }

    // Internal so tests can check the scrolling.
    let textLayer = BarTextLayer.make()
    /// Where the text is on screen. Internal for tests: a layer that is never shown has no presentation.
    var shownX: () -> CGFloat? = { nil }
    // Internal for tests: `needsDisplay` cannot be reset in a window that is never shown.
    private(set) var redrawRequests = 0
    private var textSize: CGSize = .zero
    private var colorUpdatePending = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        let host = CALayer()
        host.masksToBounds = true
        layer = host
        wantsLayer = true
        clipsToBounds = true
        host.addSublayer(textLayer)
        shownX = { [textLayer] in textLayer.presentation()?.position.x }
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
            updateScrolling(redraws: true)
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
            if updateColor() {
                requestRedraw()
            }
        }
    }

    func offset(at now: Date) -> CGFloat {
        guard let line else { return 0 }
        return MarqueeAnimation.offset(
            position: playback.position(at: now), start: line.start, end: line.end,
            textWidth: ceil(textSize.width), availableWidth: bounds.width)
    }

    private func aligned(_ x: CGFloat) -> CGFloat {
        BarTextLayer.pixelAligned(x, scale: BarTextLayer.scale(for: self))
    }

    /// Moves the model position; while the animation runs, only the snapshots show it.
    func updatePosition(now: Date) {
        BarTextLayer.withoutActions {
            textLayer.position = CGPoint(
                x: aligned(-offset(at: now)), y: ((bounds.height - textLayer.bounds.height) / 2).rounded())
        }
    }

    /// The scrolling of the whole line, to be started at `mediaTime` for the playback position at
    /// `now`. Nil when the text rests: it fits, the line has no length, or the playback is paused.
    func scrollAnimation(now: Date, mediaTime: CFTimeInterval) -> CABasicAnimation? {
        guard let line, overflows, line.end > line.start, playback.isPlaying else { return nil }

        let animation = CABasicAnimation(keyPath: "position.x")
        animation.fromValue = CGFloat(0)
        animation.toValue = aligned(bounds.width - ceil(textSize.width))
        animation.duration = line.end - line.start
        animation.beginTime = mediaTime - (playback.position(at: now) - line.start)
        animation.timingFunction = CAMediaTimingFunction(name: .linear)
        animation.fillMode = .both
        animation.isRemovedOnCompletion = false
        return animation
    }

    /// Whether the color changed.
    @discardableResult
    private func updateColor() -> Bool {
        let color = BarTextLayer.labelColor(for: self)
        guard color != textLayer.foregroundColor else { return false }
        BarTextLayer.withoutActions {
            textLayer.foregroundColor = color
        }
        return true
    }

    private func updateScale() {
        BarTextLayer.withoutActions {
            textLayer.contentsScale = BarTextLayer.scale(for: self)
        }
    }

    /// An invalidation makes AppKit snapshot the status bar button some nine times.
    private func requestRedraw() {
        redrawRequests += 1
        needsDisplay = true
    }

    private var overflows: Bool {
        !text.isEmpty && ceil(textSize.width) > bounds.width
    }

    /// Seeks, pauses and resyncs all arrive as a new `playback`, so the animation is simply rebuilt.
    /// The snapshots AppKit keeps of the button show the model position. While the animation runs it
    /// stays where the last redraw had it; while the text rests, nothing else would redraw them.
    private func updateScrolling(redraws: Bool = false, glides: Bool = true) {
        let now = Date()
        let shownX = shownX()
        let wasScrolling = textLayer.animation(forKey: Self.scrollAnimationKey) != nil
        let oldPosition = textLayer.position
        textLayer.removeAnimation(forKey: Self.scrollAnimationKey)
        textLayer.removeAnimation(forKey: Self.settleAnimationKey)

        var redraws = redraws
        let mediaTime = textLayer.convertTime(CACurrentMediaTime(), from: nil)
        if window != nil, let animation = scrollAnimation(now: now, mediaTime: mediaTime) {
            textLayer.add(animation, forKey: Self.scrollAnimationKey)
            if redraws {
                updatePosition(now: now)
            }
        } else {
            updatePosition(now: now)
            redraws = redraws || wasScrolling || textLayer.position != oldPosition
        }
        if redraws {
            requestRedraw()
        }
        if glides, let shownX,
            let animation = BarTextLayer.settleAnimation(from: shownX - aligned(-offset(at: now)))
        {
            textLayer.add(animation, forKey: Self.settleAnimationKey)
        }
    }
}
