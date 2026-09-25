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
        curve(duration: duration).x(at: position)
    }

    /// The curve the scrolling follows, in time order: the lead-in from one gap before the first line
    /// (only when it does not start the track), one node per line, and the run-out to the end of the
    /// ribbon at the track duration (only when it is after the last line). Empty without lines.
    /// Of lines sharing a time only the last one has a node, so the segment before it scrolls past the
    /// others instead of the ribbon jumping over them.
    func curve(duration: TimeInterval) -> Curve {
        guard let first = lines.first, let last = lines.last else { return Curve(nodes: []) }
        var nodes: [Curve.Node] = []
        nodes.reserveCapacity(lines.count + 2)
        if first.time > 0 {
            nodes.append(Curve.Node(time: 0, x: origins[0] - Self.gap))
        }
        for index in lines.indices {
            let node = Curve.Node(time: lines[index].time, x: origins[index])
            if nodes.last?.time == node.time {
                nodes[nodes.count - 1] = node
            } else {
                nodes.append(node)
            }
        }
        if duration > last.time {
            nodes.append(Curve.Node(time: duration, x: origins[lines.count]))
        }
        return Curve(nodes: nodes)
    }

    /// The stretch of ribbon x that a viewport of that width shows when scrolled to `offset`.
    func viewport(offset: CGFloat, width: CGFloat) -> ClosedRange<CGFloat> {
        let left = offset - width * Self.anchorShare
        return left...(left + max(0, width))
    }

    /// The lines with text that intersect a stretch of ribbon x, in order. A line that only touches
    /// an end of the stretch does not intersect it.
    func lines(in stretch: ClosedRange<CGFloat>) -> [Int] {
        // The line ends ascend like the origins, so the first line reaching into the stretch is
        // found by bisection.
        var low = 0
        var high = lines.count
        while low < high {
            let mid = (low + high) / 2
            if origins[mid] + widths[mid] > stretch.lowerBound {
                high = mid
            } else {
                low = mid + 1
            }
        }
        var found: [Int] = []
        var index = low
        while index < lines.count, origins[index] < stretch.upperBound {
            if widths[index] > 0 {
                found.append(index)
            }
            index += 1
        }
        return found
    }
}

extension LyricsRibbon {
    /// Where the ribbon is over time: a cubic through the nodes that passes every node at one speed,
    /// so the scrolling does not change pace when a line begins. Each node is still reached at its own
    /// time, and the ribbon stands still before the first node and after the last one.
    struct Curve: Equatable {
        struct Node: Equatable {
            var time: TimeInterval
            var x: CGFloat
        }

        /// The speeds at both ends of a segment, each over the average speed of the segment itself.
        /// `1` on both ends is a straight line, `0` a standstill.
        struct Slopes: Equatable {
            var start: CGFloat
            var end: CGFloat
        }

        /// In strictly ascending time.
        let nodes: [Node]
        /// One per segment between two nodes, so one less than `nodes`.
        let slopes: [Slopes]

        init(nodes: [Node]) {
            self.nodes = nodes
            guard nodes.count > 1 else {
                slopes = []
                return
            }
            let speeds = (0..<nodes.count - 1).map { index in
                (nodes[index + 1].x - nodes[index].x) / CGFloat(nodes[index + 1].time - nodes[index].time)
            }
            let nodeSpeeds = nodes.indices.map { index -> CGFloat in
                guard index > 0, index < nodes.count - 1 else { return 0 }
                return Self.boundarySpeed(before: speeds[index - 1], after: speeds[index])
            }
            slopes = speeds.enumerated().map { index, speed in
                guard speed > 0 else { return Slopes(start: 1, end: 1) }
                return Slopes(start: nodeSpeeds[index] / speed, end: nodeSpeeds[index + 1] / speed)
            }
        }

        /// The speed the ribbon passes a node with, from the average speeds of the segments before and
        /// after it.
        static func boundarySpeed(before: CGFloat, after: CGFloat) -> CGFloat {
            guard before > 0, after > 0 else { return 0 }
            // The harmonic mean is at most twice the slower side, which keeps every segment monotone.
            return 2 * before * after / (before + after)
        }

        /// The share of a segment covered at `u` (0…1). This is the cubic Bezier timing function with
        /// the control points `(1/3, start/3)` and `(2/3, 1 - end/3)`, whose x is u itself.
        static func progress(at u: CGFloat, slopes: Slopes) -> CGFloat {
            let square = u * u
            let cube = square * u
            return slopes.start * (cube - 2 * square + u) + (3 * square - 2 * cube)
                + slopes.end * (cube - square)
        }

        func x(at position: TimeInterval) -> CGFloat {
            guard let first = nodes.first, let last = nodes.last else { return 0 }
            if position >= last.time { return last.x }
            if position < first.time { return first.x }

            var low = 0
            var high = nodes.count - 1
            while low < high {
                let mid = (low + high + 1) / 2
                if nodes[mid].time <= position {
                    low = mid
                } else {
                    high = mid - 1
                }
            }
            guard low + 1 < nodes.count else { return last.x }
            let from = nodes[low]
            let to = nodes[low + 1]
            let progress = Self.progress(
                at: CGFloat((position - from.time) / (to.time - from.time)), slopes: slopes[low])
            return from.x + (to.x - from.x) * progress
        }
    }
}
