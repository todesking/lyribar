import CoreGraphics

/// Horizontal layout of the status item: [lyric] [track info] [icon], never wider than `maxWidth`
/// (except that the icon is always kept).
///
/// With `reservesLyricWidth` the bar is exactly `maxWidth` wide and the lyric keeps whatever the
/// icon and the track info leave, so that the width does not change from line to line.
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
        maxWidth: CGFloat,
        reservesLyricWidth: Bool = false
    ) -> BarLayout {
        let minimumTotal = padding * 2 + iconWidth
        // The icon is kept even when it does not fit, so the fixed width has a floor.
        let fixedTotal = reservesLyricWidth ? max(maxWidth, minimumTotal) : nil
        // Room for the texts, including the spacing that follows each of them.
        var available = max(0, (fixedTotal ?? maxWidth) - minimumTotal)

        var trackWidth: CGFloat = 0
        var lyricResult: CGFloat = 0
        let lyricNatural = lyricWidth.map { ceil($0) } ?? 0
        let trackNatural = trackInfoWidth.map { ceil($0) } ?? 0

        if fixedTotal != nil {
            // The lyric takes the rest of the bar, so the track info share is measured against the
            // reserved room instead of against what the current line leaves.
            if trackNatural > 0 {
                let textRoom = available - spacing * 2
                trackWidth = max(0, floor(min(trackNatural, textRoom * trackInfoShare)))
                if trackWidth > 0 {
                    available -= trackWidth + spacing
                }
            }
            lyricResult = max(0, available - spacing)
        } else {
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
        // In the fixed mode the bar keeps its width even when nothing is left for the lyric, so the
        // icon stays at the trailing edge.
        let iconX = max(x, (fixedTotal ?? 0) - padding - iconWidth)
        let iconRange = iconX...(iconX + iconWidth)
        return BarLayout(
            lyric: lyricRange, trackInfo: trackRange, icon: iconRange,
            totalWidth: iconX + iconWidth + padding)
    }
}
