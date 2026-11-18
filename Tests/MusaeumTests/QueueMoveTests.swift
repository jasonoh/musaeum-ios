import XCTest

@testable import Musaeum

/// **A reading queue on the phone** (slice 9) — the client half of the Mac design's
/// D7, and AC16's two halves: a move takes effect and the list shows it, and against
/// a Mac that answers `404` the Move menu is **absent** rather than refused.
///
/// What each case decides:
///
/// - the request the move composes (method, path, and a body of exactly one member);
/// - a queue opening with **no** `sort` while a manual shelf still sends
///   `shelf_added desc` explicitly (AC15's follow-on);
/// - a move followed by the *same scoped query* re-read, with the Mac's order on
///   screen (the existing shelf re-query rule — the scope is kept);
/// - a `404` withdrawing the menu and saying so once, and every other refusal
///   quoting the Mac's own sentence while leaving the menu in place;
/// - a sort chosen inside a queue never becoming the library's sort;
/// - the pure rules the card's context menu exists or does not exist by.
///
/// `nonisolated` on every helper that builds a stub, for `ShelvesTests`' recorded
/// reason: this class is `@MainActor`, a closure written inside one of its methods
/// **inherits** that isolation, and `StubURLProtocol` calls its handler from a
/// background thread — where the inherited isolation asserts the queue
/// (`dispatch_assert_queue_fail`, SIGTRAP) and takes the whole test host down.
@MainActor
final class QueueMoveTests: XCTestCase {
    private let base = URL(string: "http://127.0.0.1:8788")!
    private let bookId = "6f1a1f2e-3c4d-4e5f-8a9b-0c1d2e3f4a5b"

    // MARK: Fixtures

    private nonisolated func fixture(_ name: String) throws -> Data {
        let bundle = Bundle(for: QueueMoveTests.self)
        guard let url = bundle.url(forResource: name, withExtension: "json") else {
            throw XCTSkip("no \(name).json in the test bundle — run scripts/vendor-contract-fixtures.sh")
        }
        return try Data(contentsOf: url)
    }

    private nonisolated func shelves() throws -> [Shelf] {
        try JSONDecoder().decode(Shelves.self, from: fixture("shelves")).shelves
    }

    /// The golden's two kinds, taken from the golden rather than typed here: the
    /// fixture is the contract's own payload, and a hand-typed shelf would be a
    /// second copy of the wire.
    private nonisolated func queue() throws -> Shelf {
        try XCTUnwrap(shelves().first { $0.kind == "queue" }, "the vendored shelves golden carries a queue")
    }

    private nonisolated func manualShelf() throws -> Shelf {
        try XCTUnwrap(shelves().first { $0.kind == "manual" })
    }

    /// A page shaped like the contract's own `library` payload, built from the golden
    /// so every always-present field stays present.
    private nonisolated func page(ids: [String]) throws -> Data {
        var object = try JSONSerialization.jsonObject(with: fixture("library")) as! [String: Any]
        let golden = (object["books"] as! [[String: Any]])[0]
        object["books"] = ids.enumerated().map { index, id in
            var book = golden
            book["id"] = id
            book["title"] = "Book \(index + 1)"
            return book
        }
        object["total"] = ids.count
        object["offset"] = 0
        object["nextOffset"] = ids.count
        object["isLastPage"] = true
        return try JSONSerialization.data(withJSONObject: object)
    }

    // MARK: Stubs

    /// Answers health, the shelf list, the library pages, and the place route.
    ///
    /// **Which page a read is answered with is derived from how many moves have
    /// landed**, not from a captured variable: `startLoading` records each request
    /// under the stub's own lock before it calls this handler, so
    /// `StubURLProtocol.requests` is the one piece of state here that is safe to
    /// read off the main thread — and a test that moved a `var` from the outside
    /// would be a race the compiler allows and the run pays for. The first page is
    /// the Mac's order before any move; every read after one answers the second.
    private nonisolated func stub(
        pages: [Data],
        moveStatus: Int = 200,
        moveBody: Data? = nil,
        libraryGoneAfterMove: Bool = false
    ) throws {
        let health = try fixture("health")
        let shelfList = try fixture("shelves")
        // **The deleted queue is gone from the list too** — one coherent world, so a
        // run can tell "the shelf was deleted" from "the route is absent": a list that
        // no longer names a queue is exactly what the client's reset rule reads, and
        // it is what a Mac would answer once the shelf is really gone.
        let shelfListWithoutQueue: Data = {
            guard var object = try? JSONSerialization.jsonObject(with: shelfList) as? [String: Any],
                  var rows = object["shelves"] as? [[String: Any]] else { return shelfList }
            rows.removeAll { ($0["kind"] as? String) == "queue" }
            object["shelves"] = rows
            return (try? JSONSerialization.data(withJSONObject: object)) ?? shelfList
        }()
        let reply = try moveBody ?? fixture("membership")
        StubURLProtocol.configure { request in
            guard let url = request.url else { return StubURLProtocol.Response(status: 500) }
            if url.path.hasSuffix("/api/health") { return StubURLProtocol.Response(body: health) }
            if url.path.hasSuffix("/api/shelves") {
                let moved = StubURLProtocol.requests.contains { $0.url?.path.hasSuffix("/position") == true }
                return StubURLProtocol.Response(body: libraryGoneAfterMove && moved ? shelfListWithoutQueue : shelfList)
            }
            if url.path.hasSuffix("/position") { return StubURLProtocol.Response(status: moveStatus, body: reply) }
            if url.path.hasSuffix("/api/library") {
                let moves = StubURLProtocol.requests.filter { $0.url?.path.hasSuffix("/position") == true }.count
                // **A deleted queue refuses every read scoped to it, and only those** —
                // which is what a Mac answers once a shelf is gone, and what makes the
                // client's own scoped-404 rule reachable. The unscoped refetch (the way
                // out of the scope) succeeds, so the run can tell the two apart.
                let scoped = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                    .queryItems?.contains { $0.name == "shelf" } ?? false
                if libraryGoneAfterMove, scoped, moves >= 1 {
                    return StubURLProtocol.Response(status: 404, body: Data(#"{"error":"not found"}"#.utf8))
                }
                return StubURLProtocol.Response(body: pages[min(moves, pages.count - 1)])
            }
            return StubURLProtocol.Response(status: 404)
        }
    }

    // MARK: Readers

    private nonisolated func query(_ request: URLRequest) -> [String: String] {
        let items = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
        return items.reduce(into: [:]) { $0[$1.name] = $1.value }
    }

    private nonisolated func libraryRequests() -> [URLRequest] {
        StubURLProtocol.requests.filter { $0.url?.path.hasSuffix("/api/library") == true }
    }

    private nonisolated func positionRequests() -> [URLRequest] {
        StubURLProtocol.requests.filter { $0.url?.path.hasSuffix("/position") == true }
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

    // MARK: The request the move composes

    func testTheMoveIsOnePutToThePositionPathWithABodyOfExactlyOneMember() throws {
        let top = try MusaeumClient.moveRequest(
            base: base, token: "t", shelfId: "q-1", bookId: "b2", to: .top
        )
        XCTAssertEqual(top.httpMethod, "PUT", "a place is set, so it is a PUT")
        XCTAssertEqual(top.url?.path, "/api/shelves/q-1/books/b2/position")
        XCTAssertEqual(top.url?.query, nil, "the route takes its two ids in the path and nothing in the query")
        XCTAssertEqual(top.value(forHTTPHeaderField: "Content-Type"), "application/json")

        let body = try XCTUnwrap(top.httpBody)
        let decoded = try JSONSerialization.jsonObject(with: body) as! [String: String]
        XCTAssertEqual(Set(decoded.keys), ["to"], "exactly one member — the contract refuses a second")
        XCTAssertEqual(decoded["to"], "top")

        let bottom = try MusaeumClient.moveRequest(
            base: base, token: "t", shelfId: "q-1", bookId: "b2", to: .bottom
        )
        let bottomBody = try JSONSerialization.jsonObject(with: XCTUnwrap(bottom.httpBody)) as! [String: String]
        XCTAssertEqual(bottomBody, ["to": "bottom"], "the other end, and no third place on the wire")
    }

    // MARK: AC15's follow-on — the sort a queue opens in

    func testAQueueOpensSendingNoSortAndAManualShelfStillSendsTheMacsDefault() async throws {
        try stub(pages: [try page(ids: ["b3", "b1", "b2"])])
        let model = makeModel()
        await model.start()
        await model.loadShelves()

        await model.openShelf(try queue())
        XCTAssertNil(model.query.sort, "a queue's order is the Mac's own — the phone asks for it by asking for nothing")

        let scoped = try XCTUnwrap(libraryRequests().last)
        XCTAssertEqual(query(scoped)["shelf"], try queue().id)
        XCTAssertNil(query(scoped)["sort"], "no sort is sent inside a queue")
        XCTAssertNil(query(scoped)["dir"], "and no direction — a sort is a pair")
        XCTAssertEqual(model.books.map(\.id), ["b3", "b1", "b2"], "the list is the Mac's answer, in its own order")

        await model.openShelf(try manualShelf())
        XCTAssertEqual(model.query.sort, LibrarySort(field: .shelfAdded, direction: .desc))
        let manual = try XCTUnwrap(libraryRequests().last)
        XCTAssertEqual(query(manual)["sort"], "shelf_added", "slice 7a's explicit default is untouched")
        XCTAssertEqual(query(manual)["dir"], "desc")
    }

    // MARK: AC16's first half — a move takes effect, and the list shows it

    func testAMoveReQueriesTheSameScopeAndShowsTheMacsNewOrder() async throws {
        try stub(pages: [
            try page(ids: ["b3", "b1", "b2"]),
            try page(ids: ["b2", "b3", "b1"]),
        ])
        let model = makeModel()
        await model.start()
        await model.loadShelves()
        await model.openShelf(try queue())
        XCTAssertEqual(model.books.map(\.id), ["b3", "b1", "b2"])

        let book = try XCTUnwrap(model.books.first { $0.id == "b2" })
        XCTAssertTrue(model.offersMove(for: book), "inside a queue, with nothing learned against it")

        await model.move(book, to: .top)

        XCTAssertEqual(positionRequests().count, 1, "one PUT, and the re-query is not a second move")
        XCTAssertEqual(model.moveRoute, .available, "a 200 is proof the route exists")
        XCTAssertEqual(model.books.map(\.id), ["b2", "b3", "b1"], "the grid shows the Mac's order, not a local re-sort")
        XCTAssertEqual(model.total, 3, "the count did not move — a move is not a membership change")

        let requery = try XCTUnwrap(libraryRequests().last)
        XCTAssertEqual(query(requery)["shelf"], try queue().id, "the scope is kept")
        XCTAssertNil(query(requery)["sort"], "and it is still the scope's own order")
        XCTAssertEqual(model.query.shelf?.id, try queue().id, "the model's scope is the one it asked for")
        XCTAssertNil(model.scopeNotice, "a move that worked says nothing")
    }

    // MARK: AC16's second half — a Mac that answers 404

    func testA404OnTheMoveWithdrawsTheMenuAndSaysSoOnce() async throws {
        try stub(pages: [try page(ids: ["b3", "b1", "b2"])], moveStatus: 404)
        let model = makeModel()
        await model.start()
        await model.loadShelves()
        await model.openShelf(try queue())
        let book = try XCTUnwrap(model.books.first)

        XCTAssertTrue(model.offersMove(for: book), "the golden lists a queue, which is the wire's own evidence for the route")
        let reads = libraryRequests().count

        await model.move(book, to: .top)

        XCTAssertEqual(model.moveRoute, .unavailable, "the contract's reading of this 404 on this path")
        XCTAssertFalse(model.offersMove(for: book), "the menu is absent, not disabled")
        XCTAssertEqual(model.scopeNotice, "This Mac can't move books in a queue.", "one plain sentence, and no alarm")
        XCTAssertEqual(model.books.map(\.id), ["b3", "b1", "b2"], "no order moved — the move was refused")
        XCTAssertEqual(libraryRequests().count, reads + 1, "but the scope is re-read: a 404 here is not proof the shelf exists")

        // A withdrawn menu is not sticky forever: a fresh shelf list is the wire's
        // own evidence that this Mac has queues — and the route landed with them.
        await model.loadShelves()
        XCTAssertEqual(model.moveRoute, .unknown)
        XCTAssertTrue(model.offersMove(for: book), "a pull re-probes, and the menu can come back")
    }

    /// **The 404 a *deleted queue* answers with** — the contract's uniform refusal on
    /// this route covers an unknown shelf as well as a missing route, so the move's
    /// 404 must not strand the reader on a queue that no longer exists. The re-query
    /// it triggers reaches the existing scoped-404 rule, which leaves the scope and
    /// says so in place of the route sentence.
    func testAMoveThatFindsTheQueueDeletedLeavesTheScopeAndSaysSo() async throws {
        try stub(
            pages: [try page(ids: ["b3", "b1", "b2"]), try page(ids: ["b3", "b1", "b2"])],
            moveStatus: 404,
            libraryGoneAfterMove: true
        )
        let model = makeModel()
        await model.start()
        await model.loadShelves()
        await model.openShelf(try queue())
        XCTAssertEqual(model.query.shelf?.id, try queue().id)
        let book = try XCTUnwrap(model.books.first)

        await model.move(book, to: .top)

        XCTAssertNil(model.query.shelf, "the queue the Mac no longer has is left")
        XCTAssertEqual(model.scopeNotice, "“Up Next” is gone from the Mac.", "and the truer sentence replaces the route one")
        XCTAssertEqual(model.moveRoute, .unavailable, "the move itself did answer 404")
        XCTAssertEqual(model.shelves.map(\.kind), ["manual"], "the fresh list no longer names a queue, so nothing resets the route")
    }

    // MARK: Every other refusal

    func testARefusedMoveQuotesTheMacAndLeavesTheMenuInPlace() async throws {
        try stub(
            pages: [try page(ids: ["b3", "b1", "b2"])],
            moveStatus: 503,
            moveBody: Data(#"{"error":"library offline"}"#.utf8)
        )
        let model = makeModel()
        await model.start()
        await model.loadShelves()
        await model.openShelf(try queue())
        let book = try XCTUnwrap(model.books.first)

        await model.move(book, to: .bottom)

        XCTAssertEqual(model.scopeNotice, "Couldn't move that book — the library share is not mounted on the Mac")
        XCTAssertTrue(model.offersMove(for: book), "a 503 is not a Mac without the route — the menu stays")
        XCTAssertEqual(model.moveRoute, .unknown, "and the route is still unproven either way")
        XCTAssertEqual(model.books.map(\.id), ["b3", "b1", "b2"], "the list was not re-queried on a refusal")

        await model.move(book, to: .bottom)
        XCTAssertEqual(positionRequests().count, 2, "the retry is a second call, not a withdrawn menu")

        // **A move that works clears what the last one said** (review finding, this
        // build): the notice row is the scope's own line, and a failure sentence left
        // standing after a successful retry is the screen disagreeing with itself.
        try stub(pages: [try page(ids: ["b2", "b3", "b1"])])
        await model.move(book, to: .top)
        XCTAssertNil(model.scopeNotice, "the Mac came back, the move landed, and the sentence went with it")
        XCTAssertEqual(model.books.map(\.id), ["b2", "b3", "b1"], "and the list followed the move")
    }

    // MARK: A sort chosen inside a queue is never the library's

    func testASortChosenInsideAQueueIsNeverPersisted() async throws {
        try stub(pages: [try page(ids: ["b3", "b1", "b2"])])
        var persisted: [LibrarySort] = []
        let model = makeModel(sort: LibrarySort(field: .author, direction: .asc)) { persisted.append($0) }

        await model.start()
        await model.loadShelves()
        await model.openShelf(try queue())
        XCTAssertTrue(persisted.isEmpty, "opening a queue changes the order without remembering it")

        await model.chooseSort(LibrarySort(field: .title, direction: .desc))
        XCTAssertEqual(model.query.sort, LibrarySort(field: .title, direction: .desc))
        XCTAssertEqual(query(try XCTUnwrap(libraryRequests().last))["sort"], "title")
        XCTAssertTrue(persisted.isEmpty, "a sort chosen inside a queue is the scope's own order")

        await model.chooseSort(nil)
        XCTAssertNil(model.query.sort, "Queue Order asks for the Mac's own order again")
        XCTAssertNil(query(try XCTUnwrap(libraryRequests().last))["sort"], "and sends nothing")
        XCTAssertTrue(persisted.isEmpty)

        await model.closeShelf()
        XCTAssertEqual(
            model.query.sort,
            LibrarySort(field: .author, direction: .asc),
            "leaving restores the reader's All Books order"
        )

        // Outside a queue there is no such thing as "no order": the guard refuses it
        // rather than composing a request that asks the Mac for nothing.
        await model.chooseSort(nil)
        XCTAssertEqual(model.query.sort, LibrarySort(field: .author, direction: .asc))
    }

    // MARK: The rules the card's menu reads

    func testTheShelfScopeRules() throws {
        let queue = try queue()
        let manual = try manualShelf()

        XCTAssertTrue(ShelfScope.isQueue(queue))
        XCTAssertFalse(ShelfScope.isQueue(manual))
        XCTAssertFalse(ShelfScope.isQueue(nil), "no scope open is not a queue")

        XCTAssertNil(ShelfScope.openingSort(for: queue), "a queue opens on the Mac's own order — send nothing")
        XCTAssertEqual(
            ShelfScope.openingSort(for: manual),
            LibrarySort(field: .shelfAdded, direction: .desc),
            "a manual shelf keeps the default slice 7a mirrored"
        )

        for route in [QueueMoveRoute.unknown, .available] {
            XCTAssertTrue(ShelfScope.offersMove(in: queue, route: route))
        }
        XCTAssertFalse(ShelfScope.offersMove(in: queue, route: .unavailable), "absent, not disabled")
        for route in [QueueMoveRoute.unknown, .available, .unavailable] {
            XCTAssertFalse(ShelfScope.offersMove(in: manual, route: route), "a manual shelf has no order to set")
            XCTAssertFalse(ShelfScope.offersMove(in: nil, route: route))
        }
    }

    // MARK: The route is not the book

    func testAMoveOutsideAQueueIsNeverAttempted() async throws {
        try stub(pages: [try page(ids: ["b3", "b1", "b2"])])
        let model = makeModel()
        await model.start()
        await model.loadShelves()
        await model.openShelf(try manualShelf())
        let book = try XCTUnwrap(model.books.first)

        await model.move(book, to: .top)

        XCTAssertTrue(positionRequests().isEmpty, "the contract refuses a move on a manual shelf with a 400; nothing to learn from hearing it")
        XCTAssertNil(model.scopeNotice)
    }
}
