import AppKit

/// Draws the lyrics ribbon scrolled to the playback position: the current line in the label color,
/// the lines around it dimmed.
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
            needsDisplay = true
        }
    }

    var playback: PlaybackState = .empty() {
        didSet {
            guard playback != oldValue else { return }
            updateTimer()
            needsDisplay = true
        }
    }

    static let dimmedAlpha: CGFloat = 0.7

    private(set) var ribbon: LyricsRibbon?
    private var heights: [CGFloat] = []
    private var timer: Timer?

    /// Whether the ribbon moves by itself; while it does not, it is only redrawn on changes.
    var wantsAnimation: Bool { ribbon != nil && playback.isPlaying }
    var isAnimating: Bool { timer != nil }

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
        let changed = newSize != frame.size
        super.setFrameSize(newSize)
        if changed {
            needsDisplay = true
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateTimer()
    }

    func offset(at now: Date) -> CGFloat {
        ribbon?.offset(at: playback.position(at: now), duration: playback.track?.duration ?? 0) ?? 0
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ribbon else { return }
        let dimmed = NSColor.labelColor.withAlphaComponent(Self.dimmedAlpha)
        for (index, x) in ribbon.visibleLines(offset: offset(at: Date()), viewportWidth: bounds.width) {
            let attributes: [NSAttributedString.Key: Any] = [
                .font: MarqueeTextView.font,
                .foregroundColor: index == currentIndex ? NSColor.labelColor : dimmed,
            ]
            let origin = NSPoint(x: x, y: ((bounds.height - heights[index]) / 2).rounded())
            (ribbon.lines[index].text as NSString).draw(at: origin, withAttributes: attributes)
        }
    }

    private func rebuild() {
        if let lyrics {
            let sizes = lyrics.lines.map { line -> CGSize in
                // Interludes take no room besides the gap.
                guard !line.text.allSatisfy(\.isWhitespace) else { return .zero }
                return NSAttributedString(string: line.text, attributes: [.font: MarqueeTextView.font]).size()
            }
            ribbon = LyricsRibbon(lines: lyrics.lines, widths: sizes.map { ceil($0.width) })
            heights = sizes.map(\.height)
        } else {
            ribbon = nil
            heights = []
        }
        updateTimer()
        needsDisplay = true
    }

    private func updateTimer() {
        let shouldRun = wantsAnimation && window != nil
        if shouldRun, timer == nil {
            let timer = Timer(timeInterval: MarqueeTextView.frameInterval, repeats: true) { [weak self] timer in
                let alive = MainActor.assumeIsolated {
                    self?.needsDisplay = true
                    return self != nil
                }
                if !alive {
                    timer.invalidate()
                }
            }
            // .common keeps the ribbon moving while the menu is open.
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        } else if !shouldRun {
            timer?.invalidate()
            timer = nil
        }
    }
}
