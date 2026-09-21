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

    /// Consumes leading `[mm:ss]` / `[mm:ss.xx]` tags and pairs each with the remaining text.
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
        // Some sources (e.g. LRCLIB) put a space right after the timestamp;
        // trim it so the displayed text isn't shifted. An instrumental gap
        // (no text after the timestamp) still ends up as an empty string.
        let text = String(remainder).trimmingCharacters(in: .whitespaces)
        return times.map { LyricLine(time: $0, text: text) }
    }

    /// Parses `mm:ss` or `mm:ss.xx` where `mm` is 1+ digits, `ss` is exactly 2 digits,
    /// and the optional fraction is 1 to 3 digits. `[offset:…]` is not applied.
    private static func parseTimestamp(_ content: Substring) -> TimeInterval? {
        let parts = content.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2 else { return nil }
        let secondsParts = parts[1].split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)

        let minutesPart = parts[0]
        let secondsPart = secondsParts[0]

        guard isAllDigits(minutesPart),
            secondsPart.count == 2, isAllDigits(secondsPart),
            let minutes = Double(minutesPart),
            let seconds = Double(secondsPart)
        else { return nil }

        var fractionSeconds = 0.0
        if secondsParts.count == 2 {
            let fractionPart = secondsParts[1]
            guard (1...3).contains(fractionPart.count), isAllDigits(fractionPart),
                let fraction = Double(fractionPart)
            else { return nil }
            fractionSeconds = fraction / pow(10, Double(fractionPart.count))
        }
        return minutes * 60 + seconds + fractionSeconds
    }

    private static func isAllDigits(_ s: Substring) -> Bool {
        !s.isEmpty && s.allSatisfy { $0.isASCII && $0.isNumber }
    }
}
