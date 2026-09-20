import AppKit

/// Scroll offset of an overflowing text as a function of time: rest at the start, scroll left until
/// the end of the text is visible, rest there, then jump back to the start.
enum MarqueeAnimation {
    static let speed: CGFloat = 30
    static let pause: TimeInterval = 1

    static func offset(elapsed: TimeInterval, textWidth: CGFloat, availableWidth: CGFloat) -> CGFloat {
        let distance = textWidth - availableWidth
        guard distance > 0, elapsed > 0 else { return 0 }
        let scrollDuration = TimeInterval(distance / speed)
        let cycle = pause + scrollDuration + pause
        let t = elapsed.truncatingRemainder(dividingBy: cycle)
        if t <= pause { return 0 }
        if t >= pause + scrollDuration { return distance }
        return CGFloat(t - pause) * speed
    }
}

/// The text is a layer and scrolling only moves it, see `BarTextLayer`.
@MainActor
final class MarqueeTextView: NSView {
    static let frameInterval: TimeInterval = 1.0 / 30.0

    static var font: NSFont { NSFont.menuBarFont(ofSize: 0) }

    static func width(of text: String) -> CGFloat {
        ceil(NSAttributedString(string: text, attributes: [.font: font]).size().width)
    }

    var text: String = "" {
        didSet {
            guard text != oldValue else { return }
            textSize = NSAttributedString(string: text, attributes: [.font: Self.font]).size()
            BarTextLayer.withoutActions {
                BarTextLayer.setText(text, size: textSize, on: textLayer)
            }
            restart()
        }
    }

    // Internal so tests can check the scrolling.
    let textLayer = BarTextLayer.make()
    private var textSize: CGSize = .zero
    private var startedAt = Date()
    private var timer: Timer?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        let host = CALayer()
        host.masksToBounds = true
        layer = host
        wantsLayer = true
        clipsToBounds = true
        host.addSublayer(textLayer)
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
            updateTimer()
            updatePosition(now: Date())
            needsDisplay = true
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateScale()
        updateTimer()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        updateScale()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColor()
    }

    func updatePosition(now: Date) {
        let offset = MarqueeAnimation.offset(
            elapsed: now.timeIntervalSince(startedAt),
            textWidth: ceil(textSize.width),
            availableWidth: bounds.width
        )
        BarTextLayer.withoutActions {
            textLayer.position = CGPoint(
                x: BarTextLayer.pixelAligned(-offset, scale: BarTextLayer.scale(for: self)),
                y: ((bounds.height - textLayer.bounds.height) / 2).rounded())
        }
    }

    private func updateColor() {
        let color = BarTextLayer.labelColor(for: self)
        guard color != textLayer.foregroundColor else { return }
        BarTextLayer.withoutActions {
            textLayer.foregroundColor = color
        }
    }

    private func updateScale() {
        BarTextLayer.withoutActions {
            textLayer.contentsScale = BarTextLayer.scale(for: self)
        }
    }

    private var overflows: Bool {
        !text.isEmpty && ceil(textSize.width) > bounds.width
    }

    private func restart() {
        startedAt = Date()
        updateColor()
        updateTimer()
        updatePosition(now: startedAt)
        // Once per text, so that the snapshots AppKit keeps of the button do not go stale.
        needsDisplay = true
    }

    private func updateTimer() {
        let shouldRun = overflows && window != nil
        if shouldRun, timer == nil {
            let timer = Timer(timeInterval: Self.frameInterval, repeats: true) { [weak self] timer in
                let alive = MainActor.assumeIsolated {
                    self?.updatePosition(now: Date())
                    return self != nil
                }
                if !alive {
                    timer.invalidate()
                }
            }
            // .common keeps the marquee moving while the menu is open.
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        } else if !shouldRun {
            timer?.invalidate()
            timer = nil
        }
    }
}
