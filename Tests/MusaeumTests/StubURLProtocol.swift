import Foundation
import XCTest

/// A `URLProtocol` stub, so the client's own behaviour is decided without a
/// server: what it asks for, what it does with each status, and — for the cover
/// pipeline — how many requests it has open at once.
final class StubURLProtocol: URLProtocol {
    struct Response {
        var status: Int = 200
        var headers: [String: String] = [:]
        var body: Data = Data()
        var delay: TimeInterval = 0
        /// A body delivered in pieces, one `didLoad` each — the shape of a streamed response.
        var chunks: [Data] = []
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var handler: ((URLRequest) -> Response)?
    nonisolated(unsafe) private static var inFlight = 0
    nonisolated(unsafe) private static var peak = 0
    nonisolated(unsafe) private static var log: [URLRequest] = []
    nonisolated(unsafe) private static var stopped = 0

    static func configure(_ handler: @escaping (URLRequest) -> Response) {
        lock.lock()
        defer { lock.unlock() }
        self.handler = handler
        inFlight = 0
        peak = 0
        log = []
        stopped = 0
    }

    static var requests: [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return log
    }

    /// How many loads the session has abandoned — a cancelled request closes its connection.
    static var stoppedLoads: Int {
        lock.lock()
        defer { lock.unlock() }
        return stopped
    }

    static var peakConcurrency: Int {
        lock.lock()
        defer { lock.unlock() }
        return peak
    }

    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    /// Guarded by `lock`: whether this load's delivery block has begun, and whether `stopLoading`
    /// got there first. `inFlight` is decremented exactly once per load, by whichever comes first.
    private var delivering = false
    private var abandoned = false
    private var delivery: DispatchWorkItem?

    override func startLoading() {
        Self.lock.lock()
        Self.inFlight += 1
        Self.peak = max(Self.peak, Self.inFlight)
        Self.log.append(request)
        let handler = Self.handler
        Self.lock.unlock()

        let response = handler?(request) ?? Response(status: 500)
        let item = DispatchWorkItem { [self] in
            Self.lock.lock()
            if abandoned {
                Self.lock.unlock()
                return
            }
            delivering = true
            Self.inFlight -= 1
            Self.lock.unlock()

            let http = HTTPURLResponse(
                url: request.url!,
                statusCode: response.status,
                httpVersion: "HTTP/1.1",
                headerFields: response.headers
            )!
            client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
            if !response.chunks.isEmpty {
                for chunk in response.chunks { client?.urlProtocol(self, didLoad: chunk) }
            } else if !response.body.isEmpty {
                client?.urlProtocol(self, didLoad: response.body)
            }
            client?.urlProtocolDidFinishLoading(self)
        }
        Self.lock.lock()
        delivery = item
        Self.lock.unlock()
        DispatchQueue.global().asyncAfter(deadline: .now() + response.delay, execute: item)
    }

    /// A cancelled request must not leave its delayed delivery behind to run against state a later
    /// test has reset: cancel the block, and if it never began, give back the slot it took.
    override func stopLoading() {
        Self.lock.lock()
        Self.stopped += 1
        if !delivering && !abandoned {
            abandoned = true
            Self.inFlight -= 1
        }
        let item = delivery
        Self.lock.unlock()
        item?.cancel()
    }
}
