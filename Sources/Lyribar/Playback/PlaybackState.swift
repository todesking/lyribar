import Foundation

struct PlaybackState: Equatable, Sendable {
    var track: TrackInfo?
    var isPlaying: Bool
    var syncedPosition: TimeInterval
    var syncedAt: Date

    static func empty(at now: Date = Date()) -> PlaybackState {
        PlaybackState(track: nil, isPlaying: false, syncedPosition: 0, syncedAt: now)
    }

    func position(at now: Date) -> TimeInterval {
        var position = syncedPosition
        if isPlaying {
            position += now.timeIntervalSince(syncedAt)
        }
        if let duration = track?.duration {
            position = min(position, duration)
        }
        return max(position, 0)
    }
}
