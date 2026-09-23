import XCTest

@testable import Musaeum

/// The paging half of criterion 11: the library is a *paged* list, and the row
/// that reaches the end is what fetches the page after it.
///
/// The live probe cannot decide this one — the probe profile holds 8 books
/// against a page size of 100, so there is no second page for it to reach. The
/// decider is here: a stubbed two-page server and the model's own state.
@MainActor
final class LibraryPagingTests: XCTestCase {
    private let base = URL(string: "http://127.0.0.1:8788")!

    /// `nonisolated` on all three helpers, and not by taste: this class is
    /// `@MainActor`, so a closure written inside one of its methods **inherits**
    /// that isolation — and `StubURLProtocol` calls the handler from a background
    /// thread, where the inherited isolation is an assertion that fails as
    /// `dispatch_assert_queue_fail` / SIGTRAP. It takes the whole test-host app
    /// down with it, so it reads as "the app quit" rather than as a failed case.
    private nonisolated func fixture(_ name: String) throws -> Data {
        let bundle = Bundle(for: LibraryPagingTests.self)
        guard let url = bundle.url(forResource: name, withExtension: "json") else {
            throw XCTSkip("no \(name).json in the test bundle — run scripts/vendor-contract-fixtures.sh")
        }
        return try Data(contentsOf: url)
    }

    /// A page shaped like the contract's own `library` payload, built **from the
    /// golden** so every always-present field stays present (the decoder is
    /// strict, and a hand-typed book would be a second hand-copy of the wire).
    private nonisolated func page(ids: [String], total: Int, offset: Int, isLast: Bool) throws -> Data {
        var object = try JSONSerialization.jsonObject(with: fixture("library")) as! [String: Any]
        let golden = (object["books"] as! [[String: Any]])[0]
        var books: [[String: Any]] = []
        for (index, id) in ids.enumerated() {
            var book = golden
            book["id"] = id
            book["title"] = "Book \(index + 1)"
            books.append(book)
        }
        object["books"] = books
        object["total"] = total
        object["offset"] = offset
        object["nextOffset"] = offset + ids.count
        object["isLastPage"] = isLast
        return try JSONSerialization.data(withJSONObject: object)
    }

    private nonisolated func stub() throws {
        let first = try page(ids: ["a", "b"], total: 3, offset: 0, isLast: false)
        let second = try page(ids: ["c"], total: 3, offset: 2, isLast: true)
        let health = try fixture("health")
        StubURLProtocol.configure { request in
            guard let url = request.url, url.path.hasSuffix("/api/health") == false else {
                return StubURLProtocol.Response(status: 200, body: health)
            }
            let offset = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first { $0.name == "offset" }?.value
            return StubURLProtocol.Response(status: 200, body: offset == "0" ? first : second)
        }
    }

    func testTheLastRowFetchesThePageAfterIt() async throws {
        try stub()
        let model = LibraryModel(client: MusaeumClient(base: base, token: "t", session: StubURLProtocol.session()))

        await model.start()
        XCTAssertEqual(model.books.map(\.id), ["a", "b"])
        XCTAssertEqual(model.total, 3)
        XCTAssertTrue(model.hasMore, "two of three books are on screen")

        await model.loadNextPageIfNeeded(current: model.books.last!)
        XCTAssertEqual(model.books.map(\.id), ["a", "b", "c"])
        XCTAssertFalse(model.hasMore, "the server said this was the last page")
    }

    /// The other half of the same rule: a row that is *not* the last one must not
    /// fetch — a grid that asked on every cell would send 100 requests a page.
    func testARowThatIsNotTheLastOneAsksForNothing() async throws {
        try stub()
        let model = LibraryModel(client: MusaeumClient(base: base, token: "t", session: StubURLProtocol.session()))
        await model.start()

        let before = StubURLProtocol.requests.count
        await model.loadNextPageIfNeeded(current: model.books[0])
        XCTAssertEqual(StubURLProtocol.requests.count, before, "no request for a row that is not the last")
        XCTAssertEqual(model.books.map(\.id), ["a", "b"])
    }
}
