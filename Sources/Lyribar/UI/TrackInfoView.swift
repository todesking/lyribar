import AppKit

/// One line of dimmed text, truncated at the tail.
///
/// Not an NSTextField: inside a status bar button it invalidates itself every time AppKit snapshots
/// the button, even while hidden, which schedules the next snapshot and keeps the main thread busy.
@MainActor
final class TrackInfoView: NSView {
    static func width(of text: String) -> CGFloat {
        MarqueeTextView.width(of: text)
    }

    var text: String = "" {
        didSet {
            guard text != oldValue else { return }
            textHeight = NSAttributedString(string: text, attributes: [.font: MarqueeTextView.font]).size().height
            needsDisplay = true
        }
    }

    private var textHeight: CGFloat = 0

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

    override func draw(_ dirtyRect: NSRect) {
        guard !text.isEmpty else { return }
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        let attributes: [NSAttributedString.Key: Any] = [
            .font: MarqueeTextView.font,
            // Drawn by hand, `secondaryLabelColor` is too dark to read on the menu bar.
            .foregroundColor: NSColor.labelColor.withAlphaComponent(BarTextLayer.dimmedAlpha),
            .paragraphStyle: paragraph,
        ]
        let rect = NSRect(
            x: 0, y: ((bounds.height - textHeight) / 2).rounded(), width: bounds.width, height: textHeight)
        (text as NSString).draw(
            with: rect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], attributes: attributes)
    }
}
