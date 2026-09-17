import Foundation
import Testing

@testable import Lyribar

private enum FakeError: Error { case boom }

private actor RecordingProvider: LyricsProvider {
    enum Outcome: Sendable {
        case found(SyncedLyrics)
        case missing
        case failing
    }

    private let outcome: Outcome
    private(set) var requested: [String] = []

    init(_ outcome: Outcome) { self.outcome = outcome }

    func fetch(_ track: TrackInfo) async throws -> SyncedLyrics? {
        requested.append(track.id)
        switch outcome {
        case .found(let lyrics): return lyrics
        case .missing: return nil
        case .failing: throw FakeError.boom
        }
    }
}

/// Fetches suspend until the test completes them, and ignore cancellation, so the resolver's
/// "is this result still for the current track?" check can be exercised directly.
private actor GatedProvider: LyricsProvider {
    private var continuations: [String: CheckedContinuation<SyncedLyrics?, Never>] = [:]
    private var completed: [String: SyncedLyrics?] = [:]
    private(set) var requested: [String] = []

    func fetch(_ track: TrackInfo) async throws -> SyncedLyrics? {
        requested.append(track.id)
        return await withCheckedContinuation { continuation in
            if let result = completed.removeValue(forKey: track.id) {
                continuation.resume(returning: result)
            } else {
                continuations[track.id] = continuation
            }
        }
    }

    func complete(_ id: String, with lyrics: SyncedLyrics?) {
        if let continuation = continuations.removeValue(forKey: id) {
            continuation.resume(returning: lyrics)
        } else {
            completed[id] = lyrics
        }
    }

    func waitForRequest(_ id: String) async -> Bool {
        for _ in 0..<10_000 {
            if requested.contains(id) { return true }
            await Task.yield()
        }
        return false
    }
}

extension LyricsResolver.Status {
    fileprivate var foundLines: [LyricLine]? {
        if case .found(let lyrics, _) = self { lyrics.lines } else { nil }
    }
    fileprivate var foundSource: String? {
        if case .found(_, let source) = self { source } else { nil }
    }
    fileprivate var isIdle: Bool { if case .idle = self { true } else { false } }
    fileprivate var isLoading: Bool { if case .loading = self { true } else { false } }
    fileprivate var isNotFound: Bool { if case .notFound = self { true } else { false } }
    fileprivate var failure: Error? { if case .failed(let error) = self { error } else { nil } }
}

@MainActor
struct LyricsResolverTests {
    private let trackA = TrackInfo(id: "a", title: "Song A", artist: "Artist", duration: 100)
    private let trackB = TrackInfo(id: "b", title: "Song B", artist: "Artist", duration: 200)
    private let lyricsA = SyncedLyrics(lines: [LyricLine(time: 1, text: "A one")])
    private let lyricsB = SyncedLyrics(lines: [LyricLine(time: 2, text: "B one")])

    private func makeCache() -> LyricsCache {
        LyricsCache(directory: URL.temporaryDirectory.appending(path: "lyribar-resolver-\(UUID().uuidString)"))
    }

    private func remove(_ cache: LyricsCache) {
        try? FileManager.default.removeItem(at: cache.directory)
    }

    @Test func nilTrackIsIdle() async {
        let cache = makeCache()
        defer { remove(cache) }
        let resolver = LyricsResolver(provider: RecordingProvider(.missing), cache: cache, source: "test")

        resolver.resolve(track: nil)

        #expect(resolver.status.isIdle)
        #expect(resolver.fetchTask == nil)
    }

    @Test func cacheHitSkipsProvider() async {
        let cache = makeCache()
        defer { remove(cache) }
        cache.set(trackA, lyrics: lyricsA, source: "lrclib")
        let provider = RecordingProvider(.found(lyricsB))
        let resolver = LyricsResolver(provider: provider, cache: cache, source: "test")

        resolver.resolve(track: trackA)

        #expect(resolver.status.foundLines == lyricsA.lines)
        #expect(resolver.status.foundSource == "test")
        #expect(resolver.fetchTask == nil)
        #expect(await provider.requested.isEmpty)
    }

    @Test func providerResultIsStoredInCache() async {
        let cache = makeCache()
        defer { remove(cache) }
        let resolver = LyricsResolver(
            provider: RecordingProvider(.found(lyricsA)), cache: cache, source: "test")

        resolver.resolve(track: trackA)
        #expect(resolver.status.isLoading)
        await resolver.fetchTask?.value

        #expect(resolver.status.foundLines == lyricsA.lines)
        #expect(cache.get(trackA)?.lines == lyricsA.lines)
    }

    @Test func missIsReportedAndNotCached() async {
        let cache = makeCache()
        defer { remove(cache) }
        let resolver = LyricsResolver(provider: RecordingProvider(.missing), cache: cache, source: "test")

        resolver.resolve(track: trackA)
        await resolver.fetchTask?.value

        #expect(resolver.status.isNotFound)
        #expect(cache.get(trackA) == nil)
        #expect(cache.totalSize() == 0)
    }

    @Test func failureIsReported() async {
        let cache = makeCache()
        defer { remove(cache) }
        let resolver = LyricsResolver(provider: RecordingProvider(.failing), cache: cache, source: "test")

        resolver.resolve(track: trackA)
        await resolver.fetchTask?.value

        #expect(resolver.status.failure is FakeError)
    }

    // Spotify revises the duration of the track already playing; that is not a track change.
    @Test func durationUpdateDoesNotRefetch() async {
        let cache = makeCache()
        defer { remove(cache) }
        let provider = RecordingProvider(.found(lyricsA))
        let resolver = LyricsResolver(provider: provider, cache: cache, source: "test")

        resolver.resolve(track: trackA)
        await resolver.fetchTask?.value
        var updated = trackA
        updated.duration += 0.027
        resolver.resolve(track: updated)

        #expect(resolver.status.foundLines == lyricsA.lines)
        #expect(await provider.requested == ["a"])
    }

    @Test func durationUpdateDoesNotCancelInFlightFetch() async {
        let cache = makeCache()
        defer { remove(cache) }
        let provider = GatedProvider()
        let resolver = LyricsResolver(provider: provider, cache: cache, source: "test")

        resolver.resolve(track: trackA)
        #expect(await provider.waitForRequest("a"))
        var updated = trackA
        updated.duration += 0.027
        resolver.resolve(track: updated)
        #expect(resolver.status.isLoading)

        await provider.complete("a", with: lyricsA)
        await resolver.fetchTask?.value

        #expect(resolver.status.foundLines == lyricsA.lines)
        #expect(await provider.requested == ["a"])
    }

    @Test func resultForPreviousTrackIsDiscarded() async {
        let cache = makeCache()
        defer { remove(cache) }
        let provider = GatedProvider()
        let resolver = LyricsResolver(provider: provider, cache: cache, source: "test")

        resolver.resolve(track: trackA)
        #expect(await provider.waitForRequest("a"))
        resolver.resolve(track: trackB)
        #expect(await provider.waitForRequest("b"))

        await provider.complete("a", with: lyricsA)
        for _ in 0..<20 { await Task.yield() }
        #expect(resolver.status.isLoading)
        #expect(cache.get(trackA) == nil)

        await provider.complete("b", with: lyricsB)
        await resolver.fetchTask?.value
        #expect(resolver.status.foundLines == lyricsB.lines)
    }
}
