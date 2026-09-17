import Foundation
import Testing

@testable import Lyribar

// Serialized: StubURLProtocol keeps its handler in global state.
@Suite(.serialized)
struct LRCLibProviderTests {
    private let track = TrackInfo(
        id: "spotify:track:abc", title: "Song Name", artist: "The Artist", duration: 222.6)

    private func provider(_ handler: @escaping StubURLProtocol.Handler) -> LRCLibProvider {
        LRCLibProvider(session: StubURLProtocol.session(handler), userAgent: "Lyribar/test (unit)")
    }

    private func body(_ json: String) -> Data { Data(json.utf8) }

    // The body LRCLIB really returns for a miss (checked against the live API, 2026-09-18).
    private var trackNotFound: Data {
        body(#"{"message":"Failed to find specified track","name":"TrackNotFound","statusCode":404}"#)
    }

    @Test func getHitReturnsSyncedLyrics() async throws {
        let provider = provider { _ in
            (200, self.body(#"{"syncedLyrics":"[00:12.00]Hello","plainLyrics":"Hello"}"#))
        }

        let lyrics = try await provider.fetch(track)

        #expect(lyrics?.lines == [LyricLine(time: 12, text: "Hello")])
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

        let lyrics = try await provider.fetch(track)

        #expect(lyrics == nil)
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

        let lyrics = try await provider.fetch(track)

        #expect(lyrics?.lines == [LyricLine(time: 5, text: "Second")])
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
            // LRCLIB really does answer 503 like this when its database is busy.
            return (
                503,
                self.body(
                    #"{"message":"The server is busy, please retry in a moment","name":"ServerOverloaded","statusCode":503}"#
                )
            )
        }

        await #expect(throws: LRCLibError.unexpectedStatus(503)) {
            _ = try await provider.fetch(self.track)
        }
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
