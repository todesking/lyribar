import Foundation

/// Canned HTTP responses so tests never touch the network.
///
/// Each stub owns its handler and its recording, keyed by a header the stubbed session adds, so
/// suites that stub HTTP do not disturb each other when the test runner runs them in parallel.
final class StubURLProtocol: URLProtocol {
    enum Outcome: Sendable {
        case response(status: Int, body: Data)
        /// A transport failure, as URLSession reports a timeout or a dropped connection.
        case failure(URLError)
    }

    typealias Handler = @Sendable (URLRequest) -> (status: Int, body: Data)
    typealias OutcomeHandler = @Sendable (URLRequest) -> Outcome

    /// A stubbed session together with what it was asked for.
    final class Stub: Sendable {
        let session: URLSession
        private let id: Int

        fileprivate init(id: Int, session: URLSession) {
            self.id = id
            self.session = session
        }

        var requests: [URLRequest] { StubURLProtocol.requests(of: id) }
    }

    private static let idHeader = "X-Stub-Id"
    private static let lock = NSLock()
    nonisolated(unsafe) private static var nextID = 0
    nonisolated(unsafe) private static var handlers: [Int: OutcomeHandler] = [:]
    nonisolated(unsafe) private static var recorded: [Int: [URLRequest]] = [:]

    static func stub(_ handler: @escaping Handler) -> Stub {
        stub(outcomes: { request in
            let (status, body) = handler(request)
            return .response(status: status, body: body)
        })
    }

    static func stub(outcomes handler: @escaping OutcomeHandler) -> Stub {
        let id = lock.withLock {
            nextID += 1
            handlers[nextID] = handler
            recorded[nextID] = []
            return nextID
        }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        config.httpAdditionalHeaders = [idHeader: String(id)]
        return Stub(id: id, session: URLSession(configuration: config))
    }

    private static func requests(of id: Int) -> [URLRequest] {
        lock.withLock { recorded[id] ?? [] }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let id = request.value(forHTTPHeaderField: Self.idHeader).flatMap(Int.init)
        let handler = Self.lock.withLock {
            guard let id else { return nil as OutcomeHandler? }
            Self.recorded[id, default: []].append(request)
            return Self.handlers[id]
        }
        guard let handler, let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        let status: Int
        let body: Data
        switch handler(request) {
        case .response(let responseStatus, let responseBody):
            (status, body) = (responseStatus, responseBody)
        case .failure(let error):
            client?.urlProtocol(self, didFailWithError: error)
            return
        }
        guard
            let response = HTTPURLResponse(
                url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)
        else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
