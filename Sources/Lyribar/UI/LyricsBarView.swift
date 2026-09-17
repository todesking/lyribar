import AppKit

/// [current line (marquee)] [Title – Artist] [icon]. Mouse events fall through to the status bar button.
@MainActor
final class LyricsBarView: NSView {
    static let iconWidth: CGFloat = 18

    private let marquee = MarqueeTextView(frame: .zero)
    private let trackLabel = NSTextField(labelWithString: "")
    private let iconView = NSImageView(frame: .zero)

    private(set) var content = BarContent()
    private(set) var maxWidth: CGFloat = CGFloat(Settings.defaultMaxWidth)
    private(set) var layoutResult = BarLayout.compute(
        lyricWidth: nil, trackInfoWidth: nil, iconWidth: LyricsBarView.iconWidth,
        maxWidth: CGFloat(Settings.defaultMaxWidth))

    var preferredWidth: CGFloat { layoutResult.totalWidth }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        trackLabel.font = MarqueeTextView.font
        trackLabel.textColor = .secondaryLabelColor
        trackLabel.lineBreakMode = .byTruncatingTail
        trackLabel.maximumNumberOfLines = 1
        trackLabel.cell?.usesSingleLineMode = true

        let image = NSImage(systemSymbolName: "music.note.list", accessibilityDescription: "Lyribar")
        image?.isTemplate = true
        iconView.image = image
        iconView.imageScaling = .scaleProportionallyDown

        addSubview(marquee)
        addSubview(trackLabel)
        addSubview(iconView)
        update(content: content, maxWidth: maxWidth)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func update(content: BarContent, maxWidth: CGFloat) {
        self.content = content
        self.maxWidth = maxWidth

        marquee.text = content.lyric ?? ""
        trackLabel.stringValue = content.trackInfo ?? ""
        layoutResult = BarLayout.compute(
            lyricWidth: content.lyric.map(MarqueeTextView.width(of:)),
            // NSTextField draws its text inset from the frame.
            trackInfoWidth: content.trackInfo.map { _ in ceil(trackLabel.intrinsicContentSize.width) },
            iconWidth: Self.iconWidth,
            maxWidth: maxWidth
        )
        setFrameSize(NSSize(width: layoutResult.totalWidth, height: frame.height))
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let height = bounds.height

        marquee.isHidden = layoutResult.lyric == nil
        if let range = layoutResult.lyric {
            marquee.frame = NSRect(x: range.lowerBound, y: 0, width: range.upperBound - range.lowerBound, height: height)
        }

        trackLabel.isHidden = layoutResult.trackInfo == nil
        if let range = layoutResult.trackInfo {
            let labelHeight = trackLabel.intrinsicContentSize.height
            trackLabel.frame = NSRect(
                x: range.lowerBound, y: ((height - labelHeight) / 2).rounded(),
                width: range.upperBound - range.lowerBound, height: labelHeight)
        }

        let icon = layoutResult.icon
        iconView.frame = NSRect(x: icon.lowerBound, y: 0, width: icon.upperBound - icon.lowerBound, height: height)
    }
}
