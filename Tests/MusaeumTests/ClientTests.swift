import XCTest

@testable import Musaeum

/// What the client asks for, and what it does with each answer.
///
/// The routes and parameters are the contract's own (`../musaeum/docs/rest-api.md`),
/// and the statuses are its failure table: the point of these cases is that a
/// refusal is *distinguished* rather than collapsed into one error.
final class ClientTests: XCTestCase {
    private let base = URL(string: "http://100.64.0.1:8788")!

    private func fixture(_ name: String) -> Data {
        let bundle = Bundle(for: ClientTests.self)
        guard let url = bundle.url(forResource: name, withExtension: "json"),
              let data = try? Data(contentsOf: url)
        else { return Data("{}".utf8) }
        return data
    }

    private func client(_ handler: @escaping (URLRequest) -> StubURLProtocol.Response) -> MusaeumClient {
        StubURLProtocol.configure(handler)
        return MusaeumClient(base: base, token: "test-token", session: StubURLProtocol.session())
    }

    // MARK: AC5 — the requests the contract names, and only those

    func testHealthRequestCarriesTheBearerToken() async throws {
        let client = client { _ in
            StubURLProtocol.Response(status: 200, body: self.fixture("health"))
        }
        _ = try await client.health()
        let request = try XCTUnwrap(StubURLProtocol.requests.first)
        XCTAssertEqual(request.url?.path, "/api/health")
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-token")
    }

    /// **A Mac that is off the network must be decided in seconds, not a minute.**
    /// With the tailnet down the tailnet address is not refused, it is silent, and
    /// on the session's default 60 s the library sat on a spinner for that long.
    func testHealthRequestGivesUpQuickly() async throws {
        let client = client { _ in
            StubURLProtocol.Response(status: 200, body: self.fixture("health"))
        }
        _ = try await client.health()
        let request = try XCTUnwrap(StubURLProtocol.requests.first)
        XCTAssertEqual(request.timeoutInterval, MusaeumClient.healthTimeout)
        XCTAssertLessThanOrEqual(MusaeumClient.healthTimeout, 5)
    }

    func testLibraryRequestCarriesTheContractsDefaultWindow() async throws {
        let client = client { _ in StubURLProtocol.Response(status: 200, body: self.fixture("library")) }
        _ = try await client.library()
        let request = try XCTUnwrap(StubURLProtocol.requests.first)
        XCTAssertEqual(request.url?.path, "/api/library")
        let query = queryItems(request)
        XCTAssertEqual(query["limit"], "100")
        XCTAssertEqual(query["offset"], "0")
        XCTAssertNil(query["q"], "an unfiltered page is the whole library, not a search")
    }

    func testLibraryRequestCarriesSearchSortAndDirection() async throws {
        let client = client { _ in StubURLProtocol.Response(status: 200, body: self.fixture("library")) }
        _ = try await client.library(limit: 50, offset: 100, sort: "author", direction: "desc", query: "dune")
        let query = queryItems(try XCTUnwrap(StubURLProtocol.requests.first))
        XCTAssertEqual(query["limit"], "50")
        XCTAssertEqual(query["offset"], "100")
        XCTAssertEqual(query["sort"], "author")
        XCTAssertEqual(query["dir"], "desc")
        XCTAssertEqual(query["q"], "dune")
    }

    func testBookDetailRequestAsksByID() async throws {
        let client = client { _ in StubURLProtocol.Response(status: 200, body: self.fixture("book")) }
        _ = try await client.book(id: "6f1a1f2e")
        XCTAssertEqual(StubURLProtocol.requests.first?.url?.path, "/api/books/6f1a1f2e")
    }

    /// Covers are fixed filenames on the server, so the version the payload
    /// carries is what stops a replaced cover being answered from a cache — the
    /// defect the Mac app found the hard way on 2026-09-21.
    func testCoverRequestCarriesTheVersionAndSize() async throws {
        let client = client { _ in StubURLProtocol.Response(status: 200, body: Data([0xFF, 0xD8])) }
        _ = try await client.cover(id: "abc", size: "full", version: "2026-09-21T09:12:00.000Z")
        let query = queryItems(try XCTUnwrap(StubURLProtocol.requests.first))
        XCTAssertEqual(query["size"], "full")
        XCTAssertEqual(query["v"], "2026-09-21T09:12:00.000Z")
        XCTAssertEqual(StubURLProtocol.requests.first?.url?.path, "/api/books/abc/cover")
    }

    /// A book is asked for by **id and format**, never by path: the wire
    /// deliberately does not carry one (invariant 2).
    func testFileRequestAsksByIDAndFormat() async throws {
        let client = client { _ in StubURLProtocol.Response(status: 200, body: Data([0x50])) }
        _ = try await client.download(id: "abc", format: "epub")
        let request = try XCTUnwrap(StubURLProtocol.requests.first)
        XCTAssertEqual(request.url?.path, "/api/books/abc/file")
        XCTAssertEqual(queryItems(request)["format"], "epub")
    }

    // MARK: The upload's request — the second write

    /// What the wire sees for an upload: the contract's two parameters, the bearer
    /// header, and **nothing else**. No body on the request and no `Content-Type` —
    /// the bytes travel as the session's *file* and the route does not read a type,
    /// so inventing one would be this client describing a shape the contract does
    /// not name. AC1's other half (that the body really is a file the session reads
    /// rather than bytes in memory) is `UploadTests`'s, where the stream is read.
    func testUploadRequestCarriesTheContractsParametersAndNothingElse() async throws {
        let file = try temporaryFile(named: "The Expanse.epub", bytes: 32)
        let client = client { _ in StubURLProtocol.Response(status: 201, body: self.fixture("import")) }
        _ = try await client.uploadBook(file: file, format: "epub", filename: "The Expanse.epub")

        let request = try XCTUnwrap(StubURLProtocol.requests.first)
        XCTAssertEqual(request.url?.path, "/api/books")
        XCTAssertEqual(request.httpMethod, "POST")
        let query = queryItems(request)
        XCTAssertEqual(query["format"], "epub")
        XCTAssertEqual(query["filename"], "The Expanse.epub")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-token")
        XCTAssertNil(request.httpBody, "the bytes are the session's file, not a body this client built")
        // **The client composes no `Content-Type`, and that is the whole claim**:
        // the route says it does not read one, so a type from this app would be a
        // shape the contract does not name. `URLSession` adds its own
        // `application/octet-stream` for an upload without one, which the route
        // ignores — so the assertion is on the composer, not on the wire.
        XCTAssertNil(
            MusaeumClient.uploadRequest(base: base, token: "t", format: "epub", filename: "book.epub")
                .value(forHTTPHeaderField: "Content-Type")
        )
    }

    // MARK: AC4 — the contract version is refused when it moves

    func testAnUnknownContractVersionIsRefusedByName() async throws {
        let moved = """
        {"apiVersion":2,"version":"0.2.0","books":1,"library":"online"}
        """.data(using: .utf8)!
        let client = client { _ in StubURLProtocol.Response(status: 200, body: moved) }
        do {
            _ = try await client.health()
            XCTFail("a version this app does not speak must be refused")
        } catch let error as ClientError {
            XCTAssertEqual(error, .unsupportedAPIVersion(2))
        }
    }

    func testTheContractVersionThisAppSpeaksIsAccepted() async throws {
        let client = client { _ in StubURLProtocol.Response(status: 200, body: self.fixture("health")) }
        let health = try await client.health()
        XCTAssertEqual(health.apiVersion, 1)
    }

    // MARK: AC6 — the failures are distinguished, not collapsed

    func testUnauthorizedIsItsOwnOutcome() async throws {
        let client = client { _ in
            StubURLProtocol.Response(
                status: 401,
                headers: ["WWW-Authenticate": "Bearer"],
                body: Data(#"{"error":"unauthorized"}"#.utf8)
            )
        }
        await XCTAssertThrowsErrorAsync(try await client.health()) { error in
            XCTAssertEqual(error as? ClientError, .unauthorized)
            XCTAssertTrue((error as? ClientError)?.isCredentialProblem == true)
        }
    }

    func testBusyIsRetryableAndCarriesItsRetryAfter() async throws {
        let client = client { _ in
            StubURLProtocol.Response(
                status: 503,
                headers: ["Retry-After": "1"],
                body: Data(#"{"error":"busy"}"#.utf8)
            )
        }
        await XCTAssertThrowsErrorAsync(try await client.facets()) { error in
            XCTAssertEqual(error as? ClientError, .busy(retryAfter: 1))
            XCTAssertTrue((error as? ClientError)?.isRetryable == true)
        }
    }

    func testTheShareBeingOfflineIsItsOwnOutcome() async throws {
        let client = client { _ in
            StubURLProtocol.Response(
                status: 503,
                headers: ["Retry-After": "5"],
                body: Data(#"{"error":"library offline"}"#.utf8)
            )
        }
        await XCTAssertThrowsErrorAsync(try await client.facets()) { error in
            XCTAssertEqual(error as? ClientError, .libraryOffline(retryAfter: 5))
        }
    }

    func testNotFoundAndServerAndBadRequestAreDistinct() async throws {
        let cases: [(Int, Data, ClientError)] = [
            (404, Data(#"{"error":"not found"}"#.utf8), .notFound),
            (500, Data(#"{"error":"internal"}"#.utf8), .server),
            (400, Data(#"{"error":"bad request"}"#.utf8), .badRequest("bad request")),
            (416, Data(#"{"error":"range not satisfiable"}"#.utf8), .rangeNotSatisfiable),
        ]
        for (status, body, expected) in cases {
            let client = client { _ in StubURLProtocol.Response(status: status, body: body) }
            await XCTAssertThrowsErrorAsync(try await client.facets()) { error in
                XCTAssertEqual(error as? ClientError, expected, "status \(status)")
            }
        }
    }

    /// **A status `musaeum`'s own slice 2 added, which this client had no case
    /// for — so this case pins a defect that shipped.** `mapStatus`'s `default` is
    /// `unreachable`, whose own documentation is *"the Mac is asleep, off the
    /// tailnet, or the app is closed"* and which **is retryable**: an oversized
    /// upload was therefore reported to the reader as a Mac that had not answered,
    /// and then sent again, indefinitely, on a file that can never fit.
    ///
    /// **Both halves in one case on purpose**: a status mapped to its own outcome
    /// and then retried anyway is the same bug with a better message.
    func testContentTooLargeIsItsOwnOutcomeAndIsNotRetried() throws {
        let http = try XCTUnwrap(
            HTTPURLResponse(url: base, statusCode: 413, httpVersion: "HTTP/1.1", headerFields: [:])
        )
        XCTAssertThrowsError(
            try MusaeumClient.mapStatus(http, body: Data(#"{"error":"content too large"}"#.utf8))
        ) { error in
            XCTAssertEqual(error as? ClientError, .tooLarge)
        }
        XCTAssertFalse(ClientError.tooLarge.isRetryable, "the same bytes cannot fit on a second attempt")
        XCTAssertTrue(
            ClientError.tooLarge.description.contains("content too large"),
            "the row's words are the contract's own"
        )
    }

    /// The Mac asleep is the ordinary case, not an exception (D14).
    func testAnUnreachableServerIsAnOrdinaryOutcome() async throws {
        // A port nothing listens on: the app's own story for "the Mac is shut".
        let client = MusaeumClient(base: URL(string: "http://127.0.0.1:9")!, token: "x")
        await XCTAssertThrowsErrorAsync(try await client.health()) { error in
            guard case .unreachable = error as? ClientError else {
                return XCTFail("expected an unreachable outcome, got \(error)")
            }
        }
    }

    // MARK: decoding

    func testAPayloadThatDoesNotMatchTheContractIsARefusalNotANilTitle() async throws {
        let client = client { _ in
            StubURLProtocol.Response(status: 200, body: Data(#"{"id":"x","title":"t"}"#.utf8))
        }
        await XCTAssertThrowsErrorAsync(try await client.book(id: "x")) { error in
            guard case .decoding = error as? ClientError else {
                return XCTFail("expected a decoding refusal, got \(error)")
            }
        }
    }

    private func queryItems(_ request: URLRequest) -> [String: String] {
        let items = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
        return Dictionary(items.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { a, _ in a })
    }

    /// A picked book, as a path the app can read directly.
    private func temporaryFile(named name: String, bytes: Int) throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("musaeum-client-\(UUID().uuidString)-\(name)")
        try Data(repeating: 0x45, count: bytes).write(to: url)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
}

/// `XCTAssertThrowsError` has no async twin that hands back the error.
func XCTAssertThrowsErrorAsync<T>(
    _ expression: @autoclosure () async throws -> T,
    file: StaticString = #filePath,
    line: UInt = #line,
    _ handler: (any Error) -> Void
) async {
    do {
        _ = try await expression()
        XCTFail("expected this to throw", file: file, line: line)
    } catch {
        handler(error)
    }
}
