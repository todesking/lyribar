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
    @ObservationIgnored private(set) var track: TrackInfo?
    // Exposed so tests can await the in-flight fetch.
    @ObservationIgnored private(set) var fetchTask: Task<Void, Never>?

    init(
        provider: any LyricsProvider = LRCLibProvider(),
        cache: LyricsCache = LyricsCache(),
        source: String = LRCLibProvider.source
    ) {
        self.provider = provider
        self.cache = cache
        self.source = source
    }

    /// Track identity is compared by id: Spotify updates the duration of the track being played,
    /// and that must not cancel an in-flight fetch or trigger a refetch.
    func resolve(track: TrackInfo?) {
        guard let track else {
            cancel()
            self.track = nil
            status = .idle
            return
        }
        guard !track.isSameTrack(as: self.track) else { return }
        cancel()
        self.track = track

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
            }
        }
    }

    private func cancel() {
        fetchTask?.cancel()
        fetchTask = nil
    }
}
