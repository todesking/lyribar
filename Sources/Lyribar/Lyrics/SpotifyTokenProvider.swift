import Foundation

enum SpotifyWebClient {
    // The unofficial endpoints are only known to work when the caller looks like a browser.
    static let userAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"
}

enum SpotifyAuthError: Error, Equatable {
    enum Step: Sendable {
        case secrets
        case serverTime
        case token
    }

    case notConfigured
    case cookieRejected
    /// `status` is the HTTP status when it was not 200, and nil when a 200 could not be read.
    case unexpectedResponse(step: Step, status: Int?)
}

/// Turns the stored `sp_dc` cookie into a web player access token: fetch the published TOTP
/// secrets, ask Spotify for its clock, and trade a TOTP for a token.
///
/// Tokens and rejections live in memory only, and neither the cookie nor the token is ever logged.
actor SpotifyTokenProvider {
    private static let serverTimePath = "/api/server-time"
    private static let tokenPath = "/api/token"
    private static let host = "open.spotify.com"
    /// Refresh this long before expiry so a token handed out here does not die mid-request.
    private static let expiryMargin: TimeInterval = 60

    private let session: URLSession
    private let credentials: any SpotifyCredentialStore
    private let secretsURL: URL
    private let now: @Sendable () -> Date

    private var issued: (cookie: String, token: String, expiresAt: Date)?
    private var rejectedCookie: String?
    private var inFlight: (id: Int, cookie: String, task: Task<String, Error>)?
    private var lastIssueID = 0

    init(
        session: URLSession = .shared,
        credentials: any SpotifyCredentialStore,
        secretsURL: URL,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.session = session
        self.credentials = credentials
        self.secretsURL = secretsURL
        self.now = now
    }

    func token() async throws -> String {
        guard let cookie = credentials.cookie() else { throw SpotifyAuthError.notConfigured }
        if let issued, issued.cookie == cookie,
            issued.expiresAt.addingTimeInterval(-Self.expiryMargin) > now()
        {
            return issued.token
        }
        // A cookie Spotify already refused will not start working; a new one deserves a try.
        guard rejectedCookie != cookie else { throw SpotifyAuthError.cookieRejected }
        // Callers that arrive while a token is being issued share it instead of sending their own
        // TOTP request. An issuance for another cookie is stale, so it is replaced rather than
        // joined.
        if let inFlight, inFlight.cookie == cookie {
            return try await inFlight.task.value
        }

        lastIssueID += 1
        let id = lastIssueID
        // Unstructured on purpose: one caller giving up must not cancel the others' issuance.
        let task = Task { try await self.issue(id: id, cookie: cookie) }
        inFlight = (id, cookie, task)
        return try await task.value
    }

    /// Drops the remembered token, but not the memory of a refused cookie. An issuance already
    /// under way may be joined: its token is newer than the one being dropped.
    func invalidate() {
        issued = nil
    }

    /// The three hops, run once per `inFlight` entry.
    private func issue(id: Int, cookie: String) async throws -> String {
        defer { if inFlight?.id == id { inFlight = nil } }

        let secret = try await fetchSecret()
        // Fetched after the secrets, not alongside them, so the TOTP is built on a fresh clock.
        let serverTime = try await fetchServerTime()
        let code = SpotifyTOTP.code(
            key: SpotifyTOTP.key(fromSecret: secret.values), time: serverTime)
        let response = try await fetchToken(cookie: cookie, code: code, version: secret.version)
        guard !response.isAnonymous else {
            // An issuance for another cookie may have landed meanwhile; only drop our own token.
            if issued?.cookie == cookie { issued = nil }
            rejectedCookie = cookie
            throw SpotifyAuthError.cookieRejected
        }
        issued = (
            cookie, response.accessToken,
            Date(timeIntervalSince1970: response.accessTokenExpirationTimestampMs / 1000)
        )
        return response.accessToken
    }

    // JSON objects have no key order, so the newest version is the numerically largest key.
    private func fetchSecret() async throws -> (version: String, values: [Int]) {
        let data = try await get(URLRequest(url: secretsURL), step: .secrets)
        let secrets = try decode([String: [Int]].self, from: data, step: .secrets)
        let newest = secrets
            .compactMap { key, values in Int(key).map { (key, $0, values) } }
            .max { $0.1 < $1.1 }
        guard let newest else {
            throw SpotifyAuthError.unexpectedResponse(step: .secrets, status: nil)
        }
        return (newest.0, newest.2)
    }

    private func fetchServerTime() async throws -> Int {
        let request = try request(path: Self.serverTimePath, query: [], step: .serverTime)
        let data = try await get(request, step: .serverTime)
        return try decode(ServerTime.self, from: data, step: .serverTime).serverTime
    }

    private func fetchToken(cookie: String, code: String, version: String) async throws -> Token {
        var request = try request(
            path: Self.tokenPath,
            query: [
                ("reason", "transport"),
                ("productType", "web-player"),
                ("totp", code),
                ("totpVer", version),
                ("ts", String(Int(now().timeIntervalSince1970))),
            ],
            step: .token)
        request.setValue("sp_dc=\(cookie)", forHTTPHeaderField: "Cookie")
        let data = try await get(request, step: .token)
        return try decode(Token.self, from: data, step: .token)
    }

    private func request(path: String, query: [(String, String)], step: SpotifyAuthError.Step)
        throws -> URLRequest
    {
        var components = URLComponents()
        components.scheme = "https"
        components.host = Self.host
        components.path = path
        if !query.isEmpty {
            components.queryItems = query.map { URLQueryItem(name: $0.0, value: $0.1) }
        }
        guard let url = components.url else {
            throw SpotifyAuthError.unexpectedResponse(step: step, status: nil)
        }
        return URLRequest(url: url)
    }

    /// No retries here: the resolver already retries, and a failed hop leaves nothing to resume.
    private func get(_ request: URLRequest, step: SpotifyAuthError.Step) async throws -> Data {
        var request = request
        request.setValue(SpotifyWebClient.userAgent, forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw SpotifyAuthError.unexpectedResponse(step: step, status: nil)
        }
        guard http.statusCode == 200 else {
            throw SpotifyAuthError.unexpectedResponse(step: step, status: http.statusCode)
        }
        return data
    }

    private func decode<T: Decodable>(
        _ type: T.Type, from data: Data, step: SpotifyAuthError.Step
    ) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw SpotifyAuthError.unexpectedResponse(step: step, status: nil)
        }
    }

    private struct ServerTime: Decodable {
        let serverTime: Int
    }

    private struct Token: Decodable {
        let accessToken: String
        let accessTokenExpirationTimestampMs: Double
        let isAnonymous: Bool
    }
}
