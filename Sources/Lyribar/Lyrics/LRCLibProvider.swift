import Foundation

enum LRCLibError: Error, Equatable {
    case invalidURL
    case invalidResponse
    case unexpectedStatus(Int)
}

/// Fetches synced lyrics from LRCLIB: `/api/get` by artist/title/duration, falling back to
/// `/api/search` by artist/title when the exact match misses. Among the search results, only
/// records whose duration is close to the track's are considered, closest first. Plain lyrics
/// are never used.
struct LRCLibProvider: LyricsProvider {
    static let source = "lrclib"

    typealias RetryPolicy = RetryingHTTPClient.RetryPolicy

    private static let scheme = "https"
    private static let host = "lrclib.net"
    // /api/get already tolerates a couple of seconds; the wider margin here is only meant to
    // absorb search's fuzzy name matching (feat. credits, "Remastered" suffixes, ...), not to
    // match a different version of the track.
    private static let searchDurationTolerance: Double = 3

    private let http: RetryingHTTPClient
    private let userAgent: String

    init(
        session: URLSession = .shared,
        userAgent: String = LRCLibProvider.defaultUserAgent,
        retryPolicy: RetryPolicy = .default,
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        http = RetryingHTTPClient(session: session, retryPolicy: retryPolicy, sleep: sleep)
        self.userAgent = userAgent
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
            return bestMatch(among: records, for: track)
        case 404:
            return nil
        default:
            throw LRCLibError.unexpectedStatus(status)
        }
    }

    private func bestMatch(among records: [Record], for track: TrackInfo) -> SyncedLyrics? {
        let candidates = records
            .compactMap { record -> (synced: String, distance: Double)? in
                guard let synced = record.syncedLyrics, let duration = record.duration else {
                    return nil
                }
                let distance = abs(duration - track.duration)
                guard distance <= Self.searchDurationTolerance else { return nil }
                return (synced, distance)
            }
            .sorted { $0.distance < $1.distance }
        for candidate in candidates {
            if let parsed = LRCParser.parse(candidate.synced) { return parsed }
        }
        return nil
    }

    private func send(_ request: URLRequest) async throws -> (Data, Int) {
        do {
            return try await http.send(request)
        } catch HTTPClientError.invalidResponse {
            throw LRCLibError.invalidResponse
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
        let duration: Double?
    }
}
