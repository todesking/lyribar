import Foundation

enum LRCLibError: Error, Equatable {
    case invalidURL
    case invalidResponse
    case unexpectedStatus(Int)
}

/// Fetches synced lyrics from LRCLIB: `/api/get` by artist/title/duration, falling back to
/// `/api/search` by artist/title when the exact match misses. Plain lyrics are never used.
struct LRCLibProvider: LyricsProvider {
    static let source = "lrclib"

    /// Exponential backoff for transient failures. Kept short: LRCLIB is a free service.
    struct RetryPolicy: Sendable {
        var maxRetries: Int
        var initialDelay: Duration
        var multiplier: Double

        static let `default` = RetryPolicy(
            maxRetries: 3, initialDelay: .milliseconds(500), multiplier: 2)
        static let none = RetryPolicy(maxRetries: 0, initialDelay: .zero, multiplier: 1)

        func delay(forRetry retry: Int) -> Duration {
            initialDelay * pow(multiplier, Double(retry))
        }
    }

    private static let scheme = "https"
    private static let host = "lrclib.net"

    private let session: URLSession
    private let userAgent: String
    private let retryPolicy: RetryPolicy
    private let sleep: @Sendable (Duration) async throws -> Void

    init(
        session: URLSession = .shared,
        userAgent: String = LRCLibProvider.defaultUserAgent,
        retryPolicy: RetryPolicy = .default,
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.session = session
        self.userAgent = userAgent
        self.retryPolicy = retryPolicy
        self.sleep = sleep
    }

    // LRCLIB asks clients to identify themselves.
    static var defaultUserAgent: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        return "Lyribar/\(version) (https://github.com/todesking/lyribar)"
    }

    func fetch(_ track: TrackInfo) async throws -> FetchedLyrics? {
        guard let lyrics = try await lyrics(for: track) else { return nil }
        return FetchedLyrics(lyrics: lyrics, source: Self.source)
    }

    private func lyrics(for track: TrackInfo) async throws -> SyncedLyrics? {
        let request = try makeRequest(
            path: "/api/get",
            query: [
                ("track_name", track.title),
                ("artist_name", track.artist),
                ("duration", String(Int(track.duration.rounded()))),
            ])
        let (data, status) = try await send(request)
        switch status {
        case 200:
            let record = try JSONDecoder().decode(Record.self, from: data)
            return record.syncedLyrics.flatMap(LRCParser.parse)
        case 404:
            return try await search(track)
        default:
            throw LRCLibError.unexpectedStatus(status)
        }
    }

    private func search(_ track: TrackInfo) async throws -> SyncedLyrics? {
        let request = try makeRequest(
            path: "/api/search",
            query: [
                ("track_name", track.title),
                ("artist_name", track.artist),
            ])
        let (data, status) = try await send(request)
        switch status {
        case 200:
            let records = try JSONDecoder().decode([Record].self, from: data)
            guard let synced = records.lazy.compactMap(\.syncedLyrics).first else { return nil }
            return LRCParser.parse(synced)
        case 404:
            return nil
        default:
            throw LRCLibError.unexpectedStatus(status)
        }
    }

    /// Retries 5xx and transport errors (timeout, connection drop) a bounded number of times.
    /// 429 and the other 4xx are answers, not hiccups, and are returned as is.
    private func send(_ request: URLRequest) async throws -> (Data, Int) {
        var retry = 0
        while true {
            do {
                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse else { throw LRCLibError.invalidResponse }
                guard (500...599).contains(http.statusCode), retry < retryPolicy.maxRetries else {
                    return (data, http.statusCode)
                }
            } catch let error as URLError {
                guard retry < retryPolicy.maxRetries else { throw error }
            }
            try Task.checkCancellation()
            try await sleep(retryPolicy.delay(forRetry: retry))
            retry += 1
        }
    }

    private func makeRequest(path: String, query: [(String, String)]) throws -> URLRequest {
        var components = URLComponents()
        components.scheme = Self.scheme
        components.host = Self.host
        components.path = path
        // URLComponents leaves "+" as is in query values, which servers read as a space.
        components.percentEncodedQuery = query
            .map { "\(Self.escape($0.0))=\(Self.escape($0.1))" }
            .joined(separator: "&")
        guard let url = components.url else { throw LRCLibError.invalidURL }
        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        return request
    }

    private static let unreserved = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    private static func escape(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: unreserved) ?? value
    }

    private struct Record: Decodable {
        let syncedLyrics: String?
    }
}
