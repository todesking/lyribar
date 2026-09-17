import Foundation
import Testing
@testable import Lyribar

struct SpotifyScriptTests {
    private let now = Date(timeIntervalSince1970: 1_000)

    private func output(_ fields: [String]) -> String {
        fields.joined(separator: SpotifyScript.separator)
    }

    @Test func parsesPlayingTrack() {
        let state = SpotifyScript.parse(
            output(["playing", "spotify:track:abc", "Song", "Artist", "354000", "12.5"]), now: now)
        #expect(
            state
                == PlaybackState(
                    track: TrackInfo(id: "spotify:track:abc", title: "Song", artist: "Artist", duration: 354),
                    isPlaying: true, syncedPosition: 12.5, syncedAt: now))
    }

    @Test func parsesPausedTrackWithCommaDecimal() {
        let state = SpotifyScript.parse(
            output(["paused", "spotify:track:abc", "Song", "Artist", "354000", "12,5"]), now: now)
        #expect(state?.isPlaying == false)
        #expect(state?.syncedPosition == 12.5)
    }

    @Test func stoppedHasNoTrack() {
        #expect(SpotifyScript.parse("stopped", now: now) == .empty(at: now))
    }

    @Test func malformedOutputIsNil() {
        #expect(SpotifyScript.parse("", now: now) == nil)
        #expect(SpotifyScript.parse(output(["playing", "id", "Song"]), now: now) == nil)
        #expect(SpotifyScript.parse(output(["playing", "id", "Song", "Artist", "x", "1"]), now: now) == nil)
        #expect(SpotifyScript.parse(output(["weird", "id", "Song", "Artist", "1000", "1"]), now: now) == nil)
    }
}
