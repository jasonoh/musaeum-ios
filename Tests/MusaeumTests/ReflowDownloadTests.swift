import XCTest

@testable import Musaeum

/// `downloadReflow` — the poll that waits out the Mac's layout pass.
///
/// The contract's `format=reflow` table (`../musaeum/docs/rest-api.md`): 200 is the
/// book, 202 is "still running" with a progress body, 422 is "cannot reflow". The
/// plain `download` would take a 202 for a finished file, which is the failure
/// these cases exist to prevent. `pause` is injected and the deadline counts the
/// pauses asked for, so none of this waits on a clock.
final class ReflowDownloadTests: XCTestCase {
    private let base = URL(string: "http://100.64.0.1:8788")!

    private func client(_ handler: @escaping (URLRequest) -> StubURLProtocol.Response) -> MusaeumClient {
        StubURLProtocol.configure(handler)
        return MusaeumClient(base: base, token: "test-token", session: StubURLProtocol.session())
    }

    /// Hands out responses in order, then repeats the last.
    private final class Script: @unchecked Sendable {
        private let lock = NSLock()
        private var index = 0
        let responses: [StubURLProtocol.Response]
        init(_ responses: [StubURLProtocol.Response]) { self.responses = responses }
        func next() -> StubURLProtocol.Response {
            lock.lock()
            defer { lock.unlock() }
            let response = responses[min(index, responses.count - 1)]
            index += 1
            return response
        }
    }

    private final class Recorder<T: Sendable>: @unchecked Sendable {
        private let lock = NSLock()
        private var items: [T] = []
        func add(_ item: T) { lock.lock(); items.append(item); lock.unlock() }
        var all: [T] { lock.lock(); defer { lock.unlock() }; return items }
    }

    private func progress(_ phase: String, _ completed: Int, _ total: Int, retryAfter: String? = "2") -> StubURLProtocol.Response {
        var headers: [String: String] = [:]
        if let retryAfter { headers["Retry-After"] = retryAfter }
        let body = #"{"phase":"\#(phase)","completed":\#(completed),"total":\#(total)}"#
        return .init(status: 202, headers: headers, body: Data(body.utf8))
    }

    private let epub = Data([0x50, 0x4B, 0x03, 0x04, 0xDE, 0xAD, 0xBE, 0xEF])

    private func run(
        _ client: MusaeumClient,
        id: String = "book1",
        deadline: Duration = .seconds(25 * 60),
        pauses: Recorder<Duration> = Recorder(),
        seen: Recorder<ReflowProgress> = Recorder()
    ) async throws -> (file: URL, bytes: Int) {
        try await client.downloadReflow(
            id: id,
            deadline: deadline,
            pause: { pauses.add($0) },
            onProgress: { seen.add($0) }
        )
    }

    func testPollsThroughTwo202sThenReturnsTheBytes() async throws {
        let script = Script([
            progress("layout", 12, 24),
            progress("layout", 24, 24),
            .init(status: 200, body: epub),
        ])
        let client = client { _ in script.next() }
        let pauses = Recorder<Duration>()
        let seen = Recorder<ReflowProgress>()
        let result = try await run(client, id: "abc", pauses: pauses, seen: seen)
        defer { try? FileManager.default.removeItem(at: result.file) }

        XCTAssertEqual(try Data(contentsOf: result.file), epub)
        XCTAssertEqual(result.bytes, epub.count)
        XCTAssertEqual(seen.all.map { "\($0.completed)/\($0.total)" }, ["12/24", "24/24"])
        XCTAssertEqual(pauses.all, [.seconds(2), .seconds(2)])
        let requests = StubURLProtocol.requests
        XCTAssertEqual(requests.count, 3)
        for request in requests {
            XCTAssertEqual(request.url?.path, "/api/books/abc/file")
            XCTAssertEqual(request.url?.query, "format=reflow")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-token")
        }
    }

    /// Review focus 1: a 202's JSON is progress, never the book.
    func testA202BodyIsNeverReturnedAsTheFile() async throws {
        let script = Script([progress("start", 0, 0), .init(status: 200, body: epub)])
        let client = client { _ in script.next() }
        let result = try await run(client)
        defer { try? FileManager.default.removeItem(at: result.file) }
        let bytes = try Data(contentsOf: result.file)
        XCTAssertEqual(bytes, epub)
        XCTAssertFalse(String(decoding: bytes, as: UTF8.self).contains("phase"))
    }

    func testAnUndecodable202StillPollsAndReportsStart() async throws {
        let script = Script([.init(status: 202, headers: ["Retry-After": "2"], body: Data("nope".utf8)), .init(status: 200, body: epub)])
        let client = client { _ in script.next() }
        let seen = Recorder<ReflowProgress>()
        let result = try await run(client, seen: seen)
        defer { try? FileManager.default.removeItem(at: result.file) }
        XCTAssertEqual(seen.all, [ReflowProgress(phase: "start", completed: 0, total: 0)])
    }

    func testA422ThrowsCannotReflowWithTheMacsReason() async throws {
        let reasoned = client { _ in
            .init(status: 422, body: Data(#"{"error":"cannot reflow","reason":"no page carries a text layer"}"#.utf8))
        }
        do {
            _ = try await run(reasoned)
            XCTFail("expected a throw")
        } catch {
            XCTAssertEqual(error as? ClientError, .cannotReflow("no page carries a text layer"))
        }
        XCTAssertEqual(StubURLProtocol.requests.count, 1, "a refusal is not retried")

        let silent = client { _ in .init(status: 422) }
        do {
            _ = try await run(silent)
            XCTFail("expected a throw")
        } catch {
            XCTAssertEqual(error as? ClientError, .cannotReflow("the Mac gave no reason"))
        }
        XCTAssertEqual(StubURLProtocol.requests.count, 1)
        XCTAssertFalse(ClientError.cannotReflow("x").isRetryable)
        XCTAssertEqual(
            ClientError.cannotReflow("scanned").description,
            "the Mac could not make a readable copy of this PDF — scanned"
        )
    }

    func testStatusesOutsideTheReflowTableKeepTheirOrdinaryMeaning() async throws {
        func failure(_ response: StubURLProtocol.Response) async -> ClientError? {
            let client = self.client { _ in response }
            do {
                _ = try await run(client)
                return nil
            } catch {
                return error as? ClientError
            }
        }
        let notFound = await failure(.init(status: 404))
        XCTAssertEqual(notFound, .notFound)
        let offline = await failure(.init(status: 503, headers: ["Retry-After": "5"], body: Data(#"{"error":"library offline"}"#.utf8)))
        XCTAssertEqual(offline, .libraryOffline(retryAfter: 5))
        let unauthorized = await failure(.init(status: 401))
        XCTAssertEqual(unauthorized, .unauthorized)
    }

    func testABusy503IsRetriedTwiceThenThrown() async throws {
        let client = client { _ in .init(status: 503, headers: ["Retry-After": "3"], body: Data(#"{"error":"busy"}"#.utf8)) }
        let pauses = Recorder<Duration>()
        do {
            _ = try await run(client, pauses: pauses)
            XCTFail("expected a throw")
        } catch {
            XCTAssertEqual(error as? ClientError, .busy(retryAfter: 3))
        }
        XCTAssertEqual(StubURLProtocol.requests.count, 3)
        XCTAssertEqual(pauses.all, [.seconds(3), .seconds(3)])
    }

    func testRetryAfterIsClampedAndDefaulted() async throws {
        for (header, expected) in [("3600", 10), ("0", 1), (nil, 2)] as [(String?, Int)] {
            let script = Script([progress("layout", 1, 2, retryAfter: header), .init(status: 200, body: epub)])
            let client = client { _ in script.next() }
            let pauses = Recorder<Duration>()
            let result = try await run(client, pauses: pauses)
            try? FileManager.default.removeItem(at: result.file)
            XCTAssertEqual(pauses.all, [.seconds(expected)], "Retry-After \(header ?? "absent")")
        }
    }

    func testAHostileRetryAfterOnA202FallsBackToTheDefault() async throws {
        for header in ["nan", "inf", "-5"] {
            let script = Script([progress("layout", 1, 2, retryAfter: header), .init(status: 200, body: epub)])
            let client = client { _ in script.next() }
            let pauses = Recorder<Duration>()
            let result = try await run(client, pauses: pauses)
            try? FileManager.default.removeItem(at: result.file)
            XCTAssertEqual(pauses.all, [.seconds(2)], "Retry-After \(header)")
        }
    }

    func testAHostileRetryAfterOnABusy503FallsBackToOneSecond() async throws {
        for header in ["nan", "inf", "-5"] {
            let client = client { _ in .init(status: 503, headers: ["Retry-After": header], body: Data(#"{"error":"busy"}"#.utf8)) }
            let pauses = Recorder<Duration>()
            do {
                _ = try await run(client, pauses: pauses)
                XCTFail("expected a throw")
            } catch {
                XCTAssertEqual(error as? ClientError, .busy(retryAfter: nil), "Retry-After \(header)")
            }
            XCTAssertEqual(pauses.all, [.seconds(1), .seconds(1)], "Retry-After \(header)")
        }
    }

    func testANegativeRetryAfterDoesNotPostponeTheDeadline() async throws {
        let client = client { _ in self.progress("layout", 1, 100, retryAfter: "-5") }
        let pauses = Recorder<Duration>()
        do {
            _ = try await run(client, deadline: .seconds(10), pauses: pauses)
            XCTFail("expected a throw")
        } catch {
            XCTAssertEqual(error as? ClientError, .unreachable("the Mac did not finish preparing this book in time"))
        }
        XCTAssertEqual(pauses.all.reduce(.zero, +), .seconds(10))
    }

    func testTheDeadlineEndsAStuckPass() async throws {
        let client = client { _ in self.progress("layout", 1, 100) }
        let pauses = Recorder<Duration>()
        do {
            _ = try await run(client, deadline: .seconds(10), pauses: pauses)
            XCTFail("expected a throw")
        } catch {
            XCTAssertEqual(error as? ClientError, .unreachable("the Mac did not finish preparing this book in time"))
        }
        XCTAssertLessThanOrEqual(StubURLProtocol.requests.count, 10 / 2 + 1)
        XCTAssertEqual(pauses.all.reduce(.zero, +), .seconds(10))
    }

    func testCancellationStopsThePoll() async throws {
        let client = client { _ in self.progress("layout", 1, 100) }
        let firstProgress = expectation(description: "first 202 reported")
        let task = Task {
            try await client.downloadReflow(
                id: "book1",
                pause: { try await Task.sleep(for: $0) },
                onProgress: { _ in firstProgress.fulfill() }
            )
        }
        await fulfillment(of: [firstProgress], timeout: 5)
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("expected cancellation")
        } catch {
            XCTAssertTrue(error is CancellationError, "got \(error)")
        }
        let count = StubURLProtocol.requests.count
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(StubURLProtocol.requests.count, count, "no request after cancel")
        XCTAssertEqual(count, 1)
    }
}
