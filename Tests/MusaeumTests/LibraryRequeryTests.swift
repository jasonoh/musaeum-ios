import XCTest

@testable import Musaeum

/// **A re-query keeps the list on screen until its own page lands** — the fix for
/// the owner's *visual readjustment lag* of 2026-09-30, on every shelf switch.
///
/// Opening a shelf, leaving one, a sort, a filter and a settled keystroke all run
/// `LibraryModel.start()`, which used to empty the grid to a spinner for the whole
/// round trip and then pop every cover back in. These cases decide the model's
/// half of the replacement: what is on screen while the Mac is answering, what the
/// stale list may not do, and which covers ride over to the new list. The dimming
/// and the rebuilt grid are the view's half, and a unit test cannot see a screen.
///
/// `nonisolated` on every helper that builds a stub, for `LibraryPagingTests`'
/// recorded reason: `StubURLProtocol` calls its handler off the main thread, and a
/// closure inheriting this class's `@MainActor` isolation traps there.
@MainActor
final class LibraryRequeryTests: XCTestCase {
    private let base = URL(string: "http://127.0.0.1:8788")!

    /// Long enough that a case can look at the model mid-flight, short enough that
    /// the suite does not notice it.
    private nonisolated static let slow: TimeInterval = 0.8

    private nonisolated func fixture(_ name: String) throws -> Data {
        let bundle = Bundle(for: LibraryRequeryTests.self)
        guard let url = bundle.url(forResource: name, withExtension: "json") else {
            throw XCTSkip("no \(name).json in the test bundle — run scripts/vendor-contract-fixtures.sh")
        }
        return try Data(contentsOf: url)
    }

    /// A page built **from the golden**, as the other suites build theirs; each
    /// book is `(id, cover version)`.
    private nonisolated func page(_ books: [(String, String)], total: Int? = nil, isLast: Bool = true) throws -> Data {
        var object = try JSONSerialization.jsonObject(with: fixture("library")) as! [String: Any]
        let golden = (object["books"] as! [[String: Any]])[0]
        object["books"] = books.enumerated().map { index, pair in
            var book = golden
            book["id"] = pair.0
            book["title"] = "Book \(index + 1)"
            var cover = golden["cover"] as! [String: Any]
            cover["version"] = pair.1
            book["cover"] = cover
            return book
        }
        object["total"] = total ?? books.count
        object["offset"] = 0
        object["nextOffset"] = books.count
        object["isLastPage"] = isLast
        return try JSONSerialization.data(withJSONObject: object)
    }

    /// The unsearched library answers at once with `first`; a search answers
    /// `searched`, **slowly**. Covers answer with a byte each.
    private nonisolated func stub(first: Data, searched: Data) throws {
        let health = try fixture("health")
        StubURLProtocol.configure { request in
            guard let url = request.url else { return StubURLProtocol.Response(status: 500) }
            if url.path.hasSuffix("/api/health") { return StubURLProtocol.Response(body: health) }
            if url.path.hasSuffix("/cover") { return StubURLProtocol.Response(body: Data([0xFF])) }
            let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            if items.contains(where: { $0.name == "q" }) {
                return StubURLProtocol.Response(body: searched, delay: Self.slow)
            }
            return StubURLProtocol.Response(body: first)
        }
    }

    private func makeModel() -> LibraryModel {
        LibraryModel(
            client: MusaeumClient(base: base, token: "t", session: StubURLProtocol.session()),
            pipeline: CoverPipeline(session: StubURLProtocol.session())
        )
    }

    /// Long enough for the slow answer's request to be out, well short of its answer.
    private func midFlight() async throws {
        try await Task.sleep(for: .milliseconds(250))
    }

    func testTheListOnScreenStaysUntilTheNewPageLands() async throws {
        try stub(first: page([("a", "1"), ("b", "1")]), searched: page([("c", "1"), ("d", "1")]))
        let model = makeModel()
        await model.start()
        let landedBefore = model.landed
        XCTAssertFalse(model.isShowingStale)

        let search = Task { await model.search("dune") }
        try await midFlight()
        XCTAssertEqual(model.phase, .loaded, "no spinner: the list on screen is still a list")
        XCTAssertEqual(model.books.map(\.id), ["a", "b"], "the old answer stays until the new one lands")
        XCTAssertTrue(model.isShowingStale, "and it is marked as the old answer, so the grid can say so")
        XCTAssertEqual(model.landed, landedBefore, "nothing has landed, so the grid is not rebuilt yet")

        await search.value
        XCTAssertEqual(model.books.map(\.id), ["c", "d"])
        XCTAssertFalse(model.isShowingStale)
        XCTAssertFalse(model.isRefreshing)
        XCTAssertNotEqual(model.landed, landedBefore, "a landed page is a new list")
        XCTAssertEqual(model.shownQuery, model.query)
    }

    /// The stale list's last row must not fetch a page: composed from the *new*
    /// query, it would append the new question's rows to the old question's answer.
    func testAStaleListAsksForNoNextPage() async throws {
        try stub(first: page([("a", "1"), ("b", "1")], total: 3, isLast: false), searched: page([("c", "1")]))
        let model = makeModel()
        await model.start()
        XCTAssertTrue(model.hasMore)

        let search = Task { await model.search("dune") }
        try await midFlight()
        let before = StubURLProtocol.requests.count
        await model.loadNextPageIfNeeded(current: try XCTUnwrap(model.books.last))
        XCTAssertEqual(StubURLProtocol.requests.count, before, "no page for a list that is being replaced")

        await search.value
        XCTAssertEqual(model.books.map(\.id), ["c"])
    }

    /// An empty card is a sentence about its query, and the query has moved: it
    /// waits on the spinner as before rather than naming the new question over the
    /// old answer.
    func testAnEmptyCardDoesNotOutliveItsQuery() async throws {
        try stub(first: page([]), searched: page([("c", "1")]))
        let model = makeModel()
        await model.start()
        XCTAssertEqual(model.emptyState, .libraryIsEmpty)

        let search = Task { await model.search("dune") }
        try await midFlight()
        XCTAssertEqual(model.phase, .loading, "nothing to keep, so the spinner")
        XCTAssertFalse(model.isShowingStale)

        await search.value
        XCTAssertEqual(model.books.map(\.id), ["c"])
    }

    /// A cover in hand rides over to the new list **only while its version
    /// holds** — a cover the Mac replaced is asked for again — and only for books
    /// on the new page, so the cache stays one page's worth.
    func testCoversComeWithTheListOnlyWhileTheirVersionHolds() async throws {
        try stub(
            first: page([("a", "1"), ("b", "1"), ("gone", "1")]),
            searched: page([("a", "1"), ("b", "2"), ("new", "1")])
        )
        let model = makeModel()
        await model.start()
        for book in model.books { await model.cover(for: book) }
        XCTAssertEqual(Set(model.covers.keys), ["a", "b", "gone"])

        await model.search("dune")
        XCTAssertEqual(
            Set(model.covers.keys),
            ["a"],
            "a: same version, kept · b: replaced on the Mac, asked again · gone: not on the new page"
        )
    }
}
