import XCTest

@testable import Musaeum

/// The shelf scope and the membership writes over a stubbed server: what each
/// request carries (the scope on **every** page), the Mac's default inside a
/// shelf and the restore on the way out, the capability probe's three states,
/// the membership method and path, and the sentences that belong to a scope.
///
/// `nonisolated` on every helper that builds a stub, for `LibraryQueryTests`'
/// own recorded reason: this class is `@MainActor`, a closure written inside one
/// of its methods **inherits** that isolation, and `StubURLProtocol` calls its
/// handler from a background thread — where the inherited isolation asserts the
/// queue (`dispatch_assert_queue_fail`, SIGTRAP) and takes the whole test host
/// down. The owner reads that as *"the app quit"*, not as a failed case.
@MainActor
final class ShelvesTests: XCTestCase {
    private let base = URL(string: "http://127.0.0.1:8788")!
    private let shelfId = "b2c3d4e5-6f70-4182-93a4-b5c6d7e8f901"
    private let bookId = "6f1a1f2e-3c4d-4e5f-8a9b-0c1d2e3f4a5b"

    // MARK: Fixtures and stubs

    private nonisolated func fixture(_ name: String) throws -> Data {
        let bundle = Bundle(for: ShelvesTests.self)
        guard let url = bundle.url(forResource: name, withExtension: "json") else {
            throw XCTSkip("no \(name).json in the test bundle — run scripts/vendor-contract-fixtures.sh")
        }
        return try Data(contentsOf: url)
    }

    /// A page shaped like the contract's own `library` payload, built **from the
    /// golden** so every always-present field stays present: the decoder is
    /// strict, and a hand-typed book would be a second hand-copy of the wire.
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

    /// The one shelf the golden names, as the model would hold it.
    private nonisolated func shelf() throws -> Shelf {
        try JSONDecoder().decode(Shelves.self, from: fixture("shelves")).shelves[0]
    }

    /// Answers health, the shelves route, the library and the membership path.
    /// `shelvesStatus` and `libraryStatus` are how a case makes the Mac a
    /// pre-shelves one, or a shelf that has gone.
    private nonisolated func stub(
        shelvesStatus: Int = 200,
        libraryStatus: Int = 200,
        page: Data,
        membershipStatus: Int = 200,
        membershipBody: Data? = nil
    ) throws {
        let health = try fixture("health")
        let shelves = try fixture("shelves")
        let membership = try membershipBody ?? fixture("membership")
        StubURLProtocol.configure { request in
            guard let url = request.url else { return StubURLProtocol.Response(status: 500) }
            if url.path.hasSuffix("/api/health") { return StubURLProtocol.Response(body: health) }
            if url.path.hasSuffix("/api/shelves") {
                return StubURLProtocol.Response(status: shelvesStatus, body: shelves)
            }
            if url.path.hasSuffix("/api/library") {
                return StubURLProtocol.Response(status: libraryStatus, body: page)
            }
            if url.path.contains("/api/shelves/") {
                return StubURLProtocol.Response(status: membershipStatus, body: membership)
            }
            return StubURLProtocol.Response(status: 404)
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

    private func makeClient() -> MusaeumClient {
        MusaeumClient(base: base, token: "t", session: StubURLProtocol.session())
    }

    // MARK: 7a — the scope

    func testTheScopeAndTheDefaultSortRideEveryPage() async throws {
        try stub(page: try page(ids: ["a", "b"], total: 3))
        let model = makeModel()
        await model.start()
        await model.loadShelves()
        XCTAssertEqual(model.shelvesSupported, true)
        XCTAssertEqual(model.shelves.map(\.id), [shelfId])

        let before = libraryRequests().count
        await model.openShelf(try shelf())
        XCTAssertEqual(model.query.sort, LibrarySort(field: .shelfAdded, direction: .desc))
        await model.loadNextPageIfNeeded(current: try XCTUnwrap(model.books.last))

        let scoped = Array(libraryRequests().dropFirst(before))
        XCTAssertEqual(scoped.count, 2, "the open and the page after it")
        for request in scoped {
            let items = query(request)
            XCTAssertEqual(items["shelf"], shelfId, "the scope rides every page, not only the first")
            XCTAssertEqual(items["sort"], "shelf_added")
            XCTAssertEqual(items["dir"], "desc")
        }
    }

    func testASearchInsideAShelfIsStillScoped() async throws {
        try stub(page: try page(ids: ["a"], total: 1))
        let model = makeModel()
        await model.openShelf(try shelf())

        let before = libraryRequests().count
        await model.search("dune")

        let scoped = Array(libraryRequests().dropFirst(before))
        XCTAssertFalse(scoped.isEmpty)
        for request in scoped {
            XCTAssertEqual(query(request)["shelf"], shelfId)
            XCTAssertEqual(query(request)["q"], "dune", "the term and the scope are one request")
        }
    }

    func testLeavingRestoresTheSortAndShelfAddedIsNeverPersisted() async throws {
        try stub(page: try page(ids: ["a"], total: 1))
        var persisted: [LibrarySort] = []
        let model = makeModel(sort: LibrarySort(field: .author, direction: .asc)) { persisted.append($0) }

        await model.openShelf(try shelf())
        XCTAssertEqual(model.query.sort, LibrarySort(field: .shelfAdded, direction: .desc))
        XCTAssertTrue(persisted.isEmpty, "opening a shelf changes the order without remembering it")

        await model.chooseSort(LibrarySort(field: .title, direction: .desc))
        XCTAssertTrue(persisted.isEmpty, "a sort chosen inside a shelf is the scope's own order")

        await model.closeShelf()
        XCTAssertEqual(
            model.query.sort,
            LibrarySort(field: .author, direction: .asc),
            "leaving restores the order that was on"
        )

        await model.chooseSort(LibrarySort(field: .title, direction: .asc))
        XCTAssertEqual(
            persisted,
            [LibrarySort(field: .title, direction: .asc)],
            "an All Books sort is still remembered"
        )
    }

    func testShelvesAreUnsupportedWhenTheRouteDoesNotExist() async throws {
        try stub(shelvesStatus: 404, page: try page(ids: ["a"], total: 1))
        let model = makeModel()
        await model.loadShelves()
        XCTAssertEqual(model.shelvesSupported, false, "a pre-shelves Mac answers 404 and the UI stays away")
        XCTAssertTrue(model.shelves.isEmpty)
    }

    func testAnUnansweredProbeIsUnknownRatherThanAbsent() async throws {
        try stub(shelvesStatus: 500, page: try page(ids: ["a"], total: 1))
        let model = makeModel()
        await model.loadShelves()
        XCTAssertNil(model.shelvesSupported, "a Mac that did not answer is not a Mac without shelves")
    }

    /// **The owner's *the shelves have disappeared*, 2026-09-30.** The probe ran
    /// once, at launch; a launch that met the Mac mid-restart left the answer
    /// unknown and the scope control hidden for the whole session. The next load
    /// that lands asks again.
    func testAnUnansweredProbeIsAskedAgainByTheNextLoadThatLands() async throws {
        try stub(shelvesStatus: 500, page: try page(ids: ["a"], total: 1))
        let model = makeModel()
        await model.start()
        XCTAssertNil(model.shelvesSupported, "the Mac answered the library but not the probe")

        try stub(page: try page(ids: ["a"], total: 1))
        await model.start()
        XCTAssertEqual(model.shelvesSupported, true, "a load that lands re-asks an unknown")
        XCTAssertEqual(model.shelves.map(\.id), [shelfId])
    }

    /// The other half of the rule: an answer in hand — yes or no — is not re-asked
    /// by every sort and settled keystroke.
    func testAKnownAnswerIsNotAskedAgainByEveryLoad() async throws {
        for status in [200, 404] {
            try stub(shelvesStatus: status, page: try page(ids: ["a"], total: 1))
            let model = makeModel()
            await model.start()
            XCTAssertNotNil(model.shelvesSupported, "the first load that lands asks (\(status))")
            let asked = StubURLProtocol.requests.filter { $0.url?.path.hasSuffix("/api/shelves") == true }.count
            XCTAssertEqual(asked, 1)

            await model.search("dune")
            let after = StubURLProtocol.requests.filter { $0.url?.path.hasSuffix("/api/shelves") == true }.count
            XCTAssertEqual(after, asked, "a known answer (\(status)) is remembered, not re-asked")
        }
    }

    func testAGoneShelfLeavesTheScopeAndSaysSo() async throws {
        try stub(libraryStatus: 404, page: try page(ids: [], total: 0))
        let model = makeModel()
        await model.openShelf(try shelf())

        XCTAssertNil(model.query.shelf, "the scope the Mac cannot answer for is left")
        XCTAssertEqual(model.scopeNotice, "“To Read” is gone from the Mac.")
    }

    // MARK: 7a — the rules a view reads

    func testTheFieldNamesTheScope() throws {
        var q = LibraryQuery()
        XCTAssertEqual(q.searchPlaceholder, "Search titles, authors, series…")
        q.shelf = try shelf()
        XCTAssertEqual(q.searchPlaceholder, "Search “To Read”")
    }

    func testShelfAddedIsOfferedOnlyInsideAShelfAndNeverStored() throws {
        XCTAssertFalse(
            LibrarySort.options(inShelf: false).contains { $0.field == .shelfAdded },
            "the order is meaningless outside a shelf, and the server refuses it there"
        )
        let inShelf = LibrarySort.options(inShelf: true)
        XCTAssertEqual(inShelf.filter { $0.field == .shelfAdded }.count, 2)
        XCTAssertEqual(inShelf.first, LibrarySort.allBooksOptions.first, "the All Books orders stay on top")
        XCTAssertEqual(
            LibrarySort(field: .shelfAdded, direction: .desc).label,
            "Date Added to Shelf, Newest First",
            "the Mac's own words"
        )
        XCTAssertEqual(
            LibrarySort.stored("shelf_added:desc"),
            .default,
            "an inside-only order is not a stored preference"
        )
    }

    func testAnEmptyShelfHasItsOwnSentence() throws {
        var q = LibraryQuery()
        XCTAssertEqual(LibraryEmptyState.of(q, isEmpty: true), .libraryIsEmpty)
        q.shelf = try shelf()
        XCTAssertEqual(LibraryEmptyState.of(q, isEmpty: true), .shelfIsEmpty("To Read"))
        q.text = "dune"
        XCTAssertEqual(
            LibraryEmptyState.of(q, isEmpty: true),
            .noMatches("dune"),
            "the term is the narrower question, shelf or not"
        )
        XCTAssertNil(LibraryEmptyState.of(q, isEmpty: false))
    }

    // MARK: 7a/b — the membership writes (the client's half)

    func testAToggleIsOnePutOrOneDeleteWithNoBody() async throws {
        try stub(page: try page(ids: ["a"], total: 1))
        let client = makeClient()

        let added = try await client.addToShelf(shelfId: shelfId, bookId: bookId)
        let removed = try await client.removeFromShelf(shelfId: shelfId, bookId: bookId)

        XCTAssertEqual(added.shelves, [shelfId], "the reply is the book read back after the write")
        XCTAssertEqual(removed.id, bookId)

        let membership = StubURLProtocol.requests.filter { $0.url?.path.contains("/api/shelves/") == true }
        XCTAssertEqual(membership.count, 2)
        XCTAssertEqual(membership[0].httpMethod, "PUT")
        XCTAssertEqual(membership[1].httpMethod, "DELETE")
        for request in membership {
            XCTAssertEqual(request.url?.path, "/api/shelves/\(shelfId)/books/\(bookId)")
            XCTAssertNil(request.httpBody, "the contract's writes send no body")
        }
    }

    // MARK: 7b — the checklist's own model

    /// The book golden with its membership set to `shelves` — the seed a detail
    /// opens with, and the one field a case needs to differ in.
    private nonisolated func bookFixture(shelves: [String]) throws -> Data {
        var object = try JSONSerialization.jsonObject(with: fixture("book")) as! [String: Any]
        object["shelves"] = shelves
        return try JSONSerialization.data(withJSONObject: object)
    }

    /// The membership golden with the answered book's membership set — so a case
    /// can make the server's answer differ from anything a local flip would
    /// produce.
    private nonisolated func membershipFixture(bookShelves: [String]) throws -> Data {
        var object = try JSONSerialization.jsonObject(with: fixture("membership")) as! [String: Any]
        var book = object["book"] as! [String: Any]
        book["shelves"] = bookShelves
        object["book"] = book
        return try JSONSerialization.data(withJSONObject: object)
    }

    private func detailModel() -> BookDetailModel {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("shelves-tests-\(UUID().uuidString)")
        return BookDetailModel(client: makeClient(), downloads: DownloadStore(root: root))
    }

    /// **AC10: the checklist shows the book the Mac answered with.** This
    /// fixture's book carries a shelf the request never mentioned, which a local
    /// flip could not produce — the difference between refreshing from the
    /// server's answer and guessing.
    func testAToggleRefreshesFromTheReturnedBook() async throws {
        let other = "ffffffff-0000-4000-8000-000000000001"
        try stub(
            page: try page(ids: ["a"], total: 1),
            membershipBody: try membershipFixture(bookShelves: [shelfId, other])
        )
        let seed = try JSONDecoder().decode(ContractBook.self, from: try bookFixture(shelves: []))
        let model = detailModel()
        await model.load(seed: seed)
        await model.loadShelves()
        XCTAssertEqual(model.shelvesSupported, true)

        await model.toggle(try shelf())

        let membership = StubURLProtocol.requests.filter { $0.url?.path.contains("/api/shelves/") == true }
        XCTAssertEqual(membership.first?.httpMethod, "PUT", "a book that is not on the shelf is added")
        XCTAssertEqual(model.book?.shelves, [shelfId, other], "the row is the server's own answer, not a flip")
        XCTAssertNil(model.shelfFailure)
    }

    func testAToggleOfAMemberIsADelete() async throws {
        try stub(page: try page(ids: ["a"], total: 1))
        let seed = try JSONDecoder().decode(ContractBook.self, from: try bookFixture(shelves: [shelfId]))
        let model = detailModel()
        await model.load(seed: seed)
        await model.loadShelves()

        await model.toggle(try shelf())

        let membership = StubURLProtocol.requests.filter { $0.url?.path.contains("/api/shelves/") == true }
        XCTAssertEqual(membership.first?.httpMethod, "DELETE")
    }

    /// **AC11: a failure is a sentence, and the checklist is left as it was.**
    /// The Mac's writes are idempotent (D10), so the retry is a second tap and
    /// nothing has to be unwound.
    func testAFailedToggleSurfacesTheSentenceAndLeavesTheChecklist() async throws {
        try stub(
            page: try page(ids: ["a"], total: 1),
            membershipStatus: 503,
            membershipBody: Data(#"{"error":"library offline"}"#.utf8)
        )
        let seed = try JSONDecoder().decode(ContractBook.self, from: try bookFixture(shelves: [shelfId]))
        let model = detailModel()
        await model.load(seed: seed)
        await model.loadShelves()

        await model.toggle(try shelf())

        XCTAssertEqual(model.shelfFailure, "the library share is not mounted on the Mac")
        XCTAssertEqual(model.book?.shelves, [shelfId], "nothing was flipped locally")
        XCTAssertNil(model.toggling, "the row is not left in flight")
    }
}
