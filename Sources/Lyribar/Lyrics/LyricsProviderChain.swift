import Foundation

/// Tries its providers in order and returns the first hit. A provider that fails does not end the
/// chain: the first failure is reported only if no later provider has lyrics, so a broken source
/// still falls back to a working one.
struct LyricsProviderChain: LyricsProvider {
    let providers: [any LyricsProvider]

    func fetch(_ track: TrackInfo) async throws -> FetchedLyrics? {
        var firstError: Error?
        for provider in providers {
            try Task.checkCancellation()
            do {
                if let fetched = try await provider.fetch(track) { return fetched }
            } catch let error as CancellationError {
                throw error
            } catch {
                if firstError == nil { firstError = error }
            }
        }
        if let firstError { throw firstError }
        return nil
    }
}
