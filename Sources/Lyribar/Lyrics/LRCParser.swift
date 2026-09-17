import Foundation

/// Parses LRC-formatted lyrics text into `SyncedLyrics`.
enum LRCParser {
    static func parse(_ text: String) -> SyncedLyrics? {
        var lines: [LyricLine] = []
        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.hasSuffix("\r") ? rawLine.dropLast() : rawLine
            lines.append(contentsOf: parseLine(line))
        }
        guard !lines.isEmpty else { return nil }
        lines.sort { $0.time < $1.time }
        return SyncedLyrics(lines: lines)
    }

    /// Consumes leading `[mm:ss.xx]` tags and pairs each with the remaining text.
    /// A line whose leading bracket is not a timestamp (e.g. `[ar:Artist]`) is ignored.
    private static func parseLine(_ line: Substring) -> [LyricLine] {
        var remainder = line
        var times: [TimeInterval] = []
        while remainder.first == "[" {
            guard let closeIndex = remainder.firstIndex(of: "]") else { break }
            let content = remainder[remainder.index(after: remainder.startIndex)..<closeIndex]
            guard let time = parseTimestamp(content) else { break }
            times.append(time)
            remainder = remainder[remainder.index(after: closeIndex)...]
        }
        guard !times.isEmpty else { return [] }
        let text = String(remainder)
        return times.map { LyricLine(time: $0, text: text) }
    }

    /// Parses `mm:ss.xx` where `mm` is 1+ digits, `ss` is exactly 2 digits,
    /// and `xx` is 2 or 3 digits.
    private static func parseTimestamp(_ content: Substring) -> TimeInterval? {
        let parts = content.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2 else { return nil }
        let secondsParts = parts[1].split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
        guard secondsParts.count == 2 else { return nil }

        let minutesPart = parts[0]
        let secondsPart = secondsParts[0]
        let fractionPart = secondsParts[1]

        guard isAllDigits(minutesPart),
            secondsPart.count == 2, isAllDigits(secondsPart),
            (2...3).contains(fractionPart.count), isAllDigits(fractionPart),
            let minutes = Double(minutesPart),
            let seconds = Double(secondsPart),
            let fraction = Double(fractionPart)
        else { return nil }

        let fractionScale = fractionPart.count == 2 ? 100.0 : 1000.0
        return minutes * 60 + seconds + fraction / fractionScale
    }

    private static func isAllDigits(_ s: Substring) -> Bool {
        !s.isEmpty && s.allSatisfy { $0.isASCII && $0.isNumber }
    }
}
