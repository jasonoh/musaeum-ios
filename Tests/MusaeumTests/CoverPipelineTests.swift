import XCTest

@testable import Musaeum

/// The cover pipeline's whole reason to exist is a **bound**, and a bound is
/// decided by counting: the server shares two byte transfers between both of its
/// byte routes and answers the third with `503 busy`, so a client that opens more
/// than two at once does not go faster — it collects refusals and takes the
/// file-I/O pool away from the Mac app it is reading from.
final class CoverPipelineTests: XCTestCase {
    private let base = URL(string: "http://100.64.0.1:8788")!

    func testItNeverHasMoreThanTwoTransfersOpen() async throws {
        StubURLProtocol.configure { _ in
            StubURLProtocol.Response(status: 200, headers: ["Content-Type": "image/jpeg"], body: Data([0xFF, 0xD8, 0xFF]), delay: 0.06)
        }
        let client = MusaeumClient(base: base, token: "t", session: StubURLProtocol.session())
        let pipeline = CoverPipeline(session: StubURLProtocol.session())

        await withTaskGroup(of: Void.self) { group in
            for index in 0..<9 {
                group.addTask {
                    _ = try? await pipeline.data(for: client.coverRequest(id: "book-\(index)", size: "thumb"))
                }
            }
        }

        XCTAssertEqual(StubURLProtocol.requests.count, 9, "every cover was fetched")
        XCTAssertEqual(
            StubURLProtocol.peakConcurrency,
            CoverPipeline.maxInFlight,
            "the pipeline's own cap is what the server's budget is; 9 covers must never have more than 2 open"
        )
    }

    /// `503 busy` is the answer the server gives on purpose, and the contract
    /// says the client retries it — a grid that dropped the cover would show a
    /// grey rectangle for a book whose cover is perfectly available.
    func testABusyAnswerIsRetriedRatherThanDropped() async throws {
        // The stub logs a request before it answers it, so the first two answers
        // are the server's own "busy" and the third is the cover.
        StubURLProtocol.configure { _ in
            if StubURLProtocol.requests.count <= 2 {
                return StubURLProtocol.Response(
                    status: 503,
                    headers: ["Retry-After": "0"],
                    body: Data(#"{"error":"busy"}"#.utf8)
                )
            }
            return StubURLProtocol.Response(status: 200, body: Data([0xFF, 0xD8]))
        }

        let client = MusaeumClient(base: base, token: "t", session: StubURLProtocol.session())
        let pipeline = CoverPipeline(session: StubURLProtocol.session())

        let first = try await pipeline.data(for: client.coverRequest(id: "a", size: "thumb"))
        XCTAssertEqual(first.count, 2)
        XCTAssertEqual(StubURLProtocol.requests.count, 3, "two refusals then the cover")
    }

    func testAShareThatIsOfflineSurfacesAsItsOwnOutcome() async throws {
        StubURLProtocol.configure { _ in
            StubURLProtocol.Response(
                status: 503,
                headers: ["Retry-After": "5"],
                body: Data(#"{"error":"library offline"}"#.utf8)
            )
        }
        let client = MusaeumClient(base: base, token: "t", session: StubURLProtocol.session())
        let pipeline = CoverPipeline(session: StubURLProtocol.session())
        await XCTAssertThrowsErrorAsync(
            try await pipeline.data(for: client.coverRequest(id: "a", size: "thumb"), attempts: 1)
        ) { error in
            XCTAssertEqual(error as? ClientError, .libraryOffline(retryAfter: 5))
        }
    }
}
