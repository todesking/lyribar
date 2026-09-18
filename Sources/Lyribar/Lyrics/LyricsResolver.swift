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
    @ObservationIgnored private let source: String
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
        source: String = LRCLibProvider.source,
        retryDelay: Duration = .seconds(30),
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.provider = provider
        self.cache = cache
        self.source = source
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
    /// for retrying by hand.
    func retry() {
        guard let track else { return }
        cancelFetch()
        start(track)
    }

    private func start(_ track: TrackInfo) {
        if let cached = cache.get(track) {
            status = .found(cached, source: source)
            return
        }
        status = .loading
        fetchTask = Task { [provider, cache, source] in
            do {
                let lyrics = try await provider.fetch(track)
                guard !Task.isCancelled, track.isSameTrack(as: self.track) else { return }
                guard let lyrics else {
                    // A miss is not cached in v1.
                    status = .notFound
                    return
                }
                cache.set(track, lyrics: lyrics, source: source)
                status = .found(lyrics, source: source)
            } catch {
                guard !Task.isCancelled, !(error is CancellationError),
                    track.isSameTrack(as: self.track)
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
