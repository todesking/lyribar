import Foundation
import Testing

@testable import Lyribar

/// A clock the test moves by hand, so token expiry needs no real waiting.
private final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var date: Date

    init(_ date: Date) { self.date = date }

    var now: @Sendable () -> Date { { self.lock.withLock { self.date } } }

    func advance(by seconds: TimeInterval) {
        lock.withLock { date += seconds }
    }
}

struct SpotifyTokenProviderTests {
    private static let secretsURL = URL(string: "https://secrets.example/secretDict.json")!
    private static let cookie = "sp-dc-value"
    // The clock of the fixtures below. The local clock is skewed against Spotify's on purpose, far
    // enough to land in another TOTP step, so using the wrong one shows up in the code.
    private static let serverTime = 1_789_727_992
    private static let clientTime = serverTime - 137
    private static let expirationMs: Double = 1_789_741_968_959
    private static let secret = [70, 71, 72, 73, 74, 75]

    private let clock = TestClock(Date(timeIntervalSince1970: TimeInterval(clientTime)))
    private let credentials = InMemorySpotifyCredentialStore(cookie: cookie)

    // Shapes taken from the live endpoints (external API survey, 2026-09-18).
    private static let secretsBody = Data(#"{"60":[1,2,3],"61":[70,71,72,73,74,75]}"#.utf8)
    private static let serverTimeBody = Data(#"{"serverTime":1789727992}"#.utf8)

    private static func tokenBody(_ token: String, anonymous: Bool = false) -> Data {
        Data(
            """
            {"clientId":"d8a5ed958d274c2e8ee717e6a4b0971d","accessToken":"\(token)",\
            "accessTokenExpirationTimestampMs":1789741968959,"isAnonymous":\(anonymous),\
            "_notes":"Usage of this endpoint is not permitted"}
            """.utf8)
    }

    /// Serves the three hops of the happy path, with per-step overrides for the failure tests.
    private static func handler(
        secrets: (status: Int, body: Data) = (200, secretsBody),
        serverTime: (status: Int, body: Data) = (200, serverTimeBody),
        token: @escaping @Sendable (URLRequest) -> (status: Int, body: Data) = { _ in
            (200, tokenBody("token-1"))
        }
    ) -> StubURLProtocol.Handler {
        { request in
            switch request.url?.path {
            case "/secretDict.json": return secrets
            case "/api/server-time": return serverTime
            default: return token(request)
            }
        }
    }

    private func provider(_ handler: @escaping StubURLProtocol.Handler = handler())
        -> (SpotifyTokenProvider, StubURLProtocol.Stub)
    {
        let stub = StubURLProtocol.stub(handler)
        let provider = SpotifyTokenProvider(
            session: stub.session, credentials: credentials, secretsURL: Self.secretsURL,
            now: clock.now)
        return (provider, stub)
    }

    private func query(_ request: URLRequest) throws -> [String: String] {
        let url = try #require(request.url)
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        return Dictionary(items.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { first, _ in first })
    }

    @Test func withoutACookieNothingIsRequested() async throws {
        let stub = StubURLProtocol.stub(Self.handler())
        let provider = SpotifyTokenProvider(
            session: stub.session, credentials: InMemorySpotifyCredentialStore(),
            secretsURL: Self.secretsURL, now: clock.now)

        await #expect(throws: SpotifyAuthError.notConfigured) { _ = try await provider.token() }

        #expect(stub.requests.isEmpty)
    }

    @Test func fetchesATokenThroughAllThreeHops() async throws {
        let (provider, stub) = provider()

        let token = try await provider.token()

        #expect(token == "token-1")
        let requests = stub.requests
        #expect(requests.count == 3)
        #expect(requests.map { $0.url?.path } == ["/secretDict.json", "/api/server-time", "/api/token"])
        #expect(
            requests.allSatisfy {
                $0.value(forHTTPHeaderField: "User-Agent") == SpotifyWebClient.userAgent
            })
        // Only the token request carries the session cookie.
        #expect(requests[0].value(forHTTPHeaderField: "Cookie") == nil)
        #expect(requests[1].value(forHTTPHeaderField: "Cookie") == nil)

        let tokenRequest = requests[2]
        #expect(tokenRequest.url?.host() == "open.spotify.com")
        #expect(tokenRequest.value(forHTTPHeaderField: "Cookie") == "sp_dc=\(Self.cookie)")
        let query = try query(tokenRequest)
        #expect(query["reason"] == "transport")
        #expect(query["productType"] == "web-player")
        #expect(query["totpVer"] == "61")
        // `ts` is our clock, but the TOTP is computed from Spotify's, with the newest secret.
        #expect(query["ts"] == String(Self.clientTime))
        let expected = SpotifyTOTP.code(
            key: SpotifyTOTP.key(fromSecret: Self.secret), time: Self.serverTime)
        #expect(query["totp"] == expected)
    }

    @Test func secretVersionsAreComparedAsNumbers() async throws {
        let (provider, stub) = provider(
            Self.handler(secrets: (200, Data(#"{"9":[1,2,3],"10":[70,71,72,73,74,75]}"#.utf8))))

        _ = try await provider.token()

        let query = try query(stub.requests[2])
        #expect(query["totpVer"] == "10")
        #expect(
            query["totp"]
                == SpotifyTOTP.code(
                    key: SpotifyTOTP.key(fromSecret: Self.secret), time: Self.serverTime))
    }

    @Test func aValidTokenIsReusedUntilItNearsExpiry() async throws {
        let (provider, stub) = provider()

        #expect(try await provider.token() == "token-1")
        #expect(try await provider.token() == "token-1")
        #expect(stub.requests.count == 3)

        // One second before the 60-second margin the token still counts as fresh.
        let lifetime = Self.expirationMs / 1000 - TimeInterval(Self.clientTime)
        clock.advance(by: lifetime - 61)
        #expect(try await provider.token() == "token-1")
        #expect(stub.requests.count == 3)

        clock.advance(by: 1)
        #expect(try await provider.token() == "token-1")
        #expect(stub.requests.count == 6)
    }

    @Test func anAnonymousTokenMeansTheCookieWasRejected() async throws {
        let (provider, stub) = provider(
            Self.handler(token: { request in
                request.value(forHTTPHeaderField: "Cookie") == "sp_dc=\(Self.cookie)"
                    ? (200, Self.tokenBody("anon-token", anonymous: true))
                    : (200, Self.tokenBody("token-2"))
            }))

        await #expect(throws: SpotifyAuthError.cookieRejected) { _ = try await provider.token() }
        #expect(stub.requests.count == 3)

        // The same cookie is not worth asking about twice.
        await #expect(throws: SpotifyAuthError.cookieRejected) { _ = try await provider.token() }
        #expect(stub.requests.count == 3)

        credentials.setCookie("a-fresh-cookie")
        #expect(try await provider.token() == "token-2")
        #expect(stub.requests.count == 6)
    }

    @Test func invalidateForcesARefetch() async throws {
        let (provider, stub) = provider()

        _ = try await provider.token()
        await provider.invalidate()

        #expect(try await provider.token() == "token-1")
        #expect(stub.requests.count == 6)
    }

    @Test func invalidateKeepsTheRejection() async throws {
        let (provider, stub) = provider(
            Self.handler(token: { _ in (200, Self.tokenBody("anon-token", anonymous: true)) }))

        await #expect(throws: SpotifyAuthError.cookieRejected) { _ = try await provider.token() }
        await provider.invalidate()

        await #expect(throws: SpotifyAuthError.cookieRejected) { _ = try await provider.token() }
        #expect(stub.requests.count == 3)
    }

    @Test func secretsFailureStopsAtTheFirstHop() async throws {
        let (failing, stub) = provider(Self.handler(secrets: (500, Data("nope".utf8))))
        await #expect(throws: SpotifyAuthError.unexpectedResponse(step: .secrets, status: 500)) {
            _ = try await failing.token()
        }
        #expect(stub.requests.count == 1)

        let (broken, _) = provider(Self.handler(secrets: (200, Data("{not json".utf8))))
        await #expect(throws: SpotifyAuthError.unexpectedResponse(step: .secrets, status: nil)) {
            _ = try await broken.token()
        }

        let (empty, _) = provider(Self.handler(secrets: (200, Data("{}".utf8))))
        await #expect(throws: SpotifyAuthError.unexpectedResponse(step: .secrets, status: nil)) {
            _ = try await empty.token()
        }
    }

    @Test func serverTimeFailureStopsAtTheSecondHop() async throws {
        let (failing, stub) = provider(Self.handler(serverTime: (503, Data("nope".utf8))))
        await #expect(throws: SpotifyAuthError.unexpectedResponse(step: .serverTime, status: 503)) {
            _ = try await failing.token()
        }
        #expect(stub.requests.count == 2)

        let (broken, _) = provider(
            Self.handler(serverTime: (200, Data(#"{"serverTime":"soon"}"#.utf8))))
        await #expect(throws: SpotifyAuthError.unexpectedResponse(step: .serverTime, status: nil)) {
            _ = try await broken.token()
        }
    }

    @Test func tokenFailureIsReportedAsSuch() async throws {
        let (failing, stub) = provider(Self.handler(token: { _ in (401, Data()) }))
        await #expect(throws: SpotifyAuthError.unexpectedResponse(step: .token, status: 401)) {
            _ = try await failing.token()
        }
        #expect(stub.requests.count == 3)

        let (broken, _) = provider(
            Self.handler(token: { _ in (200, Data(#"{"accessToken":1}"#.utf8)) }))
        await #expect(throws: SpotifyAuthError.unexpectedResponse(step: .token, status: nil)) {
            _ = try await broken.token()
        }
    }
}
