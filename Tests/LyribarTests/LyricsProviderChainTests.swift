import Foundation
import Testing

@testable import Lyribar

private enum ChainError: Error, Equatable {
    case first
    case second
}

private actor StubProvider: LyricsProvider {
    enum Outcome: Sendable {
        case found(String)
        case missing
        case failing(ChainError)
        case cancelled
    }

    private let outcome: Outcome
    private(set) var callCount = 0

    init(_ outcome: Outcome) { self.outcome = outcome }

    func fetch(_ track: TrackInfo) async throws -> FetchedLyrics? {
        callCount += 1
        switch outcome {
        case .found(let source):
            return FetchedLyrics(lyrics: SyncedLyrics(lines: [LyricLine(time: 1, text: source)]), source: source)
        case .missing:
            return nil
        case .failing(let error):
            throw error
        case .cancelled:
            throw CancellationError()
        }
    }
}

/// Cancels the task running the chain and then reports a miss, so the chain reaches its
/// cancellation check with the task already cancelled.
private actor CancellingProvider: LyricsProvider {
    private var task: Task<FetchedLyrics?, Error>?

    func use(_ task: Task<FetchedLyrics?, Error>) { self.task = task }

    func fetch(_ track: TrackInfo) async throws -> FetchedLyrics? {
        // Time-based: the test hands over the task only after the chain has started.
        let deadline = ContinuousClock.now + .seconds(5)
        while task == nil, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(1))
        }
        task?.cancel()
        return nil
    }
}

struct LyricsProviderChainTests {
    private let track = TrackInfo(
        id: "spotify:track:abc", title: "Song Name", artist: "The Artist", duration: 222.0)

    @Test func firstHitSkipsTheRest() async throws {
        let first = StubProvider(.found("first"))
        let second = StubProvider(.found("second"))
        let chain = LyricsProviderChain(providers: [first, second])

        let fetched = try await chain.fetch(track)

        #expect(fetched?.source == "first")
        #expect(await second.callCount == 0)
    }

    @Test func missFallsThroughToTheNext() async throws {
        let first = StubProvider(.missing)
        let second = StubProvider(.found("second"))
        let chain = LyricsProviderChain(providers: [first, second])

        let fetched = try await chain.fetch(track)

        #expect(fetched?.source == "second")
        #expect(await first.callCount == 1)
    }

    @Test func failureFallsThroughToTheNext() async throws {
        let first = StubProvider(.failing(.first))
        let second = StubProvider(.found("second"))
        let chain = LyricsProviderChain(providers: [first, second])

        let fetched = try await chain.fetch(track)

        #expect(fetched?.source == "second")
    }

    // A source that is down must not be hidden behind the miss of the next one: the resolver needs
    // the failure to schedule its retry.
    @Test func failureIsReportedWhenTheNextOneMisses() async throws {
        let chain = LyricsProviderChain(providers: [
            StubProvider(.failing(.first)), StubProvider(.missing),
        ])

        await #expect(throws: ChainError.first) {
            _ = try await chain.fetch(self.track)
        }
    }

    @Test func firstFailureWinsWhenAllFail() async throws {
        let chain = LyricsProviderChain(providers: [
            StubProvider(.failing(.first)), StubProvider(.failing(.second)),
        ])

        await #expect(throws: ChainError.first) {
            _ = try await chain.fetch(self.track)
        }
    }

    @Test func allMissesReturnNil() async throws {
        let chain = LyricsProviderChain(providers: [StubProvider(.missing), StubProvider(.missing)])

        #expect(try await chain.fetch(track) == nil)
    }

    @Test func noProvidersReturnNil() async throws {
        let chain = LyricsProviderChain(providers: [])

        #expect(try await chain.fetch(track) == nil)
    }

    @Test func cancellationErrorStopsTheChain() async throws {
        let second = StubProvider(.found("second"))
        let chain = LyricsProviderChain(providers: [StubProvider(.cancelled), second])

        await #expect(throws: CancellationError.self) {
            _ = try await chain.fetch(self.track)
        }
        #expect(await second.callCount == 0)
    }

    @Test func cancelledTaskStopsBeforeTheNextProvider() async throws {
        let first = CancellingProvider()
        let second = StubProvider(.found("second"))
        let chain = LyricsProviderChain(providers: [first, second])

        let track = track
        let task = Task { try await chain.fetch(track) }
        await first.use(task)

        await #expect(throws: CancellationError.self) {
            _ = try await task.value
        }
        #expect(await second.callCount == 0)
    }
}
