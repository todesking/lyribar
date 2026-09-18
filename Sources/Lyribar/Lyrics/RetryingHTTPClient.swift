import Foundation

enum HTTPClientError: Error, Equatable {
    /// URLSession answered with something that is not an HTTP response.
    case invalidResponse
}

/// Sends requests and retries 5xx and transport errors (timeout, connection drop) a bounded number
/// of times. 429 and the other 4xx are answers, not hiccups, and are returned as is.
struct RetryingHTTPClient: Sendable {
    /// Exponential backoff for transient failures. Kept short: these are free services.
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

    private let session: URLSession
    private let retryPolicy: RetryPolicy
    private let sleep: @Sendable (Duration) async throws -> Void

    init(
        session: URLSession,
        retryPolicy: RetryPolicy = .default,
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.session = session
        self.retryPolicy = retryPolicy
        self.sleep = sleep
    }

    func send(_ request: URLRequest) async throws -> (Data, Int) {
        var retry = 0
        while true {
            do {
                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse else {
                    throw HTTPClientError.invalidResponse
                }
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
}
