import Foundation

/// Invariant: `lines` is sorted by `time` in ascending order.
struct SyncedLyrics: Codable {
    let lines: [LyricLine]
}
