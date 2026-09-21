import Foundation
import Observation

/// Resolves the lyrics of the current track: cache first, then the provider.
@MainActor
@Observable
final class LyricsResolver {
    enum Status {
        case idle
        case loading
        case found(SyncedLyrics, source: String)
        case notFound
        case failed(Error)
    }

    private(set) var status: Status = .idle

    @ObservationIgnored private let provider: any LyricsProvider
    @ObservationIgnored private let cache: LyricsCache
    @ObservationIgnored private let retryDelay: Duration
    @ObservationIgnored private let sleep: @Sendable (Duration) async throws -> Void
    @ObservationIgnored private(set) var track: TrackInfo?
    // Exposed so tests can await the in-flight fetch.
    @ObservationIgnored private(set) var fetchTask: Task<Void, Never>?
    // Exposed so tests can await the scheduled retry.
    @ObservationIgnored private(set) var retryTask: Task<Void, Never>?
    @ObservationIgnored private var didRetryCurrentTrack = false

    init(
        provider: any LyricsProvider = LRCLibProvider(),
        cache: LyricsCache = LyricsCache(),
        retryDelay: Duration = .seconds(30),
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.provider = provider
        self.cache = cache
        self.retryDelay = retryDelay
        self.sleep = sleep
    }

    /// Track identity is compared by id: Spotify updates the duration of the track being played,
    /// and that must not cancel an in-flight fetch or trigger a refetch.
    func resolve(track: TrackInfo?) {
        guard let track else {
            cancelAll()
            self.track = nil
            status = .idle
            return
        }
        guard !track.isSameTrack(as: self.track) else { return }
        cancelAll()
        self.track = track
        didRetryCurrentTrack = false
        start(track)
    }

    /// Resolves the current track again. Used by the automatic retry after a failure, and the hook
    /// for retrying by hand. Only the fetch is cancelled: the scheduled retry is the caller.
    func retry() {
        guard let track else { return }
        cancelFetch()
        start(track)
    }

    /// Fetches the current track again without reading the cache, and keeps the cached lyrics
    /// showing until a new result arrives. Used when the conditions of a fetch change, such as a
    /// Spotify cookie being saved or removed.
    ///
    /// A retry scheduled under the old conditions is dropped, and the one automatic retry becomes
    /// available again: the conditions changed, so a failure now is a new one.
    func refetch() {
        guard let track else { return }
        cancelAll()
        didRetryCurrentTrack = false
        start(track, bypassCache: true)
    }

    private func start(_ track: TrackInfo, bypassCache: Bool = false) {
        let cached = cache.get(track)
        if let cached {
            status = .found(cached.lyrics, source: cached.source)
            if !bypassCache { return }
        } else {
            status = .loading
        }
        fetchTask = Task { [provider, cache] in
            do {
                let fetched = try await provider.fetch(track)
                guard !Task.isCancelled, track.isSameTrack(as: self.track) else { return }
                guard let fetched else {
                    // A miss is not cached in v1, and it does not drop lyrics already shown.
                    if cached == nil { status = .notFound }
                    return
                }
                cache.set(track, lyrics: fetched.lyrics, source: fetched.source)
                status = .found(fetched.lyrics, source: fetched.source)
            } catch {
                guard !Task.isCancelled, !(error is CancellationError),
                    track.isSameTrack(as: self.track), cached == nil
                else { return }
                status = .failed(error)
                scheduleRetry(for: track)
            }
        }
    }

    /// One automatic retry per track: a failure that was only a hiccup recovers without waiting for
    /// a track change, while one that persists stops instead of asking LRCLIB forever.
    private func scheduleRetry(for track: TrackInfo) {
        guard !didRetryCurrentTrack else { return }
        didRetryCurrentTrack = true
        retryTask = Task { [sleep, retryDelay] in
            try? await sleep(retryDelay)
            guard !Task.isCancelled, track.isSameTrack(as: self.track) else { return }
            retry()
        }
    }

    private func cancelFetch() {
        fetchTask?.cancel()
        fetchTask = nil
    }

    private func cancelAll() {
        cancelFetch()
        retryTask?.cancel()
        retryTask = nil
    }
}
