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
            restart()
        }
    }

    private var textSize: CGSize = .zero
    private var startedAt = Date()
    private var timer: Timer?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        clipsToBounds = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func setFrameSize(_ newSize: NSSize) {
        let widthChanged = newSize.width != frame.width
        super.setFrameSize(newSize)
        if widthChanged {
            updateTimer()
            needsDisplay = true
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateTimer()
    }

    override func draw(_ dirtyRect: NSRect) {
        guard !text.isEmpty else { return }
        let offset = MarqueeAnimation.offset(
            elapsed: Date().timeIntervalSince(startedAt),
            textWidth: ceil(textSize.width),
            availableWidth: bounds.width
        )
        let attributes: [NSAttributedString.Key: Any] = [
            .font: Self.font,
            .foregroundColor: NSColor.labelColor,
        ]
        let origin = NSPoint(x: -offset, y: ((bounds.height - textSize.height) / 2).rounded())
        (text as NSString).draw(at: origin, withAttributes: attributes)
    }

    private var overflows: Bool {
        !text.isEmpty && ceil(textSize.width) > bounds.width
    }

    private func restart() {
        startedAt = Date()
        updateTimer()
        needsDisplay = true
    }

    private func updateTimer() {
        let shouldRun = overflows && window != nil
        if shouldRun, timer == nil {
            let timer = Timer(timeInterval: Self.frameInterval, repeats: true) { [weak self] timer in
                let alive = MainActor.assumeIsolated {
                    self?.needsDisplay = true
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
