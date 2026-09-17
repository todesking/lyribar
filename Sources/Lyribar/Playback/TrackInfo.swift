import Foundation

struct TrackInfo: Equatable, Codable, Sendable {
    var id: String
    var title: String
    var artist: String
    var duration: TimeInterval

    // Spotify may report a slightly different duration for the same track (a provisional value right
    // after a track change), so track identity must be compared by id, not by ==.
    func isSameTrack(as other: TrackInfo?) -> Bool {
        id == other?.id
    }
}
