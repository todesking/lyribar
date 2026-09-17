import Foundation

/// Determines which lyric line is current for a given playback position.
enum LineTracker {
    /// Returns the index of the last line whose `time <= position`, via binary search.
    /// Returns `nil` if no such line exists (e.g. `position` is before the first line,
    /// or `lyrics` is empty).
    static func currentIndex(at position: TimeInterval, in lyrics: SyncedLyrics) -> Int? {
        let lines = lyrics.lines
        var low = 0
        var high = lines.count - 1
        var result: Int?

        while low <= high {
            let mid = (low + high) / 2
            if lines[mid].time <= position {
                result = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }

        return result
    }
}
