import Foundation
import Testing
@testable import Lyribar

struct PlaybackStateTests {
    private let track = TrackInfo(id: "spotify:track:abc", title: "Song", artist: "Artist", duration: 200)
    private let syncedAt = Date(timeIntervalSince1970: 1_000)

    @Test func interpolatesWhilePlaying() {
        let state = PlaybackState(track: track, isPlaying: true, syncedPosition: 10, syncedAt: syncedAt)
        #expect(state.position(at: syncedAt) == 10)
        #expect(state.position(at: syncedAt.addingTimeInterval(2.5)) == 12.5)
    }

    @Test func staysFixedWhilePaused() {
        let state = PlaybackState(track: track, isPlaying: false, syncedPosition: 10, syncedAt: syncedAt)
        #expect(state.position(at: syncedAt.addingTimeInterval(30)) == 10)
    }

    @Test func clampsToDuration() {
        let state = PlaybackState(track: track, isPlaying: true, syncedPosition: 195, syncedAt: syncedAt)
        #expect(state.position(at: syncedAt.addingTimeInterval(60)) == 200)
    }

    @Test func neverGoesNegative() {
        let state = PlaybackState(track: track, isPlaying: true, syncedPosition: 1, syncedAt: syncedAt)
        #expect(state.position(at: syncedAt.addingTimeInterval(-5)) == 0)
    }

    @Test func interpolatesWithoutTrack() {
        let state = PlaybackState(track: nil, isPlaying: true, syncedPosition: 1, syncedAt: syncedAt)
        #expect(state.position(at: syncedAt.addingTimeInterval(1)) == 2)
    }

    @Test func trackIdentityIgnoresDuration() {
        var refined = track
        refined.duration = 200.027
        #expect(refined != track)
        #expect(refined.isSameTrack(as: track))
        #expect(!track.isSameTrack(as: TrackInfo(id: "spotify:track:xyz", title: "Song", artist: "Artist", duration: 200)))
        #expect(!track.isSameTrack(as: nil))
    }
}
