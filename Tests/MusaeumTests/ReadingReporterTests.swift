import XCTest

@testable import Musaeum

private let reporterBase = URL(string: "http://127.0.0.1:8788")!
/// A port nothing listens on: the app's own story for "the Mac is shut" (D14), and
/// the same instrument `ClientTests` uses for an unreachable server.
private let asleepBase = URL(string: "http://127.0.0.1:9")!

/// The reporter: what happens to a report, in order, when the Mac is asleep, when
/// it wakes, and when it no longer holds the book.
///
/// **Every helper that defines a stub closure is `nonisolated`, and not by taste.**
/// This class is `@MainActor`, so a closure written inside one of its methods
/// *inherits* that isolation — and `StubURLProtocol` calls its handler from a
/// background thread, where the inherited isolation is an assertion that fails as
/// `dispatch_assert_queue_fail` / SIGTRAP and takes the whole test host down. It
/// reads as "the app quit" rather than as a failed case. Slice 1 paid for this one;
/// the note is here so slice 3 does not.
@MainActor
final class ReadingReporterTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("musaeum-reporter-\\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    // MARK: helpers

    private nonisolated func fixture(_ name: String) throws -> Data {
        let bundle = Bundle(for: ReadingReporterTests.self)
        guard let url = bundle.url(forResource: name, withExtension: "json") else {
            throw XCTSkip("no \\(name).json in the test bundle — run scripts/vendor-contract-fixtures.sh")
        }
        return try Data(contentsOf: url)
    }

    /// An answer shaped like the contract's own `reading` payload, built **from the
    /// golden** so every always-present field stays present (the decoder is strict).
    private nonisolated func reply(id: String, applied: Bool = true, percent: Double = 0.42) throws -> Data {
        var object = try JSONSerialization.jsonObject(with: fixture("reading")) as! [String: Any]
        var book = object["book"] as! [String: Any]
        var reading = book["reading"] as! [String: Any]
        book["id"] = id
        reading["percent"] = percent
        book["reading"] = reading
        object["book"] = book
        object["applied"] = applied
        return try JSONSerialization.data(withJSONObject: object)
    }

    private nonisolated func notFound() -> StubURLProtocol.Response {
        StubURLProtocol.Response(status: 404, body: Data(#"{"error":"not found"}"#.utf8))
    }

    /// Answers one per request, in order — so a case decides what a *flush* does
    /// when the Mac takes the first report and refuses the second. `startLoading`
    /// logs the request before it asks the handler, so the last entry in the log is
    /// the request being answered.
    private nonisolated func stubAnswering(_ answers: [StubURLProtocol.Response]) {
        StubURLProtocol.configure { _ in
            let index = StubURLProtocol.requests.count - 1
            guard answers.indices.contains(index) else {
                return StubURLProtocol.Response(status: 200, body: Data())
            }
            return answers[index]
        }
    }

    private nonisolated func awakeClient() -> MusaeumClient {
        MusaeumClient(base: reporterBase, token: "t", session: StubURLProtocol.session())
    }

    private nonisolated func asleepClient() -> MusaeumClient {
        MusaeumClient(base: asleepBase, token: "t")
    }

    /// The body a request actually carried. `URLSession` turns a request with an
    /// `httpBody` into an upload task, and a `URLProtocol` then sees the bytes on the
    /// **stream** rather than on the property — so a case that read `httpBody` alone
    /// would silently assert nothing at all.
    private nonisolated func body(of request: URLRequest) -> [String: Any]? {
        var data = request.httpBody
        if data == nil, let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var collected = Data()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let read = stream.read(&buffer, maxLength: buffer.count)
                if read <= 0 { break }
                collected.append(buffer, count: read)
            }
            data = collected.isEmpty ? nil : collected
        }
        guard let data else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private nonisolated func bookIds(_ requests: [URLRequest]) -> [String] {
        requests.compactMap { request in
            guard let path = request.url?.path else { return nil }
            let parts = path.split(separator: "/")
            guard parts.count == 4 else { return nil }
            return String(parts[2])
        }
    }

    // MARK: AC 2.2 — queued, not lost, and gone once the Mac answers

    func testAReportMadeWhileTheMacIsAsleepIsKeptAndFlushedWhenItAnswers() async throws {
        let queue = ReportQueue(root: root)
        let reporter = ReadingReporter(queue: queue)

        await reporter.report(bookId: "abc", percent: 0.42, to: asleepClient())

        XCTAssertEqual(queue.reports.count, 1, "the reading is kept, not lost")
        let kept = try XCTUnwrap(queue.reports.first)
        XCTAssertEqual(kept.bookId, "abc")
        XCTAssertEqual(kept.percent, 0.42)

        stubAnswering([StubURLProtocol.Response(status: 200, body: try reply(id: "abc"))])
        await reporter.flush(to: awakeClient())

        XCTAssertTrue(queue.isEmpty, "the queue is empty once the Mac answers")
        XCTAssertEqual(reporter.pending.count, 0)
    }

    /// The same report kept **across a relaunch**: a store, a reporter and a queue
    /// reopened over the same directory is what the next launch looks like.
    func testAQueuedReportIsStillThereAfterARelaunch() async throws {
        await ReadingReporter(queue: ReportQueue(root: root))
            .report(bookId: "abc", percent: 0.42, to: asleepClient())

        let reopened = ReadingReporter(queue: ReportQueue(root: root))
        XCTAssertEqual(reopened.pending.count, 1)

        stubAnswering([StubURLProtocol.Response(status: 200, body: try reply(id: "abc"))])
        await reopened.flush(to: awakeClient())
        XCTAssertTrue(ReadingReporter(queue: ReportQueue(root: root)).pending.isEmpty)
    }

    /// An unconfigured app has no client at all, and the reading still happened.
    func testAReportWithNoServerConfiguredIsKeptRatherThanDropped() async {
        let queue = ReportQueue(root: root)
        await ReadingReporter(queue: queue).report(bookId: "abc", percent: 0.42, to: nil)
        XCTAssertEqual(queue.reports.map(\.bookId), ["abc"])
    }

    // MARK: AC 2.3 — oldest first, and the clock travels only on a flush

    func testAQueueOfThreeFlushesOldestFirstCarryingEachReportsOwnClock() async throws {
        let queue = ReportQueue(root: root)
        let reporter = ReadingReporter(queue: queue)
        let asleep = asleepClient()

        let times = try ["2026-09-22T09:00:00.000Z", "2026-09-22T09:05:00.000Z", "2026-09-22T09:10:00.000Z"]
            .map { try ISO8601.parse($0, field: "test") }
        // Written out rather than derived: `0.1 * 3` is `0.30000000000000004`, and a
        // case that asserted its own float arithmetic would be deciding nothing.
        let fractions = [0.1, 0.2, 0.3]
        for (index, bookId) in ["a", "b", "c"].enumerated() {
            await reporter.report(bookId: bookId, percent: fractions[index], at: times[index], to: asleep)
        }
        XCTAssertEqual(queue.reports.map(\.bookId), ["a", "b", "c"], "queued in the order the readings happened")

        stubAnswering([
            StubURLProtocol.Response(status: 200, body: try reply(id: "a")),
            StubURLProtocol.Response(status: 200, body: try reply(id: "b")),
            StubURLProtocol.Response(status: 200, body: try reply(id: "c")),
        ])
        await reporter.flush(to: awakeClient())

        XCTAssertTrue(queue.isEmpty)
        let requests = StubURLProtocol.requests
        XCTAssertEqual(bookIds(requests), ["a", "b", "c"], "oldest first, so the last write carries the newest position")

        let sent = requests.compactMap(body(of:))
        XCTAssertEqual(sent.count, 3)
        XCTAssertEqual(sent.map { $0["percent"] as? Double }, fractions)
        XCTAssertEqual(
            sent.map { $0["at"] as? String },
            times.map(ISO8601.string),
            "a queued report carries the time it was **read** — the Mac's D6 compares it against its own row"
        )
    }

    /// The other half of the same distinction, and the one a live server cannot
    /// show: a report the Mac can take straight away goes out with **no clock**, so
    /// the Mac's own is the truth.
    func testALiveReportReachesTheMacWithoutItsClock() async throws {
        let queue = ReportQueue(root: root)
        let reporter = ReadingReporter(queue: queue)

        stubAnswering([StubURLProtocol.Response(status: 200, body: try reply(id: "abc"))])
        await reporter.report(bookId: "abc", percent: 0.42, to: awakeClient())

        let request = try XCTUnwrap(StubURLProtocol.requests.first)
        XCTAssertEqual(request.httpMethod, "PUT")
        XCTAssertEqual(Set(try XCTUnwrap(body(of: request)).keys), ["percent"], "no `at` on a live read")
        XCTAssertTrue(queue.isEmpty, "an accepted report does not sit in the queue")
    }

    // MARK: AC 2.4 — a book the Mac no longer holds, and a Mac that is not taking reports

    func testAQueuedReportForABookTheMacNoLongerHoldsIsDroppedNotRetried() async throws {
        let queue = ReportQueue(root: root)
        let reporter = ReadingReporter(queue: queue)
        let asleep = asleepClient()
        for bookId in ["kept", "gone", "also-kept"] {
            await reporter.report(bookId: bookId, percent: 0.5, to: asleep)
        }
        XCTAssertEqual(queue.reports.count, 3)

        stubAnswering([
            StubURLProtocol.Response(status: 200, body: try reply(id: "kept")),
            notFound(),
            StubURLProtocol.Response(status: 200, body: try reply(id: "also-kept")),
        ])
        await reporter.flush(to: awakeClient())

        XCTAssertTrue(queue.isEmpty, "the 404 was dropped, not retried for ever")
        XCTAssertEqual(
            bookIds(StubURLProtocol.requests),
            ["kept", "gone", "also-kept"],
            "the drop announced itself and the flush carried on past it"
        )
    }

    /// A flush against a Mac that is not answering must not walk the whole queue:
    /// three queued reports are one request, not three refusals.
    func testAFlushAgainstASleepingMacStopsAtTheFirstRefusal() async throws {
        let queue = ReportQueue(root: root)
        let reporter = ReadingReporter(queue: queue)
        let asleep = asleepClient()
        for bookId in ["a", "b", "c"] {
            await reporter.report(bookId: bookId, percent: 0.5, to: asleep)
        }

        stubAnswering([
            StubURLProtocol.Response(status: 503, headers: ["Retry-After": "1"], body: Data(#"{"error":"busy"}"#.utf8)),
        ])
        await reporter.flush(to: awakeClient())

        XCTAssertEqual(StubURLProtocol.requests.count, 1, "the first refusal is the answer; the rest wait")
        XCTAssertEqual(queue.reports.map(\.bookId), ["a", "b", "c"], "all three are still there, in order")
    }

    /// `200 { applied: false }` is the Mac's stale refusal (D6). Nothing failed, and
    /// nothing is retried: this report's own clock will never become newer than the
    /// row it lost to.
    func testARefusedAsStaleReportSettlesRatherThanRetrying() async throws {
        let queue = ReportQueue(root: root)
        queue.enqueue(ReadingReport(bookId: "abc", percent: 0.1, readAt: Date(timeIntervalSince1970: 0)))
        let reporter = ReadingReporter(queue: queue)

        stubAnswering([StubURLProtocol.Response(status: 200, body: try reply(id: "abc", applied: false, percent: 0.9))])
        await reporter.flush(to: awakeClient())

        XCTAssertTrue(queue.isEmpty)
        XCTAssertEqual(StubURLProtocol.requests.count, 1, "a refusal is not a reason to ask again with the same clock")
    }
}
