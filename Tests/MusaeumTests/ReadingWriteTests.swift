import XCTest

@testable import Musaeum

/// The one write, as the contract spells it: `PUT /api/books/{id}/reading`, a JSON
/// body, and the **`at`-only-for-a-queued-report** rule that is D6's whole client
/// half. Decided here rather than against a live server, because what a request
/// *carries* is not something a live run can show.
final class ReadingWriteTests: XCTestCase {
    private let base = URL(string: "http://100.64.0.1:8788")!

    private func fixture(_ name: String) -> Data {
        let bundle = Bundle(for: ReadingWriteTests.self)
        guard let url = bundle.url(forResource: name, withExtension: "json"),
              let data = try? Data(contentsOf: url)
        else { return Data("{}".utf8) }
        return data
    }

    private func client(_ handler: @escaping (URLRequest) -> StubURLProtocol.Response) -> MusaeumClient {
        StubURLProtocol.configure(handler)
        return MusaeumClient(base: base, token: "test-token", session: StubURLProtocol.session())
    }

    private func object(from data: Data) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    // MARK: AC 2.1 — the request the contract names

    func testAReportIsAPutToTheBooksReadingPath() async throws {
        let client = client { _ in StubURLProtocol.Response(status: 200, body: self.fixture("reading")) }
        let result = try await client.reportReading(id: "6f1a1f2e", percent: 0.42)

        let request = try XCTUnwrap(StubURLProtocol.requests.first)
        XCTAssertEqual(request.url?.path, "/api/books/6f1a1f2e/reading", "asked by id, as the read routes are")
        XCTAssertEqual(request.httpMethod, "PUT")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-token")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertTrue(result.applied)
        // The reply is the contract's own golden, so the book the client reads back
        // is the golden's book — the write route answers the same payload as the read.
        XCTAssertEqual(result.book.id, "6f1a1f2e-3c4d-4e5f-8a9b-0c1d2e3f4a5b")
        XCTAssertEqual(result.book.reading.percent, 0.42)
    }

    /// The contract's reply is the same `book` payload as the read surface, so the
    /// client can show what the Mac now holds without a second request.
    func testTheReplyIsTheBookAfterTheWrite() async throws {
        let client = client { _ in StubURLProtocol.Response(status: 200, body: self.fixture("reading")) }
        let result = try await client.reportReading(id: "x", percent: 0.42)
        XCTAssertTrue(result.applied)
        XCTAssertEqual(result.book.reading.status, .reading)
        XCTAssertEqual(result.book.reading.updatedAt, try ISO8601.parse("2026-09-21T09:12:00.000Z", field: "test"))
    }

    /// **`applied: false` is an answer, not a failure.** The Mac already holds a
    /// later position; nothing went wrong, and a client that threw here would retry
    /// a report its own clock will never make newer.
    func testAStaleRefusalIsAnAnswerRatherThanAFailure() async throws {
        var object = try self.object(from: fixture("reading"))
        object["applied"] = false
        let stale = try JSONSerialization.data(withJSONObject: object)

        let client = client { _ in StubURLProtocol.Response(status: 200, body: stale) }
        let result = try await client.reportReading(id: "x", percent: 0.1)
        XCTAssertFalse(result.applied)
    }

    // MARK: the body — absence is real absence

    /// A live read carries **`percent` alone**: the contract says to send `at` for a
    /// report that was queued and to omit it for a live read, so the Mac's own clock
    /// is the truth while its server is answering. A phone whose clock is behind
    /// would otherwise have its own report refused as stale.
    func testALiveReportOmitsTheClockAndAQueuedOneCarriesIt() throws {
        let live = try object(from: MusaeumClient.readingBody(percent: 0.42, at: nil))
        XCTAssertEqual(Set(live.keys), ["percent"], "a live read sends no `at` — not a null one, none")
        XCTAssertEqual(live["percent"] as? Double, 0.42)

        let readAt = try ISO8601.parse("2026-09-22T09:12:00.000Z", field: "test")
        let queued = try object(from: MusaeumClient.readingBody(percent: 0.42, at: readAt))
        XCTAssertEqual(Set(queued.keys), ["percent", "at"])
        XCTAssertEqual(queued["at"] as? String, "2026-09-22T09:12:00.000Z", "the contract's own ISO 8601, with milliseconds")
    }

    /// The contract refuses `60` rather than reading it as `0.6`, so the client
    /// clamps rather than sending something it knows will be refused — and an engine
    /// reporting `1.0000001` is a rounding artefact, not a reason to lose a reading.
    func testAFractionOutsideTheUnitIntervalIsClampedBeforeItIsSent() throws {
        XCTAssertEqual(try object(from: MusaeumClient.readingBody(percent: 60, at: nil))["percent"] as? Double, 1)
        XCTAssertEqual(try object(from: MusaeumClient.readingBody(percent: -0.2, at: nil))["percent"] as? Double, 0)
        XCTAssertEqual(try object(from: MusaeumClient.readingBody(percent: 1.0000001, at: nil))["percent"] as? Double, 1)
    }

    // MARK: the refusal rule — which of the three a failed attempt becomes

    /// The rule the whole queue rests on, decided as a table rather than as three
    /// separate stories: a refusal is either *transient*, *impossible*, or *stale*.
    func testTheContractsRefusalsAreSplitThreeWays() {
        XCTAssertEqual(ReportPolicy.disposition(.notFound), .dropped, "the Mac does not have that book, and never will")
        XCTAssertEqual(ReportPolicy.disposition(.badRequest("bad")), .dropped, "the body we composed is wrong; sent again it is wrong again")
        XCTAssertEqual(ReportPolicy.disposition(.unsupportedAPIVersion(2)), .dropped, "a contract version this app does not speak is not transient")

        XCTAssertEqual(ReportPolicy.disposition(.unreachable("no route to host")), .queued, "the Mac is asleep — the ordinary case (D14)")
        XCTAssertEqual(ReportPolicy.disposition(.busy(retryAfter: 1)), .queued)
        XCTAssertEqual(ReportPolicy.disposition(.libraryOffline(retryAfter: 5)), .queued)
        XCTAssertEqual(ReportPolicy.disposition(.server), .queued)
        XCTAssertEqual(ReportPolicy.disposition(.unauthorized), .queued, "a rotated token is fixable; the reading is not re-readable")
    }
}
