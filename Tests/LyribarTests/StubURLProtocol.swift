import Foundation

/// URLProtocol stub so tests never touch the network. The handler is global state, so suites using
/// it must be `.serialized`.
final class StubURLProtocol: URLProtocol {
    enum Outcome: Sendable {
        case response(status: Int, body: Data)
        /// A transport failure, as URLSession reports a timeout or a dropped connection.
        case failure(URLError)
    }

    typealias Handler = @Sendable (URLRequest) -> (status: Int, body: Data)
    typealias OutcomeHandler = @Sendable (URLRequest) -> Outcome

    private static let lock = NSLock()
    nonisolated(unsafe) private static var handler: OutcomeHandler?
    nonisolated(unsafe) private static var requests: [URLRequest] = []

    static func session(_ handler: @escaping Handler) -> URLSession {
        session(outcomes: { request in
            let (status, body) = handler(request)
            return .response(status: status, body: body)
        })
    }

    static func session(outcomes handler: @escaping OutcomeHandler) -> URLSession {
        lock.withLock {
            self.handler = handler
            requests = []
        }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: config)
    }

    static var recordedRequests: [URLRequest] {
        lock.withLock { requests }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let handler = Self.lock.withLock {
            Self.requests.append(request)
            return Self.handler
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
