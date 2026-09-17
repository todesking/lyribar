import Foundation

struct TrackInfo: Equatable, Codable, Sendable {
    var id: String
    var title: String
    var artist: String
    var duration: TimeInterval
}
