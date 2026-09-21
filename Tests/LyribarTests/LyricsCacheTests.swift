import Foundation
import Testing

@testable import Lyribar

struct LyricsCacheTests {
    private let track = TrackInfo(
        id: "spotify:track:abc", title: "Song Name", artist: "The Artist", duration: 222.0)
    private let lyrics = SyncedLyrics(lines: [
        LyricLine(time: 1, text: "First"),
        LyricLine(time: 2, text: "Second"),
    ])

    /// Each test gets its own directory, one level below a directory that does not exist yet.
    private func withCache(_ body: (LyricsCache) throws -> Void) throws {
        let root = URL.temporaryDirectory.appending(path: "lyribar-tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try body(LyricsCache(directory: root.appending(path: "lyrics")))
    }

    @Test func defaultDirectoryIsUnderCaches() {
        let components = Array(LyricsCache.defaultDirectory.pathComponents.suffix(3))
        #expect(components == ["Caches", "com.todesking.lyribar", "lyrics"])
    }

    @Test func setThenGetRoundTrip() throws {
        try withCache { cache in
            cache.set(track, lyrics: lyrics, source: LRCLibProvider.source)
            #expect(cache.get(track)?.lyrics.lines == lyrics.lines)
        }
    }

    @Test func getReturnsTheStoredSource() throws {
        try withCache { cache in
            cache.set(track, lyrics: lyrics, source: "spotify")
            #expect(cache.get(track)?.source == "spotify")
        }
    }

    @Test func setCreatesMissingDirectory() throws {
        try withCache { cache in
            #expect(!FileManager.default.fileExists(atPath: cache.directory.path))
            cache.set(track, lyrics: lyrics, source: LRCLibProvider.source)
            #expect(FileManager.default.fileExists(atPath: cache.fileURL(for: track).path))
        }
    }

    @Test func unknownTrackIsNil() throws {
        try withCache { cache in
            #expect(cache.get(track) == nil)
            cache.set(track, lyrics: lyrics, source: LRCLibProvider.source)
            let other = TrackInfo(id: "spotify:track:xyz", title: "Other", artist: "Nobody", duration: 100)
            #expect(cache.get(other) == nil)
        }
    }

    @Test func clearRemovesEntries() throws {
        try withCache { cache in
            cache.set(track, lyrics: lyrics, source: LRCLibProvider.source)
            #expect(cache.totalSize() > 0)
            cache.clear()
            #expect(cache.get(track) == nil)
            #expect(cache.totalSize() == 0)
        }
    }

    @Test func totalSizeIsZeroWithoutDirectory() throws {
        try withCache { cache in
            #expect(cache.totalSize() == 0)
            cache.clear()  // must not throw or crash when the directory is missing
        }
    }

    @Test func storedEntryKeepsMetadata() throws {
        try withCache { cache in
            let fetchedAt = Date(timeIntervalSince1970: 1_700_000_000)
            cache.set(track, lyrics: lyrics, source: "lrclib", fetchedAt: fetchedAt)
            let data = try Data(contentsOf: cache.fileURL(for: track))
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let entry = try decoder.decode(CacheEntry.self, from: data)
            #expect(entry.trackID == track.id)
            #expect(entry.artist == track.artist)
            #expect(entry.title == track.title)
            #expect(entry.duration == track.duration)
            #expect(entry.source == "lrclib")
            #expect(entry.fetchedAt == fetchedAt)
            #expect(entry.lines == lyrics.lines)
        }
    }

    // Spotify reports a provisional duration right after a track change; the key must not
    // depend on it, since it settles to a slightly different value for the same track.
    @Test func keyIsSameForSameIdDespiteDurationDrift() throws {
        var provisional = track
        provisional.duration = 221.4
        var settled = track
        settled.duration = 221.6
        #expect(LyricsCache.key(for: provisional) == LyricsCache.key(for: settled))
        #expect(LyricsCache.key(for: provisional).count == 64)

        try withCache { cache in
            cache.set(provisional, lyrics: lyrics, source: LRCLibProvider.source)
            #expect(cache.get(settled)?.lyrics.lines == lyrics.lines)
        }
    }

    // Same artist/title/duration but a different id (e.g. explicit vs. clean, a re-recording)
    // must not share a cache entry.
    @Test func keyDiffersForDifferentIdDespiteSameArtistTitleDuration() throws {
        var otherID = track
        otherID.id = "spotify:track:other"
        #expect(LyricsCache.key(for: otherID) != LyricsCache.key(for: track))

        try withCache { cache in
            cache.set(track, lyrics: lyrics, source: LRCLibProvider.source)
            #expect(cache.get(otherID) == nil)
        }
    }
}
