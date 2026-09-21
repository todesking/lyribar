import CryptoKit
import Foundation

struct CacheEntry: Codable {
    let trackID: String
    let artist: String
    let title: String
    let duration: TimeInterval
    let source: String
    let fetchedAt: Date
    let lines: [LyricLine]
}

/// One JSON file per track under `~/Library/Caches/com.todesking.lyribar/lyrics/`.
/// Failures are swallowed: a cache miss is always an acceptable outcome.
struct LyricsCache: Sendable {
    static let bundleIdentifier = "com.todesking.lyribar"

    static var defaultDirectory: URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return caches.appending(path: bundleIdentifier, directoryHint: .isDirectory)
            .appending(path: "lyrics", directoryHint: .isDirectory)
    }

    let directory: URL

    init(directory: URL = LyricsCache.defaultDirectory) {
        self.directory = directory
    }

    func get(_ track: TrackInfo) -> FetchedLyrics? {
        guard let data = try? Data(contentsOf: fileURL(for: track)),
            let entry = try? Self.decoder.decode(CacheEntry.self, from: data),
            !entry.lines.isEmpty
        else { return nil }
        return FetchedLyrics(lyrics: SyncedLyrics(lines: entry.lines), source: entry.source)
    }

    func set(_ track: TrackInfo, lyrics: SyncedLyrics, source: String, fetchedAt: Date = Date()) {
        let entry = CacheEntry(
            trackID: track.id, artist: track.artist, title: track.title, duration: track.duration,
            source: source, fetchedAt: fetchedAt, lines: lyrics.lines)
        guard let data = try? Self.encoder.encode(entry) else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: fileURL(for: track), options: .atomic)
    }

    func clear() {
        let manager = FileManager.default
        guard let contents = try? manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        else { return }
        for url in contents {
            try? manager.removeItem(at: url)
        }
    }

    func totalSize() -> Int {
        guard
            let contents = try? FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: [.fileSizeKey])
        else { return 0 }
        return contents.reduce(0) { total, url in
            total + ((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
    }

    func fileURL(for track: TrackInfo) -> URL {
        directory.appending(path: Self.key(for: track) + ".json", directoryHint: .notDirectory)
    }

    // Keyed by track id, not by artist/title/duration: those can collide across distinct tracks
    // (explicit/clean, re-recordings, different languages), and Spotify's provisional duration
    // right after a track change would otherwise split one track across two keys.
    static func key(for track: TrackInfo) -> String {
        SHA256.hash(data: Data(track.id.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
