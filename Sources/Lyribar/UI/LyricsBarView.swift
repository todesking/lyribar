import AppKit

/// [lyrics (scrolling ribbon or current line marquee)] [Title – Artist] [icon]. Mouse events fall
/// through to the status bar button.
@MainActor
final class LyricsBarView: NSView {
    static let iconWidth: CGFloat = 18

    // Internal so tests can check which one takes the lyric area.
    let marquee = MarqueeTextView(frame: .zero)
    let ribbonView = LyricsRibbonView(frame: .zero)
    private let trackInfoView = TrackInfoView(frame: .zero)
    private let iconView = NSImageView(frame: .zero)

    private(set) var content = BarContent()
    private(set) var maxWidth: CGFloat = CGFloat(Settings.defaultMaxWidth)
    private(set) var layoutResult = BarLayout.compute(
        lyricWidth: nil, trackInfoWidth: nil, iconWidth: LyricsBarView.iconWidth,
        maxWidth: CGFloat(Settings.defaultMaxWidth))

    var preferredWidth: CGFloat { layoutResult.totalWidth }

    /// The lyric views interpolate the position themselves, so this is set on every tick.
    var playback: PlaybackState {
        get { ribbonView.playback }
        set {
            ribbonView.playback = newValue
            marquee.playback = newValue
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        let image = NSImage(systemSymbolName: "music.note.list", accessibilityDescription: "Lyribar")
        image?.isTemplate = true
        iconView.image = image
        iconView.imageScaling = .scaleProportionallyDown

        addSubview(marquee)
        addSubview(ribbonView)
        addSubview(trackInfoView)
        addSubview(iconView)
        update(content: content, maxWidth: maxWidth)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func update(content: BarContent, maxWidth: CGFloat) {
        let showedRibbon = self.content.ribbon != nil
        self.content = content
        self.maxWidth = maxWidth

        marquee.line = content.lyric
        ribbonView.lyrics = content.ribbon?.lyrics
        ribbonView.currentIndex = content.ribbon?.currentIndex
        trackInfoView.text = content.trackInfo ?? ""
        let newLayout = BarLayout.compute(
            // The ribbon has no width of its own; its room comes from `reservesLyricWidth`.
            lyricWidth: content.ribbon == nil ? content.lyric.map { MarqueeTextView.width(of: $0.text) } : nil,
            trackInfoWidth: content.trackInfo.map(TrackInfoView.width(of:)),
            iconWidth: Self.iconWidth,
            maxWidth: maxWidth,
            reservesLyricWidth: content.reservesLyricWidth
        )
        // Most updates only move the highlight. Inside a status bar button every layout pass makes
        // AppKit snapshot the button again, which is slow enough to stall the scrolling.
        let showsRibbon = content.ribbon != nil
        guard newLayout != layoutResult || showsRibbon != showedRibbon || frame.width != newLayout.totalWidth
        else { return }
        layoutResult = newLayout
        setFrameSize(NSSize(width: layoutResult.totalWidth, height: frame.height))
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let height = bounds.height

        let showsRibbon = content.ribbon != nil
        marquee.isHidden = layoutResult.lyric == nil || showsRibbon
        ribbonView.isHidden = layoutResult.lyric == nil || !showsRibbon
        if let range = layoutResult.lyric {
            let frame = NSRect(x: range.lowerBound, y: 0, width: range.upperBound - range.lowerBound, height: height)
            marquee.frame = frame
            ribbonView.frame = frame
        }

        trackInfoView.isHidden = layoutResult.trackInfo == nil
        if let range = layoutResult.trackInfo {
            trackInfoView.frame = NSRect(
                x: range.lowerBound, y: 0, width: range.upperBound - range.lowerBound, height: height)
        }

        let icon = layoutResult.icon
        iconView.frame = NSRect(x: icon.lowerBound, y: 0, width: icon.upperBound - icon.lowerBound, height: height)
    }
}
