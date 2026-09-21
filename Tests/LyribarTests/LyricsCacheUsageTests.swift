import Foundation
import Testing

@testable import Lyribar

@MainActor
struct LyricsCacheUsageTests {
    private let track = TrackInfo(
        id: "spotify:track:abc", title: "Song Name", artist: "The Artist", duration: 222.0)
    private let otherTrack = TrackInfo(
        id: "spotify:track:xyz", title: "Other Song", artist: "Nobody", duration: 100.0)
    private let lyrics = SyncedLyrics(lines: [
        LyricLine(time: 1, text: "First"),
        LyricLine(time: 2, text: "Second"),
    ])

    private func withUsage(_ body: (LyricsCacheUsage, LyricsCache) -> Void) {
        let root = URL.temporaryDirectory.appending(path: "lyribar-usage-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = LyricsCache(directory: root.appending(path: "lyrics"))
        body(LyricsCacheUsage(cache: cache), cache)
    }

    @Test func nothingIsReadBeforeTheFirstRefresh() {
        withUsage { usage, cache in
            cache.set(track, lyrics: lyrics, source: LRCLibProvider.source)
            #expect(usage.bytes == 0)
        }
    }

    @Test func refreshReadsTheCacheSize() {
        withUsage { usage, cache in
            usage.refresh()
            #expect(usage.bytes == 0)

            cache.set(track, lyrics: lyrics, source: LRCLibProvider.source)
            usage.refresh()

            #expect(usage.bytes > 0)
            #expect(usage.bytes == cache.totalSize())
        }
    }

    /// The window is reopened after more tracks were cached: every refresh has to read again.
    @Test func laterRefreshesSeeLaterWrites() {
        withUsage { usage, cache in
            cache.set(track, lyrics: lyrics, source: LRCLibProvider.source)
            usage.refresh()
            let afterFirstWrite = usage.bytes

            cache.set(otherTrack, lyrics: lyrics, source: LRCLibProvider.source)
            usage.refresh()

            #expect(usage.bytes > afterFirstWrite)
            #expect(usage.bytes == cache.totalSize())
        }
    }

    @Test func clearEmptiesTheCacheAndTheReading() {
        withUsage { usage, cache in
            cache.set(track, lyrics: lyrics, source: LRCLibProvider.source)
            usage.refresh()
            #expect(usage.bytes > 0)

            usage.clear()

            #expect(usage.bytes == 0)
            #expect(cache.totalSize() == 0)
            #expect(cache.get(track) == nil)
        }
    }
}
