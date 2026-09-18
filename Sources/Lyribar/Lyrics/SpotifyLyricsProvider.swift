import Foundation

enum SpotifyLyricsError: Error, Equatable {
    case invalidURL
    case unexpectedStatus(Int)
}

/// Fetches the line-synced lyrics the Spotify web player shows, from the unofficial `color-lyrics`
/// endpoint, using an access token minted from the stored session cookie.
///
/// Without a cookie the source simply has nothing to offer, so it returns nil rather than failing.
struct SpotifyLyricsProvider: LyricsProvider {
    static let source = "spotify"

    typealias RetryPolicy = RetryingHTTPClient.RetryPolicy

    private static let trackPrefix = "spotify:track:"
    private static let host = "spclient.wg.spotify.com"
    private static let pathPrefix = "/color-lyrics/v2/track/"
    private static let lineSynced = "LINE_SYNCED"
    /// The marker Spotify uses for an interlude, which the ribbon shows as a gap.
    private static let interlude = "♪"

    private let http: RetryingHTTPClient
    private let tokenProvider: SpotifyTokenProvider

    init(
        session: URLSession = .shared,
        tokenProvider: SpotifyTokenProvider,
        retryPolicy: RetryPolicy = .default,
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        http = RetryingHTTPClient(session: session, retryPolicy: retryPolicy, sleep: sleep)
        self.tokenProvider = tokenProvider
    }

    func fetch(_ track: TrackInfo) async throws -> FetchedLyrics? {
        // Local files and podcast episodes have no track id Spotify's catalog knows about.
        guard track.id.hasPrefix(Self.trackPrefix) else { return nil }
        guard let token = try await token() else { return nil }

        let url = try Self.url(forTrack: String(track.id.dropFirst(Self.trackPrefix.count)))
        var (data, status) = try await http.send(Self.request(url, token: token))
        // An expired or revoked token is worth one fresh try, and no more.
        if status == 401 {
            await tokenProvider.invalidate()
            guard let token = try await self.token() else { return nil }
            (data, status) = try await http.send(Self.request(url, token: token))
        }

        switch status {
        case 200:
            guard let lyrics = try Self.lyrics(from: data) else { return nil }
            return FetchedLyrics(lyrics: lyrics, source: Self.source)
        case 404:
            // A miss comes with an empty body, so there is nothing to decode.
            return nil
        default:
            throw SpotifyLyricsError.unexpectedStatus(status)
        }
    }

    private func token() async throws -> String? {
        do {
            return try await tokenProvider.token()
        } catch SpotifyAuthError.notConfigured {
            return nil
        }
    }

    private static func url(forTrack id: String) throws -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        components.path = pathPrefix + id
        components.queryItems = [
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "market", value: "from_token"),
        ]
        guard let url = components.url else { throw SpotifyLyricsError.invalidURL }
        return url
    }

    // Accept-Encoding is left to URLSession: responses received uncompressed have come back
    // truncated.
    private static func request(_ url: URL, token: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue("WebPlayer", forHTTPHeaderField: "App-platform")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "authorization")
        request.setValue(SpotifyWebClient.userAgent, forHTTPHeaderField: "User-Agent")
        return request
    }

    private static func lyrics(from data: Data) throws -> SyncedLyrics? {
        let response = try JSONDecoder().decode(Response.self, from: data)
        guard response.lyrics.syncType == lineSynced else { return nil }
        let lines = self.lines(from: response.lyrics.lines)
        guard lines.contains(where: { !$0.text.isEmpty }) else { return nil }
        return SyncedLyrics(lines: lines)
    }

    /// Times are milliseconds in a string; a line whose time makes no sense is dropped. Sorting is
    /// by index as well as time, so lines that share a time keep the order Spotify sent them in.
    private static func lines(from raw: [Response.Line]) -> [LyricLine] {
        raw.compactMap { line -> LyricLine? in
            guard let milliseconds = Double(line.startTimeMs) else { return nil }
            let words = line.words.trimmingCharacters(in: .whitespacesAndNewlines)
            return LyricLine(
                time: milliseconds / 1000, text: words == interlude ? "" : words)
        }
        .enumerated()
        .sorted { ($0.element.time, $0.offset) < ($1.element.time, $1.offset) }
        .map(\.element)
    }

    /// Only the keys that are used, so the shape can grow or shrink around them.
    private struct Response: Decodable {
        let lyrics: Lyrics

        struct Lyrics: Decodable {
            let syncType: String
            let lines: [Line]
        }

        struct Line: Decodable {
            let startTimeMs: String
            let words: String
        }
    }
}
