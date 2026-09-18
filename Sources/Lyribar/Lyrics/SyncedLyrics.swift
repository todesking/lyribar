import Foundation

/// Invariant: `lines` is sorted by `time` in ascending order.
struct SyncedLyrics: Equatable, Codable {
    let lines: [LyricLine]
}
