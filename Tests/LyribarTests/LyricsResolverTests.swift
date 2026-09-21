import Foundation
import Testing

@testable import Lyribar

private enum FakeError: Error { case boom }

/// The automatic retry fires at once; the wait itself is covered with a `SleepGate`.
private let instantSleep: @Sendable (Duration) async throws -> Void = { _ in }

private actor RecordingProvider: LyricsProvider {
    enum Outcome: Sendable {
        case found(SyncedLyrics)
        case missing
        case failing
    }

    private var outcomes: [Outcome]
    private let source: String
    private(set) var requested: [String] = []

    init(_ outcome: Outcome, source: String = "test") {
        outcomes = [outcome]
        self.source = source
    }

    /// The last outcome repeats once the script runs out.
    init(_ outcomes: [Outcome], source: String = "test") {
        precondition(!outcomes.isEmpty)
        self.outcomes = outcomes
        self.source = source
    }

    func fetch(_ track: TrackInfo) async throws -> FetchedLyrics? {
        requested.append(track.id)
        let outcome = outcomes.count == 1 ? outcomes[0] : outcomes.removeFirst()
        switch outcome {
        case .found(let lyrics): return FetchedLyrics(lyrics: lyrics, source: source)
        case .missing: return nil
        case .failing: throw FakeError.boom
        }
    }
}

/// Fetches suspend until the test completes them, and ignore cancellation, so the resolver's
/// "is this result still for the current track?" check can be exercised directly.
private actor GatedProvider: LyricsProvider {
    private var continuations: [String: CheckedContinuation<FetchedLyrics?, Never>] = [:]
    private var completed: [String: FetchedLyrics?] = [:]
    private(set) var requested: [String] = []

    func fetch(_ track: TrackInfo) async throws -> FetchedLyrics? {
        requested.append(track.id)
        return await withCheckedContinuation { continuation in
            if let result = completed.removeValue(forKey: track.id) {
                continuation.resume(returning: result)
            } else {
                continuations[track.id] = continuation
            }
        }
    }

    func complete(_ id: String, with lyrics: SyncedLyrics?, source: String = "test") {
        let fetched = lyrics.map { FetchedLyrics(lyrics: $0, source: source) }
        if let continuation = continuations.removeValue(forKey: id) {
            continuation.resume(returning: fetched)
        } else {
            completed[id] = fetched
        }
    }

    func waitForRequest(_ id: String) async -> Bool {
        // Time-based: the fetch starts on the main actor, which other suites may keep busy.
        let deadline = ContinuousClock.now + .seconds(5)
        while ContinuousClock.now < deadline {
            if requested.contains(id) { return true }
            try? await Task.sleep(for: .milliseconds(1))
        }
        return requested.contains(id)
    }
}

/// Stands in for the wait before the automatic retry: the test decides when it ends, so no real
/// time passes.
private actor SleepGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var released = false
    private(set) var requested: [Duration] = []

    nonisolated var sleep: @Sendable (Duration) async throws -> Void {
        { await self.wait($0) }
    }

    private func wait(_ duration: Duration) async {
        requested.append(duration)
        await withCheckedContinuation { continuation in
            if released {
                released = false
                continuation.resume()
            } else {
                self.continuation = continuation
            }
        }
    }

    func release() {
        if let continuation {
            self.continuation = nil
            continuation.resume()
        } else {
            released = true
        }
    }

    func waitForSleep() async -> Bool {
        // Time-based: the retry is scheduled on the main actor, which other suites may keep busy.
        let deadline = ContinuousClock.now + .seconds(5)
        while ContinuousClock.now < deadline {
            if !requested.isEmpty { return true }
            try? await Task.sleep(for: .milliseconds(1))
        }
        return !requested.isEmpty
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
        let resolver = LyricsResolver(provider: RecordingProvider(.missing), cache: cache)

        resolver.resolve(track: nil)

        #expect(resolver.status.isIdle)
        #expect(resolver.fetchTask == nil)
    }

    @Test func cacheHitSkipsProvider() async {
        let cache = makeCache()
        defer { remove(cache) }
        cache.set(trackA, lyrics: lyricsA, source: "lrclib")
        let provider = RecordingProvider(.found(lyricsB))
        let resolver = LyricsResolver(provider: provider, cache: cache)

        resolver.resolve(track: trackA)

        #expect(resolver.status.foundLines == lyricsA.lines)
        #expect(resolver.status.foundSource == "lrclib")
        #expect(resolver.fetchTask == nil)
        #expect(await provider.requested.isEmpty)
    }

    @Test func cacheHitReportsTheStoredSource() async {
        let cache = makeCache()
        defer { remove(cache) }
        cache.set(trackA, lyrics: lyricsA, source: "spotify")
        let resolver = LyricsResolver(
            provider: RecordingProvider(.found(lyricsB), source: "lrclib"), cache: cache)

        resolver.resolve(track: trackA)

        #expect(resolver.status.foundSource == "spotify")
    }

    @Test func fetchedSourceIsReportedAndCached() async {
        let cache = makeCache()
        defer { remove(cache) }
        let resolver = LyricsResolver(
            provider: RecordingProvider(.found(lyricsA), source: "spotify"), cache: cache)

        resolver.resolve(track: trackA)
        await resolver.fetchTask?.value

        #expect(resolver.status.foundSource == "spotify")
        #expect(cache.get(trackA)?.source == "spotify")
    }

    @Test func providerResultIsStoredInCache() async {
        let cache = makeCache()
        defer { remove(cache) }
        let resolver = LyricsResolver(
            provider: RecordingProvider(.found(lyricsA)), cache: cache)

        resolver.resolve(track: trackA)
        #expect(resolver.status.isLoading)
        await resolver.fetchTask?.value

        #expect(resolver.status.foundLines == lyricsA.lines)
        #expect(cache.get(trackA)?.lyrics.lines == lyricsA.lines)
    }

    @Test func missIsReportedAndNotCached() async {
        let cache = makeCache()
        defer { remove(cache) }
        let resolver = LyricsResolver(provider: RecordingProvider(.missing), cache: cache)

        resolver.resolve(track: trackA)
        await resolver.fetchTask?.value

        #expect(resolver.status.isNotFound)
        #expect(cache.get(trackA) == nil)
        #expect(cache.totalSize() == 0)
    }

    @Test func failureIsReported() async {
        let cache = makeCache()
        defer { remove(cache) }
        let resolver = LyricsResolver(provider: RecordingProvider(.failing), cache: cache)

        resolver.resolve(track: trackA)
        await resolver.fetchTask?.value

        #expect(resolver.status.failure is FakeError)
        resolver.resolve(track: nil)  // drops the automatic retry this scheduled
    }

    // Spotify revises the duration of the track already playing; that is not a track change.
    @Test func durationUpdateDoesNotRefetch() async {
        let cache = makeCache()
        defer { remove(cache) }
        let provider = RecordingProvider(.found(lyricsA))
        let resolver = LyricsResolver(provider: provider, cache: cache)

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
        let resolver = LyricsResolver(provider: provider, cache: cache)

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
        let resolver = LyricsResolver(provider: provider, cache: cache)

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

    @Test func transientFailureIsRetriedAutomatically() async {
        let cache = makeCache()
        defer { remove(cache) }
        let provider = RecordingProvider([.failing, .found(lyricsA)])
        let resolver = LyricsResolver(
            provider: provider, cache: cache, sleep: instantSleep)

        resolver.resolve(track: trackA)
        // The retry runs as soon as the first attempt fails, so the failed status is transient here.
        await resolver.fetchTask?.value
        await resolver.retryTask?.value
        await resolver.fetchTask?.value

        #expect(resolver.status.foundLines == lyricsA.lines)
        #expect(await provider.requested == ["a", "a"])
    }

    // A failure that keeps failing must not become an endless stream of requests.
    @Test func repeatedFailureIsNotRetriedAgain() async {
        let cache = makeCache()
        defer { remove(cache) }
        let provider = RecordingProvider(.failing)
        let resolver = LyricsResolver(
            provider: provider, cache: cache, sleep: instantSleep)

        resolver.resolve(track: trackA)
        await resolver.fetchTask?.value
        await resolver.retryTask?.value
        await resolver.fetchTask?.value

        #expect(resolver.status.failure is FakeError)
        // Give any further retry that was scheduled the chance to run.
        for _ in 0..<50 { await Task.yield() }
        #expect(await provider.requested == ["a", "a"])
    }

    @Test func retryWaitsForTheRetryDelay() async {
        let cache = makeCache()
        defer { remove(cache) }
        let gate = SleepGate()
        let provider = RecordingProvider([.failing, .found(lyricsA)])
        let resolver = LyricsResolver(
            provider: provider, cache: cache, retryDelay: .seconds(30),
            sleep: gate.sleep)

        resolver.resolve(track: trackA)
        await resolver.fetchTask?.value
        #expect(await gate.waitForSleep())
        #expect(await gate.requested == [.seconds(30)])
        #expect(await provider.requested == ["a"])
        #expect(resolver.status.failure is FakeError)

        await gate.release()
        await resolver.retryTask?.value
        await resolver.fetchTask?.value

        #expect(resolver.status.foundLines == lyricsA.lines)
        #expect(await provider.requested == ["a", "a"])
    }

    @Test func trackChangeCancelsThePendingRetry() async {
        let cache = makeCache()
        defer { remove(cache) }
        let gate = SleepGate()
        let provider = RecordingProvider([.failing, .found(lyricsB)])
        let resolver = LyricsResolver(
            provider: provider, cache: cache, sleep: gate.sleep)

        resolver.resolve(track: trackA)
        await resolver.fetchTask?.value
        #expect(await gate.waitForSleep())

        resolver.resolve(track: trackB)
        #expect(resolver.retryTask == nil)
        await resolver.fetchTask?.value
        await gate.release()  // the cancelled retry gives up instead of fetching "a" again

        #expect(resolver.status.foundLines == lyricsB.lines)
        for _ in 0..<50 { await Task.yield() }
        #expect(await provider.requested == ["a", "b"])
    }

    @Test func retryResolvesTheCurrentTrackAgain() async {
        let cache = makeCache()
        defer { remove(cache) }
        let gate = SleepGate()  // the automatic retry stays parked
        let provider = RecordingProvider([.failing, .found(lyricsA)])
        let resolver = LyricsResolver(
            provider: provider, cache: cache, sleep: gate.sleep)

        resolver.resolve(track: trackA)
        await resolver.fetchTask?.value
        #expect(await gate.waitForSleep())

        resolver.retry()
        await resolver.fetchTask?.value

        #expect(resolver.status.foundLines == lyricsA.lines)
        #expect(await provider.requested == ["a", "a"])
        resolver.resolve(track: nil)
        await gate.release()
    }

    @Test func retryPrefersTheCache() async {
        let cache = makeCache()
        defer { remove(cache) }
        cache.set(trackA, lyrics: lyricsA, source: "lrclib")
        let provider = RecordingProvider(.found(lyricsB), source: "spotify")
        let resolver = LyricsResolver(provider: provider, cache: cache)

        resolver.resolve(track: trackA)
        resolver.retry()

        #expect(resolver.status.foundLines == lyricsA.lines)
        #expect(resolver.status.foundSource == "lrclib")
        #expect(resolver.fetchTask == nil)
        #expect(await provider.requested.isEmpty)
    }

    @Test func refetchReplacesTheCachedLyrics() async {
        let cache = makeCache()
        defer { remove(cache) }
        cache.set(trackA, lyrics: lyricsA, source: "lrclib")
        let provider = RecordingProvider(.found(lyricsB), source: "spotify")
        let resolver = LyricsResolver(provider: provider, cache: cache)

        resolver.resolve(track: trackA)
        resolver.refetch()
        await resolver.fetchTask?.value

        #expect(resolver.status.foundLines == lyricsB.lines)
        #expect(resolver.status.foundSource == "spotify")
        #expect(cache.get(trackA)?.lyrics.lines == lyricsB.lines)
        #expect(cache.get(trackA)?.source == "spotify")
        #expect(await provider.requested == ["a"])
    }

    // The bar must not go blank while the new lyrics are on their way.
    @Test func refetchKeepsTheCachedLyricsWhileFetching() async {
        let cache = makeCache()
        defer { remove(cache) }
        cache.set(trackA, lyrics: lyricsA, source: "lrclib")
        let provider = GatedProvider()
        let resolver = LyricsResolver(provider: provider, cache: cache)

        resolver.resolve(track: trackA)
        resolver.refetch()
        #expect(await provider.waitForRequest("a"))
        #expect(resolver.status.foundLines == lyricsA.lines)
        #expect(resolver.status.foundSource == "lrclib")

        await provider.complete("a", with: lyricsB, source: "spotify")
        await resolver.fetchTask?.value

        #expect(resolver.status.foundLines == lyricsB.lines)
        #expect(resolver.status.foundSource == "spotify")
    }

    @Test func refetchMissKeepsTheCachedLyrics() async {
        let cache = makeCache()
        defer { remove(cache) }
        cache.set(trackA, lyrics: lyricsA, source: "lrclib")
        let resolver = LyricsResolver(provider: RecordingProvider(.missing), cache: cache)

        resolver.resolve(track: trackA)
        resolver.refetch()
        await resolver.fetchTask?.value

        #expect(resolver.status.foundLines == lyricsA.lines)
        #expect(resolver.status.foundSource == "lrclib")
        #expect(cache.get(trackA)?.lyrics.lines == lyricsA.lines)
    }

    @Test func refetchFailureKeepsTheCachedLyrics() async {
        let cache = makeCache()
        defer { remove(cache) }
        cache.set(trackA, lyrics: lyricsA, source: "lrclib")
        let provider = RecordingProvider(.failing)
        let resolver = LyricsResolver(provider: provider, cache: cache, sleep: instantSleep)

        resolver.resolve(track: trackA)
        resolver.refetch()
        await resolver.fetchTask?.value

        #expect(resolver.status.foundLines == lyricsA.lines)
        #expect(cache.get(trackA)?.lyrics.lines == lyricsA.lines)
        // No automatic retry is scheduled: there is nothing broken on screen to recover from.
        #expect(resolver.retryTask == nil)
        for _ in 0..<50 { await Task.yield() }
        #expect(await provider.requested == ["a"])
    }

    // A retry scheduled before the conditions changed must not fire after the refetch.
    @Test func refetchDropsThePendingRetry() async {
        let cache = makeCache()
        defer { remove(cache) }
        let gate = SleepGate()  // the automatic retry stays parked until the test releases it
        let provider = RecordingProvider([.failing, .missing])
        let resolver = LyricsResolver(provider: provider, cache: cache, sleep: gate.sleep)

        resolver.resolve(track: trackA)
        await resolver.fetchTask?.value
        #expect(await gate.waitForSleep())

        resolver.refetch()
        #expect(resolver.retryTask == nil)
        await resolver.fetchTask?.value
        #expect(resolver.status.isNotFound)

        await gate.release()  // the cancelled retry gives up instead of fetching "a" again
        for _ in 0..<50 { await Task.yield() }
        #expect(await provider.requested == ["a", "a"])
    }

    // The conditions changed, so a failure after the refetch earns an automatic retry of its own.
    @Test func refetchFailureSchedulesAnotherRetry() async {
        let cache = makeCache()
        defer { remove(cache) }
        let provider = RecordingProvider(.failing)
        let resolver = LyricsResolver(provider: provider, cache: cache, sleep: instantSleep)

        resolver.resolve(track: trackA)
        await resolver.fetchTask?.value
        await resolver.retryTask?.value
        await resolver.fetchTask?.value
        #expect(await provider.requested == ["a", "a"])  // the one automatic retry is used up

        resolver.refetch()
        await resolver.fetchTask?.value
        await resolver.retryTask?.value
        await resolver.fetchTask?.value

        #expect(resolver.status.failure is FakeError)
        #expect(await provider.requested == ["a", "a", "a", "a"])
        resolver.resolve(track: nil)  // drops anything still scheduled
    }

    // Without a cached entry there is nothing to bypass, so this is the plain retry path.
    @Test func refetchWithoutCacheLoadsLikeRetry() async {
        let cache = makeCache()
        defer { remove(cache) }
        let provider = RecordingProvider([.missing, .found(lyricsA)], source: "spotify")
        let resolver = LyricsResolver(provider: provider, cache: cache)

        resolver.resolve(track: trackA)
        await resolver.fetchTask?.value
        #expect(resolver.status.isNotFound)

        resolver.refetch()
        #expect(resolver.status.isLoading)
        await resolver.fetchTask?.value

        #expect(resolver.status.foundLines == lyricsA.lines)
        #expect(resolver.status.foundSource == "spotify")
        #expect(await provider.requested == ["a", "a"])
    }
}
