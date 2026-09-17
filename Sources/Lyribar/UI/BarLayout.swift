import CoreGraphics

/// Horizontal layout of the status item: [lyric] [track info] [icon], never wider than `maxWidth`
/// (except that the icon is always kept).
struct BarLayout: Equatable {
    static let padding: CGFloat = 6
    static let spacing: CGFloat = 8
    // Share of the text area that the track info may keep when the lyric also needs room.
    static let trackInfoShare: CGFloat = 0.4

    var lyric: ClosedRange<CGFloat>?
    var trackInfo: ClosedRange<CGFloat>?
    var icon: ClosedRange<CGFloat>
    var totalWidth: CGFloat

    static func compute(
        lyricWidth: CGFloat?,
        trackInfoWidth: CGFloat?,
        iconWidth: CGFloat,
        maxWidth: CGFloat
    ) -> BarLayout {
        let minimumTotal = padding * 2 + iconWidth
        // Room for the texts, including the spacing that follows each of them.
        var available = max(0, maxWidth - minimumTotal)

        var trackWidth: CGFloat = 0
        var lyricResult: CGFloat = 0
        let lyricNatural = lyricWidth.map { ceil($0) } ?? 0
        let trackNatural = trackInfoWidth.map { ceil($0) } ?? 0

        if trackNatural > 0 {
            let room = available - spacing
            if lyricNatural > 0 {
                let textRoom = room - spacing
                let leftover = textRoom - lyricNatural
                trackWidth = min(trackNatural, max(textRoom * trackInfoShare, leftover))
            } else {
                trackWidth = min(trackNatural, room)
            }
            trackWidth = max(0, floor(trackWidth))
            if trackWidth > 0 {
                available -= trackWidth + spacing
            }
        }
        if lyricNatural > 0 {
            lyricResult = max(0, floor(min(lyricNatural, available - spacing)))
        }

        var x = padding
        var lyricRange: ClosedRange<CGFloat>?
        var trackRange: ClosedRange<CGFloat>?
        if lyricResult > 0 {
            lyricRange = x...(x + lyricResult)
            x += lyricResult + spacing
        }
        if trackWidth > 0 {
            trackRange = x...(x + trackWidth)
            x += trackWidth + spacing
        }
        let iconRange = x...(x + iconWidth)
        return BarLayout(
            lyric: lyricRange, trackInfo: trackRange, icon: iconRange, totalWidth: x + iconWidth + padding)
    }
}
