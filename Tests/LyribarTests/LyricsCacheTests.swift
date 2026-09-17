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

    @Test func setThenGetRoundTrip() throws {
        try withCache { cache in
            cache.set(track, lyrics: lyrics, source: LRCLibProvider.source)
            #expect(cache.get(track)?.lines == lyrics.lines)
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
            #expect(entry.artist == track.artist)
            #expect(entry.title == track.title)
            #expect(entry.duration == track.duration)
            #expect(entry.source == "lrclib")
            #expect(entry.fetchedAt == fetchedAt)
            #expect(entry.lines == lyrics.lines)
        }
    }

    // Spotify reports a provisional duration right after a track change (222.0 then 222.027).
    @Test func keyRoundsDurationToSeconds() {
        var settled = track
        settled.duration = 222.027
        #expect(LyricsCache.key(for: settled) == LyricsCache.key(for: track))
    }

    @Test func keyDependsOnArtistTitleAndDuration() {
        var longer = track
        longer.duration = 223.6
        var otherTitle = track
        otherTitle.title = "Other Song"
        var otherArtist = track
        otherArtist.artist = "Other Artist"
        let keys = Set([track, longer, otherTitle, otherArtist].map(LyricsCache.key(for:)))
        #expect(keys.count == 4)
        #expect(LyricsCache.key(for: track).count == 64)
    }

    // The separator keeps "A\u{1}B" from colliding with "AB".
    @Test func keySeparatorAvoidsFieldCollisions() {
        var shifted = track
        shifted.artist = track.artist + track.title
        shifted.title = ""
        #expect(LyricsCache.key(for: shifted) != LyricsCache.key(for: track))
    }
}
