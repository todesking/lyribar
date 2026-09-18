import Foundation
import Testing

@testable import Lyribar

/// Records the backoff waits instead of performing them, so retry tests take no real time.
private actor SleepLog {
    private(set) var delays: [Duration] = []

    nonisolated var sleep: @Sendable (Duration) async throws -> Void {
        { await self.record($0) }
    }

    private func record(_ delay: Duration) { delays.append(delay) }
}

/// Counts how often a handler has been asked, so it can answer a retry differently.
private final class Calls: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    func next() -> Int { lock.withLock { count += 1; return count } }
}

struct SpotifyLyricsProviderTests {
    private static let secretsURL = URL(string: "https://secrets.example/secretDict.json")!
    private static let lyricsHost = "spclient.wg.spotify.com"
    private let credentials = InMemorySpotifyCredentialStore(cookie: "sp-dc-value")
    private let track = TrackInfo(
        id: "spotify:track:4u7EnebtmKWzUH433cf5Qv", title: "Song Name", artist: "The Artist",
        duration: 222.6)

    // The auth hops, in the shapes the live endpoints return (external API survey, 2026-09-18).
    private static let secretsBody = Data(#"{"61":[70,71,72,73,74,75]}"#.utf8)
    private static let serverTimeBody = Data(#"{"serverTime":1789727992}"#.utf8)

    private static func tokenBody(_ token: String, anonymous: Bool = false) -> Data {
        Data(
            """
            {"clientId":"d8a5ed958d274c2e8ee717e6a4b0971d","accessToken":"\(token)",\
            "accessTokenExpirationTimestampMs":4102444800000,"isAnonymous":\(anonymous),\
            "_notes":"Usage of this endpoint is not permitted"}
            """.utf8)
    }

    /// A lyrics response with the keys the app does not read left in place.
    private static func lyricsBody(
        syncType: String = "LINE_SYNCED", lines: [(start: String, words: String)]
    ) -> Data {
        let lines = lines
            .map { line in
                """
                {"startTimeMs":"\(line.start)","words":"\(line.words)","syllables":[],\
                "endTimeMs":"0","transliteratedWords":""}
                """
            }
            .joined(separator: ",")
        return Data(
            """
            {"lyrics":{"syncType":"\(syncType)","lines":[\(lines)],"provider":"syncpower",\
            "providerLyricsId":"2973316","providerDisplayName":"プチリリ","syncLyricsUri":"",\
            "isDenseTypeface":false,"alternatives":[],"language":"","isRtlLanguage":false,\
            "capStatus":"NONE","previewLines":[],"translationLanguages":[],\
            "availableTranslationLanguages":[]},"colors":{"background":-9013642,"text":-16777216,\
            "highlightText":-1},"hasVocalRemoval":false}
            """.utf8)
    }

    /// Answers the three token hops itself and leaves the lyrics request to `lyrics`.
    private static func handler(
        token: @escaping @Sendable () -> Data = { tokenBody("token-1") },
        lyrics: @escaping StubURLProtocol.OutcomeHandler
    ) -> StubURLProtocol.OutcomeHandler {
        { request in
            switch (request.url?.host(), request.url?.path) {
            case ("secrets.example", _):
                return .response(status: 200, body: secretsBody)
            case ("open.spotify.com", "/api/server-time"):
                return .response(status: 200, body: serverTimeBody)
            case ("open.spotify.com", _):
                return .response(status: 200, body: token())
            default:
                return lyrics(request)
            }
        }
    }

    private func provider(
        credentials: any SpotifyCredentialStore,
        retryPolicy: SpotifyLyricsProvider.RetryPolicy = .none,
        sleep: SleepLog = SleepLog(),
        _ handler: @escaping StubURLProtocol.OutcomeHandler
    ) -> (SpotifyLyricsProvider, StubURLProtocol.Stub) {
        let stub = StubURLProtocol.stub(outcomes: handler)
        let tokenProvider = SpotifyTokenProvider(
            session: stub.session, credentials: credentials, secretsURL: Self.secretsURL)
        let provider = SpotifyLyricsProvider(
            session: stub.session, tokenProvider: tokenProvider, retryPolicy: retryPolicy,
            sleep: sleep.sleep)
        return (provider, stub)
    }

    private func provider(
        retryPolicy: SpotifyLyricsProvider.RetryPolicy = .none,
        sleep: SleepLog = SleepLog(),
        _ handler: @escaping StubURLProtocol.OutcomeHandler
    ) -> (SpotifyLyricsProvider, StubURLProtocol.Stub) {
        provider(
            credentials: credentials, retryPolicy: retryPolicy, sleep: sleep, handler)
    }

    /// The lyrics hops only, with the token hops filtered out.
    private func lyricsRequests(_ stub: StubURLProtocol.Stub) -> [URLRequest] {
        stub.requests.filter { $0.url?.host() == Self.lyricsHost }
    }

    private static func serving(_ body: @autoclosure @escaping @Sendable () -> Data)
        -> StubURLProtocol.OutcomeHandler
    {
        handler(lyrics: { _ in .response(status: 200, body: body()) })
    }

    @Test func syncedLyricsBecomeSecondsInTimeOrder() async throws {
        let (provider, stub) = provider(
            Self.serving(
                Self.lyricsBody(lines: [
                    (start: "12500", words: "Second line"),
                    (start: "782", words: "私達 もしかして"),
                    (start: "20000", words: "A chorus"),
                    (start: "20000", words: "sung over it"),
                ])))

        let fetched = try await provider.fetch(track)

        #expect(fetched?.source == "spotify")
        // Lines that share a time keep the order they arrived in.
        #expect(
            fetched?.lyrics.lines == [
                LyricLine(time: 0.782, text: "私達 もしかして"),
                LyricLine(time: 12.5, text: "Second line"),
                LyricLine(time: 20, text: "A chorus"),
                LyricLine(time: 20, text: "sung over it"),
            ])

        let requests = lyricsRequests(stub)
        #expect(requests.count == 1)
        let url = try #require(requests.first?.url)
        #expect(url.host() == Self.lyricsHost)
        #expect(url.path == "/color-lyrics/v2/track/4u7EnebtmKWzUH433cf5Qv")
        let query = try #require(url.query)
        #expect(query.contains("format=json"))
        #expect(query.contains("market=from_token"))
        let request = try #require(requests.first)
        #expect(request.value(forHTTPHeaderField: "App-platform") == "WebPlayer")
        #expect(request.value(forHTTPHeaderField: "authorization") == "Bearer token-1")
        #expect(request.value(forHTTPHeaderField: "User-Agent") == SpotifyWebClient.userAgent)
    }

    @Test func interludesAndBlanksStayAsEmptyLines() async throws {
        let (provider, _) = provider(
            Self.serving(
                Self.lyricsBody(lines: [
                    (start: "1000", words: "  Sung words  "),
                    (start: "2000", words: "♪"),
                    (start: "3000", words: ""),
                    (start: "4000", words: " ♪ "),
                ])))

        let fetched = try await provider.fetch(track)

        #expect(
            fetched?.lyrics.lines == [
                LyricLine(time: 1, text: "Sung words"),
                LyricLine(time: 2, text: ""),
                LyricLine(time: 3, text: ""),
                LyricLine(time: 4, text: ""),
            ])
    }

    @Test func linesWithoutANumericTimeAreDropped() async throws {
        let (provider, _) = provider(
            Self.serving(
                Self.lyricsBody(lines: [
                    (start: "soon", words: "No time"),
                    (start: "1000", words: "Sung words"),
                    (start: "", words: "No time either"),
                ])))

        let fetched = try await provider.fetch(track)

        #expect(fetched?.lyrics.lines == [LyricLine(time: 1, text: "Sung words")])
    }

    @Test func unsyncedLyricsAreNotUsed() async throws {
        let (provider, _) = provider(
            Self.serving(
                Self.lyricsBody(
                    syncType: "UNSYNCED", lines: [(start: "0", words: "Just the words")])))

        #expect(try await provider.fetch(track) == nil)
    }

    @Test func lyricsWithoutAnyWordsAreNotUsed() async throws {
        let (provider, _) = provider(
            Self.serving(
                Self.lyricsBody(lines: [(start: "1000", words: "♪"), (start: "2000", words: "")])))

        #expect(try await provider.fetch(track) == nil)
    }

    @Test func aMissReturnsNil() async throws {
        let (provider, stub) = provider(
            Self.handler(lyrics: { _ in .response(status: 404, body: Data()) }))

        #expect(try await provider.fetch(track) == nil)
        #expect(lyricsRequests(stub).count == 1)
    }

    @Test func withoutACookieNothingIsRequested() async throws {
        let (provider, stub) = provider(
            credentials: InMemorySpotifyCredentialStore(),
            Self.serving(Self.lyricsBody(lines: [(start: "1000", words: "Sung words")])))

        #expect(try await provider.fetch(track) == nil)
        #expect(lyricsRequests(stub).isEmpty)
    }

    @Test func aRejectedCookieIsReported() async throws {
        let (provider, stub) = provider(
            Self.handler(
                token: { Self.tokenBody("anon-token", anonymous: true) },
                lyrics: { _ in
                    .response(
                        status: 200,
                        body: Self.lyricsBody(lines: [(start: "1000", words: "Sung words")]))
                }))

        await #expect(throws: SpotifyAuthError.cookieRejected) {
            _ = try await provider.fetch(self.track)
        }
        #expect(lyricsRequests(stub).isEmpty)
    }

    @Test func aLocalTrackIsNotRequested() async throws {
        let (provider, stub) = provider(
            Self.serving(Self.lyricsBody(lines: [(start: "1000", words: "Sung words")])))
        let local = TrackInfo(
            id: "spotify:local:::Song+Name:223", title: "Song Name", artist: "The Artist",
            duration: 222.6)

        #expect(try await provider.fetch(local) == nil)
        #expect(stub.requests.isEmpty)
    }

    @Test func anExpiredTokenIsReplacedOnce() async throws {
        let tokens = Calls()
        let lyrics = Calls()
        let (provider, stub) = provider(
            Self.handler(
                token: { Self.tokenBody("token-\(tokens.next())") },
                lyrics: { _ in
                    lyrics.next() == 1
                        ? .response(status: 401, body: Data())
                        : .response(
                            status: 200,
                            body: Self.lyricsBody(lines: [(start: "1000", words: "Sung words")]))
                }))

        let fetched = try await provider.fetch(track)

        #expect(fetched?.lyrics.lines == [LyricLine(time: 1, text: "Sung words")])
        let requests = lyricsRequests(stub)
        #expect(requests.count == 2)
        #expect(requests[0].value(forHTTPHeaderField: "authorization") == "Bearer token-1")
        #expect(requests[1].value(forHTTPHeaderField: "authorization") == "Bearer token-2")
    }

    @Test func aTokenThatIsRefusedTwiceIsAnError() async throws {
        let (provider, stub) = provider(
            Self.handler(lyrics: { _ in .response(status: 401, body: Data()) }))

        await #expect(throws: SpotifyLyricsError.unexpectedStatus(401)) {
            _ = try await provider.fetch(self.track)
        }
        #expect(lyricsRequests(stub).count == 2)
    }

    @Test func serverErrorIsRetriedThenSucceeds() async throws {
        let sleep = SleepLog()
        let calls = Calls()
        let (provider, stub) = provider(
            retryPolicy: .default, sleep: sleep,
            Self.handler(lyrics: { _ in
                calls.next() == 1
                    ? .response(status: 503, body: Data())
                    : .response(
                        status: 200,
                        body: Self.lyricsBody(lines: [(start: "1000", words: "Sung words")]))
            }))

        let fetched = try await provider.fetch(track)

        #expect(fetched?.lyrics.lines == [LyricLine(time: 1, text: "Sung words")])
        #expect(lyricsRequests(stub).count == 2)
        #expect(await sleep.delays == [.milliseconds(500)])
    }

    // Backing off would not help, and hammering a rate limiter is exactly what it asks against.
    @Test func rateLimitIsNotRetried() async throws {
        let sleep = SleepLog()
        let (provider, stub) = provider(
            retryPolicy: .default, sleep: sleep,
            Self.handler(lyrics: { _ in .response(status: 429, body: Data()) }))

        await #expect(throws: SpotifyLyricsError.unexpectedStatus(429)) {
            _ = try await provider.fetch(self.track)
        }

        #expect(lyricsRequests(stub).count == 1)
        #expect(await sleep.delays.isEmpty)
    }
}
