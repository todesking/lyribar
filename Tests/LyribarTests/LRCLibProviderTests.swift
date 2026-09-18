import Foundation
import Testing

@testable import Lyribar

/// Records the backoff waits instead of performing them, so retry tests take no real time.
private actor SleepRecorder {
    private(set) var delays: [Duration] = []

    nonisolated var sleep: @Sendable (Duration) async throws -> Void {
        { await self.record($0) }
    }

    private func record(_ delay: Duration) { delays.append(delay) }
}

// Serialized: StubURLProtocol keeps its handler in global state.
@Suite(.serialized)
struct LRCLibProviderTests {
    private let track = TrackInfo(
        id: "spotify:track:abc", title: "Song Name", artist: "The Artist", duration: 222.6)

    private func provider(
        retryPolicy: LRCLibProvider.RetryPolicy = .none,
        sleep: SleepRecorder = SleepRecorder(),
        _ handler: @escaping StubURLProtocol.Handler
    ) -> LRCLibProvider {
        LRCLibProvider(
            session: StubURLProtocol.session(handler), userAgent: "Lyribar/test (unit)",
            retryPolicy: retryPolicy, sleep: sleep.sleep)
    }

    private func provider(
        retryPolicy: LRCLibProvider.RetryPolicy = .none,
        sleep: SleepRecorder = SleepRecorder(),
        outcomes handler: @escaping StubURLProtocol.OutcomeHandler
    ) -> LRCLibProvider {
        LRCLibProvider(
            session: StubURLProtocol.session(outcomes: handler), userAgent: "Lyribar/test (unit)",
            retryPolicy: retryPolicy, sleep: sleep.sleep)
    }

    private func body(_ json: String) -> Data { Data(json.utf8) }

    // The body LRCLIB really returns for a miss (checked against the live API, 2026-09-18).
    private var trackNotFound: Data {
        body(#"{"message":"Failed to find specified track","name":"TrackNotFound","statusCode":404}"#)
    }

    // LRCLIB really does answer 503 like this when its database is busy.
    private var serverOverloaded: Data {
        body(
            #"{"message":"The server is busy, please retry in a moment","name":"ServerOverloaded","statusCode":503}"#
        )
    }

    @Test func getHitReturnsSyncedLyrics() async throws {
        let provider = provider { _ in
            (200, self.body(#"{"syncedLyrics":"[00:12.00]Hello","plainLyrics":"Hello"}"#))
        }

        let fetched = try await provider.fetch(track)

        #expect(fetched?.lyrics.lines == [LyricLine(time: 12, text: "Hello")])
        #expect(fetched?.source == LRCLibProvider.source)
        let requests = StubURLProtocol.recordedRequests
        #expect(requests.count == 1)
        let url = try #require(requests.first?.url)
        #expect(url.host() == "lrclib.net")
        #expect(url.path == "/api/get")
        let query = try #require(url.query)
        #expect(query.contains("track_name=Song%20Name"))
        #expect(query.contains("artist_name=The%20Artist"))
        // 222.6s rounds to 223.
        #expect(query.contains("duration=223"))
    }

    @Test func getHitWithoutSyncedLyricsReturnsNil() async throws {
        let provider = provider { _ in
            (200, self.body(#"{"syncedLyrics":null,"plainLyrics":"Hello","instrumental":false}"#))
        }

        let fetched = try await provider.fetch(track)

        #expect(fetched == nil)
        #expect(StubURLProtocol.recordedRequests.count == 1)
    }

    @Test func getMissFallsBackToSearch() async throws {
        let provider = provider { request in
            if request.url?.path == "/api/get" {
                return (404, self.trackNotFound)
            }
            return (
                200,
                self.body(
                    #"""
                    [{"syncedLyrics":null,"plainLyrics":"No timing"},
                     {"syncedLyrics":"[00:05.00]Second"},
                     {"syncedLyrics":"[00:07.00]Third"}]
                    """#)
            )
        }

        let fetched = try await provider.fetch(track)

        #expect(fetched?.lyrics.lines == [LyricLine(time: 5, text: "Second")])
        let requests = StubURLProtocol.recordedRequests
        #expect(requests.count == 2)
        let url = try #require(requests.last?.url)
        #expect(url.path == "/api/search")
        let query = try #require(url.query)
        #expect(query.contains("track_name=Song%20Name"))
        #expect(query.contains("artist_name=The%20Artist"))
        #expect(!query.contains("duration"))
    }

    @Test func bothMissReturnNil() async throws {
        let provider = provider { request in
            if request.url?.path == "/api/get" { return (404, self.trackNotFound) }
            return (200, self.body("[]"))
        }

        #expect(try await provider.fetch(track) == nil)
        #expect(StubURLProtocol.recordedRequests.count == 2)
    }

    @Test func searchWithoutAnySyncedLyricsReturnsNil() async throws {
        let provider = provider { request in
            if request.url?.path == "/api/get" { return (404, self.trackNotFound) }
            return (200, self.body(#"[{"syncedLyrics":null},{"plainLyrics":"No timing"}]"#))
        }

        #expect(try await provider.fetch(track) == nil)
    }

    @Test func serverErrorOnGetThrows() async throws {
        let provider = provider { _ in (500, self.body("oops")) }

        await #expect(throws: LRCLibError.unexpectedStatus(500)) {
            _ = try await provider.fetch(self.track)
        }
    }

    @Test func serverErrorOnSearchThrows() async throws {
        let provider = provider { request in
            if request.url?.path == "/api/get" { return (404, self.trackNotFound) }
            return (503, self.serverOverloaded)
        }

        await #expect(throws: LRCLibError.unexpectedStatus(503)) {
            _ = try await provider.fetch(self.track)
        }
    }

    @Test func serverErrorIsRetriedThenSucceeds() async throws {
        let sleep = SleepRecorder()
        let provider = provider(retryPolicy: .default, sleep: sleep) { _ in
            // The request being served is already recorded, so the count is the attempt number.
            if StubURLProtocol.recordedRequests.count == 1 { return (503, self.serverOverloaded) }
            return (200, self.body(#"{"syncedLyrics":"[00:12.00]Hello"}"#))
        }

        let fetched = try await provider.fetch(track)

        #expect(fetched?.lyrics.lines == [LyricLine(time: 12, text: "Hello")])
        #expect(StubURLProtocol.recordedRequests.count == 2)
        #expect(await sleep.delays == [.milliseconds(500)])
    }

    // A 5xx that never clears must not be retried forever.
    @Test func persistentServerErrorGivesUpAfterBoundedRetries() async throws {
        let sleep = SleepRecorder()
        let provider = provider(retryPolicy: .default, sleep: sleep) { _ in
            (503, self.serverOverloaded)
        }

        await #expect(throws: LRCLibError.unexpectedStatus(503)) {
            _ = try await provider.fetch(self.track)
        }

        // The first attempt plus three retries, and no more.
        #expect(StubURLProtocol.recordedRequests.count == 4)
        #expect(await sleep.delays == [.milliseconds(500), .seconds(1), .seconds(2)])
    }

    @Test func serverErrorOnSearchIsRetried() async throws {
        let provider = provider(retryPolicy: .default) { request in
            if request.url?.path == "/api/get" { return (404, self.trackNotFound) }
            if StubURLProtocol.recordedRequests.count == 2 { return (503, self.serverOverloaded) }
            return (200, self.body(#"[{"syncedLyrics":"[00:05.00]Second"}]"#))
        }

        let fetched = try await provider.fetch(track)

        #expect(fetched?.lyrics.lines == [LyricLine(time: 5, text: "Second")])
        #expect(StubURLProtocol.recordedRequests.count == 3)
    }

    @Test func transportErrorIsRetriedThenSucceeds() async throws {
        let sleep = SleepRecorder()
        let provider = provider(retryPolicy: .default, sleep: sleep, outcomes: { _ in
            if StubURLProtocol.recordedRequests.count == 1 { return .failure(URLError(.timedOut)) }
            return .response(status: 200, body: self.body(#"{"syncedLyrics":"[00:12.00]Hello"}"#))
        })

        let fetched = try await provider.fetch(track)

        #expect(fetched?.lyrics.lines == [LyricLine(time: 12, text: "Hello")])
        #expect(StubURLProtocol.recordedRequests.count == 2)
        #expect(await sleep.delays == [.milliseconds(500)])
    }

    @Test func persistentTransportErrorGivesUpAfterBoundedRetries() async throws {
        let provider = provider(retryPolicy: .default, outcomes: { _ in
            .failure(URLError(.networkConnectionLost))
        })

        await #expect(throws: URLError.self) {
            _ = try await provider.fetch(self.track)
        }

        #expect(StubURLProtocol.recordedRequests.count == 4)
    }

    // Backing off would not help, and hammering a rate limiter is exactly what it asks against.
    @Test func rateLimitIsNotRetried() async throws {
        let sleep = SleepRecorder()
        let provider = provider(retryPolicy: .default, sleep: sleep) { _ in
            (429, self.body(#"{"message":"Too many requests","statusCode":429}"#))
        }

        await #expect(throws: LRCLibError.unexpectedStatus(429)) {
            _ = try await provider.fetch(self.track)
        }

        #expect(StubURLProtocol.recordedRequests.count == 1)
        #expect(await sleep.delays.isEmpty)
    }

    @Test func requestCarriesUserAgent() async throws {
        let session = StubURLProtocol.session { _ in (200, self.body(#"{"syncedLyrics":"[00:01.00]Hi"}"#)) }
        let provider = LRCLibProvider(session: session, userAgent: "Lyribar/1.2.3 (https://example.com)")

        _ = try await provider.fetch(track)

        let header = StubURLProtocol.recordedRequests.first?.value(forHTTPHeaderField: "User-Agent")
        #expect(header == "Lyribar/1.2.3 (https://example.com)")
    }

    @Test func defaultUserAgentFormat() {
        let agent = LRCLibProvider.defaultUserAgent
        #expect(agent.hasPrefix("Lyribar/"))
        #expect(agent.hasSuffix(" (https://github.com/todesking/lyribar)"))
    }
}
