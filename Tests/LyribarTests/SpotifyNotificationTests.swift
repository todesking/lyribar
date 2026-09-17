import Foundation
import Testing
@testable import Lyribar

struct SpotifyNotificationTests {
    private let now = Date(timeIntervalSince1970: 1_000)

    private var fullUserInfo: [AnyHashable: Any] {
        [
            "Track ID": "spotify:track:abc",
            "Name": "Song",
            "Artist": "Artist",
            "Album": "Album",
            "Duration": 354_000,
            "Playback Position": 12.5,
            "Player State": "Playing",
        ]
    }

    @Test func buildsStateFromExpectedKeys() {
        let state = SpotifyNotification.playbackState(from: fullUserInfo, now: now)
        #expect(
            state
                == PlaybackState(
                    track: TrackInfo(id: "spotify:track:abc", title: "Song", artist: "Artist", duration: 354),
                    isPlaying: true, syncedPosition: 12.5, syncedAt: now))
    }

    @Test func pausedIsNotPlaying() {
        var userInfo = fullUserInfo
        userInfo["Player State"] = "Paused"
        #expect(SpotifyNotification.playbackState(from: userInfo, now: now)?.isPlaying == false)
    }

    @Test func stoppedHasNoTrack() {
        let state = SpotifyNotification.playbackState(from: ["Player State": "Stopped"], now: now)
        #expect(state == .empty(at: now))
    }

    @Test(arguments: ["Track ID", "Name", "Artist", "Duration", "Playback Position", "Player State"])
    func missingKeyIsNil(key: String) {
        var userInfo = fullUserInfo
        userInfo[key] = nil
        #expect(SpotifyNotification.playbackState(from: userInfo, now: now) == nil)
    }

    @Test func nilOrUnknownStateIsNil() {
        #expect(SpotifyNotification.playbackState(from: nil, now: now) == nil)
        var userInfo = fullUserInfo
        userInfo["Player State"] = "Buffering"
        #expect(SpotifyNotification.playbackState(from: userInfo, now: now) == nil)
    }
}
