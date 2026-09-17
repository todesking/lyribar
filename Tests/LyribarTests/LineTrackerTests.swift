import Foundation
import Testing

@testable import Lyribar

struct LineTrackerTests {
    let lyrics = SyncedLyrics(lines: [
        LyricLine(time: 10.0, text: "First"),
        LyricLine(time: 20.0, text: "Second"),
        LyricLine(time: 30.0, text: "Third"),
    ])

    @Test func beforeFirstLineReturnsNil() {
        #expect(LineTracker.currentIndex(at: 5.0, in: lyrics) == nil)
    }

    @Test func exactBoundaryMatchesThatLine() {
        #expect(LineTracker.currentIndex(at: 20.0, in: lyrics) == 1)
    }

    @Test func afterLastLineReturnsLastIndex() {
        #expect(LineTracker.currentIndex(at: 999.0, in: lyrics) == 2)
    }

    @Test func emptyLyricsReturnsNil() {
        #expect(LineTracker.currentIndex(at: 0.0, in: SyncedLyrics(lines: [])) == nil)
    }
}
