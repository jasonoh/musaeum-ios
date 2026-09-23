import XCTest

@testable import Musaeum

/// What the client asks for, and what it does with each answer.
///
/// The routes and parameters are the contract's own (`../musaeum/docs/rest-api.md`),
/// and the statuses are its failure table: the point of these cases is that a
/// refusal is *distinguished* rather than collapsed into one error.
final class ClientTests: XCTestCase {
    private let base = URL(string: "http://100.125.135.108:8788")!

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
