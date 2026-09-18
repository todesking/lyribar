import CoreGraphics
import Foundation

/// All lines laid out side by side: `[line 0] gap [line 1] gap …`. The scroll offset is the ribbon x
/// that sits at the anchor, interpolated so that each line starts at the anchor at its own time.
struct LyricsRibbon: Equatable {
    static let gap: CGFloat = 24
    /// The anchor sits at this share of the lyric area, measured from its left edge.
    static let anchorShare: CGFloat = 0.5

    let lines: [LyricLine]
    let widths: [CGFloat]
    /// `lines.count + 1` values: the start of each line, then the end of the last line plus the gap.
    let origins: [CGFloat]

    init(lines: [LyricLine], widths: [CGFloat]) {
        precondition(lines.count == widths.count)
        self.lines = lines
        self.widths = widths
        var origins: [CGFloat] = [0]
        origins.reserveCapacity(lines.count + 1)
        for width in widths {
            origins.append(origins[origins.count - 1] + width + Self.gap)
        }
        self.origins = origins
    }

    func offset(at position: TimeInterval, duration: TimeInterval) -> CGFloat {
        guard let first = lines.first, let last = lines.last else { return 0 }

        if position < first.time {
            guard first.time > 0 else { return origins[0] }
            return Self.interpolate(
                position, from: (0, origins[0] - Self.gap), to: (first.time, origins[0]))
        }

        // The last line starting at or before the position; of lines sharing a time, the later one.
        var low = 0
        var high = lines.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if lines[mid].time <= position {
                low = mid
            } else {
                high = mid - 1
            }
        }

        if low == lines.count - 1 {
            guard duration > last.time else { return origins[low] }
            return Self.interpolate(
                position, from: (last.time, origins[low]), to: (duration, origins[low + 1]))
        }
        return Self.interpolate(
            position, from: (lines[low].time, origins[low]), to: (lines[low + 1].time, origins[low + 1]))
    }

    /// Lines with text that intersect the viewport, with their x in viewport coordinates.
    func visibleLines(offset: CGFloat, viewportWidth: CGFloat) -> [(index: Int, x: CGFloat)] {
        let anchor = viewportWidth * Self.anchorShare
        var visible: [(index: Int, x: CGFloat)] = []
        for index in lines.indices where widths[index] > 0 {
            let x = anchor + origins[index] - offset
            if x >= viewportWidth { break }
            if x + widths[index] > 0 {
                visible.append((index, x))
            }
        }
        return visible
    }

    private static func interpolate(
        _ position: TimeInterval, from: (time: TimeInterval, x: CGFloat), to: (time: TimeInterval, x: CGFloat)
    ) -> CGFloat {
        guard to.time > from.time else { return to.x }
        let progress = min(max((position - from.time) / (to.time - from.time), 0), 1)
        return from.x + (to.x - from.x) * CGFloat(progress)
    }
}
