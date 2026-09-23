import XCTest

@testable import Musaeum

/// The library model over a stubbed server: **what each request carries** (the
/// narrowing has to ride on every page, not only the first), what a superseded
/// search does with the answer that arrives late, the two "nothing to show"
/// screens, and the funnel that remembers a sort and nothing else.
///
/// `nonisolated` on every helper that builds a stub is not taste. This class is
/// `@MainActor`, so a closure written inside one of its methods **inherits** that
/// isolation — and `StubURLProtocol` calls its handler from a background thread,
/// where the inherited isolation asserts the queue (`dispatch_assert_queue_fail`,
/// SIGTRAP) and takes the whole test host down. The owner reads that as *"the app
/// quit"*, not as a failed case (slice 1's trap 2; the same note is on
/// `LibraryPagingTests`).
@MainActor
final class LibraryQueryTests: XCTestCase {
    private let base = URL(string: "http://127.0.0.1:8788")!

    // MARK: Fixtures and stubs

    private nonisolated func fixture(_ name: String) throws -> Data {
        let bundle = Bundle(for: LibraryQueryTests.self)
        guard let url = bundle.url(forResource: name, withExtension: "json") else {
            throw XCTSkip("no \(name).json in the test bundle — run scripts/vendor-contract-fixtures.sh")
        }
        return try Data(contentsOf: url)
    }

    /// A page shaped like the contract's own `library` payload, built **from the
    /// golden** so every always-present field stays present: the decoder is strict,
    /// and a hand-typed book would be a second hand-copy of the wire.
    private nonisolated func page(ids: [String], total: Int, offset: Int = 0) throws -> Data {
        var object = try JSONSerialization.jsonObject(with: fixture("library")) as! [String: Any]
        let golden = (object["books"] as! [[String: Any]])[0]
        object["books"] = ids.enumerated().map { index, id in
            var book = golden
            book["id"] = id
            book["title"] = "Book \(index + 1)"
            return book
        }
        object["total"] = total
        object["offset"] = offset
        return try JSONSerialization.data(withJSONObject: object)
    }

    private struct Answer: Sendable {
        var body: Data
        var delay: TimeInterval = 0
    }

    /// One handler keyed by the **term** a request carried (no term reads as `""`),
    /// so a single stub answers a library page, a search, and the same search twice
    /// with different latencies.
    private nonisolated func stub(byTerm answers: [String: Answer]) throws {
        let health = try fixture("health")
        StubURLProtocol.configure { request in
            guard let url = request.url, !url.path.hasSuffix("/api/health") else {
                return StubURLProtocol.Response(status: 200, body: health)
            }
            let term = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first { $0.name == "q" }?.value ?? ""
            guard let answer = answers[term] else {
                return StubURLProtocol.Response(status: 200, body: Data())
            }
            return StubURLProtocol.Response(status: 200, body: answer.body, delay: answer.delay)
        }
    }

    /// The paging case needs the **offset** as well as the term: a search's first
    /// page and its second are different requests and have to be answerable apart.
    private nonisolated func stubPages(first: Data, second: Data) throws {
        let health = try fixture("health")
        StubURLProtocol.configure { request in
            guard let url = request.url, !url.path.hasSuffix("/api/health") else {
                return StubURLProtocol.Response(status: 200, body: health)
            }
            let offset = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first { $0.name == "offset" }?.value
            return StubURLProtocol.Response(status: 200, body: offset == "0" ? first : second)
        }
    }

    private nonisolated func query(_ request: URLRequest) -> [String: String] {
        let items = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
        return items.reduce(into: [:]) { $0[$1.name] = $1.value }
    }

    private nonisolated func libraryRequests() -> [URLRequest] {
        StubURLProtocol.requests.filter { $0.url?.path.hasSuffix("/api/library") == true }
    }

    private func makeModel(
        sort: LibrarySort = .default,
        persistSort: @escaping (LibrarySort) -> Void = { _ in }
    ) -> LibraryModel {
        LibraryModel(
            client: MusaeumClient(base: base, token: "t", session: StubURLProtocol.session()),
            sort: sort,
            persistSort: persistSort
        )
    }

    // MARK: 3.3 — the narrowing rides on every page

    func testTheSearchAndTheSortRideOnThePageAfterTheFirstToo() async throws {
        try stubPages(
            first: try page(ids: ["a", "b"], total: 3),
            second: try page(ids: ["c"], total: 3, offset: 2)
        )
        let model = makeModel(sort: LibrarySort(field: .author, direction: .desc))

        await model.search("dune")
        XCTAssertEqual(model.books.map(\.id), ["a", "b"])
        await model.loadNextPageIfNeeded(current: try XCTUnwrap(model.books.last))

        XCTAssertEqual(model.books.map(\.id), ["a", "b", "c"], "the page after the first arrived at all")
        let requests = libraryRequests()
        XCTAssertEqual(requests.count, 2)
        for request in requests {
            let items = query(request)
            XCTAssertEqual(items["sort"], "author", "the sort rides every page, not only the first")
            XCTAssertEqual(items["dir"], "desc")
            XCTAssertEqual(items["q"], "dune", "page two of a search is a search, not row 101 of the library")
            XCTAssertEqual(items["limit"], "100")
        }
        XCTAssertEqual(query(requests[0])["offset"], "0")
        XCTAssertEqual(query(requests[1])["offset"], "2")
    }

    // MARK: 3.4 — whitespace is not a term

    func testAWhitespaceOnlyQueryIsSentAsNoTermAtAll() async throws {
        try stub(byTerm: ["": Answer(body: try page(ids: ["a"], total: 1))])
        let model = makeModel()

        await model.search("   ")

        let request = try XCTUnwrap(libraryRequests().first)
        XCTAssertNil(query(request)["q"], "whitespace is not a term this client composes")
        XCTAssertFalse(model.query.isSearching)
        XCTAssertEqual(model.resultCountLabel, "1 book", "the whole library, not a search of it")
    }

    // MARK: 3.5 — a superseded search does not land

    func testASupersededSearchDoesNotPaintItsAnswerOverTheNewerOne() async throws {
        try stub(byTerm: [
            "slow": Answer(body: try page(ids: ["slow"], total: 1), delay: 0.6),
            "fast": Answer(body: try page(ids: ["fast"], total: 1), delay: 0.05),
        ])
        let model = makeModel()

        // The older search goes first; the newer one supersedes it while it is
        // still in flight, which is one keystroke past another on a tailnet.
        let older = Task { await model.search("slow") }
        try await Task.sleep(for: .milliseconds(80))
        await model.search("fast")
        XCTAssertEqual(model.books.map(\.id), ["fast"])

        _ = await older.value
        // Long enough for the superseded answer to have arrived and been dropped.
        try await Task.sleep(for: .milliseconds(800))

        XCTAssertEqual(model.books.map(\.id), ["fast"], "the older search answered last and must not paint")
        XCTAssertEqual(model.total, 1)
        XCTAssertEqual(model.phase, .loaded, "a superseded answer must not leave the screen loading")

        // **The control**, without which this case would pass on a client that sent
        // one request: both really went out, so what it decides is a race.
        let terms = Set(libraryRequests().compactMap { query($0)["q"] })
        XCTAssertEqual(terms, Set(["slow", "fast"]))
    }

    // MARK: 3.6 — the two "nothing to show" screens

    func testAnEmptyLibraryAndASearchThatMatchedNothingAreDifferentScreens() async throws {
        try stub(byTerm: [
            "": Answer(body: try page(ids: [], total: 0)),
            "zzz": Answer(body: try page(ids: [], total: 0)),
            "dune": Answer(body: try page(ids: ["a", "b"], total: 2)),
        ])
        let model = makeModel()

        await model.start()
        XCTAssertEqual(model.emptyState, .libraryIsEmpty, "the Mac reports no books at all")
        XCTAssertEqual(model.resultCountLabel, "0 books")

        await model.search("zzz")
        XCTAssertEqual(model.emptyState, .noMatches("zzz"), "the library has books; this term matched none")
        XCTAssertEqual(model.resultCountLabel, "0 matches", "and the count says matches, not books")

        await model.search("dune")
        XCTAssertNil(model.emptyState, "there is something to show")
        XCTAssertEqual(model.resultCountLabel, "2 matches")
        XCTAssertEqual(model.books.map(\.id), ["a", "b"])
    }

    // MARK: 3.7 — a sort is remembered, and a search is not

    func testChoosingASortRemembersItAndSearchingRemembersNothing() async throws {
        try stub(byTerm: [
            "": Answer(body: try page(ids: ["a"], total: 1)),
            "dune": Answer(body: try page(ids: ["a"], total: 1)),
        ])
        let defaults = UserDefaults(suiteName: "musaeum-tests-\(UUID().uuidString)")!
        let settings = SettingsStore(defaults: defaults, keychain: KeychainStore(service: "dev.jasonoh.Musaeum.tests"))
        let model = makeModel(sort: settings.librarySort, persistSort: { settings.save(librarySort: $0) })

        await model.search("dune")
        await model.chooseSort(LibrarySort(field: .author, direction: .desc))

        XCTAssertEqual(settings.librarySort, LibrarySort(field: .author, direction: .desc), "choosing is remembering")
        let last = try XCTUnwrap(libraryRequests().last)
        XCTAssertEqual(query(last)["sort"], "author", "and the new order went to the server as well")
        XCTAssertEqual(query(last)["q"], "dune", "the search survived the sort change")

        // **And nothing else was written.** The criterion is "*the query* is not
        // remembered", and asserted one key at a time it would pass while a second
        // key was written beside the first — so the container is compared whole.
        let written = Set(defaults.dictionaryRepresentation().keys.filter { $0.hasPrefix("musaeum.") })
        XCTAssertEqual(written, Set(["musaeum.librarySort"]), "the sort is the only thing this screen persists")
    }

    /// The other half of the same rule: a choice that changes nothing must not cost
    /// a request, and must not be recorded as a fresh preference.
    func testTheOrderAlreadyInForceAndAnEmptySearchAskForNothing() async throws {
        try stub(byTerm: ["": Answer(body: try page(ids: ["a"], total: 1))])
        var persisted: [LibrarySort] = []
        let model = makeModel(persistSort: { persisted.append($0) })

        await model.start()
        let before = libraryRequests().count

        await model.chooseSort(model.query.sort)
        await model.search("")

        XCTAssertEqual(libraryRequests().count, before, "neither asked the Mac for anything")
        XCTAssertTrue(persisted.isEmpty, "and neither recorded a preference")
    }
}
