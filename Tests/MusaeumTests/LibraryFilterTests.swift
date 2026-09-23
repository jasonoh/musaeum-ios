import XCTest

@testable import Musaeum

/// The filters: the pure rules that decide what a selection *becomes* on the wire,
/// and the model half that decides what a **request** carries.
///
/// Both halves are here because they fail for different reasons — the pure rules
/// are about the contract's own vocabulary and the omit-when-empty rule, and the
/// model's are about a narrowing riding on every page rather than on the first.
/// `LibraryQueryTests` carries the same split for the sort and the term.
///
/// `nonisolated` on every helper that builds a stub is not taste: this class is
/// `@MainActor`, so a closure written inside one of its methods **inherits** that
/// isolation, and `StubURLProtocol` calls its handler from a background thread,
/// where the inherited isolation asserts the queue (`dispatch_assert_queue_fail`,
/// SIGTRAP) and takes the whole test host down. The owner reads that as *"the app
/// quit"*, not as a failed case (slice 1's trap 2; the note is on
/// `LibraryQueryTests` and `LibraryPagingTests` too).
@MainActor
final class LibraryFilterTests: XCTestCase {
    private let base = URL(string: "http://127.0.0.1:8788")!

    // MARK: Fixtures and stubs

    private nonisolated func fixture(_ name: String) throws -> Data {
        let bundle = Bundle(for: LibraryFilterTests.self)
        guard let url = bundle.url(forResource: name, withExtension: "json") else {
            throw XCTSkip("no \(name).json in the test bundle — run scripts/vendor-contract-fixtures.sh")
        }
        return try Data(contentsOf: url)
    }

    /// The contract's own facets payload, decoded through the app's strict decoder —
    /// so a count asserted here is the document's count and not a hand-typed one.
    private nonisolated func facetsFixture() throws -> Facets {
        try JSONDecoder().decode(Facets.self, from: fixture("facets"))
    }

    /// A page shaped like the contract's own `library` payload, built **from the
    /// golden** so every always-present field stays present.
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

    /// Answers the two library pages a walk needs, by **offset** — which is what
    /// makes "the filter rides on page 2 as well" observable rather than assumed.
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

    /// Answers a **filtered** library and the unfiltered one apart, so a case can
    /// watch the count come back when the filters go.
    private nonisolated func stubFiltered(filtered: Data, unfiltered: Data) throws {
        let health = try fixture("health")
        StubURLProtocol.configure { request in
            guard let url = request.url, !url.path.hasSuffix("/api/health") else {
                return StubURLProtocol.Response(status: 200, body: health)
            }
            let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            let isFiltered = items.contains { ["formats", "readStatus", "authors", "series", "tags", "minRating"].contains($0.name) }
            return StubURLProtocol.Response(status: 200, body: isFiltered ? filtered : unfiltered)
        }
    }

    private nonisolated func query(_ request: URLRequest) -> [String: String] {
        let items = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
        return items.reduce(into: [:]) { $0[$1.name] = $1.value }
    }

    private nonisolated func libraryRequests() -> [URLRequest] {
        StubURLProtocol.requests.filter { $0.url?.path.hasSuffix("/api/library") == true }
    }

    private func makeModel() -> LibraryModel {
        LibraryModel(client: MusaeumClient(base: base, token: "t", session: StubURLProtocol.session()))
    }

    // MARK: 3.11 — an empty selection omits its parameter

    /// **The rule the whole file turns on.** An axis with nothing in it is not a
    /// parameter: `formats=` is a pair with no value, and the one thing it can mean
    /// is whatever the server decides an empty list means.
    func testAClearedSelectionComposesNoParametersAtAll() {
        XCTAssertTrue(LibraryFilters.none.queryItems.isEmpty)
        XCTAssertFalse(LibraryFilters.none.isActive)
        XCTAssertEqual(LibraryFilters.none.selectedCount, 0)

        var filters = LibraryFilters.none
        filters.toggle(ReadingStatus.reading)
        filters.toggle(LibraryFilters.Format.epub)
        filters.minRating = 4
        filters.toggle("Steven Kotler", in: .authors)

        XCTAssertEqual(
            Set(filters.queryItems.map(\.name)),
            ["readStatus", "formats", "minRating", "authors"]
        )
        XCTAssertTrue(filters.queryItems.allSatisfy { !($0.value ?? "").isEmpty }, "no value travels empty")

        filters.clear()
        XCTAssertTrue(filters.queryItems.isEmpty, "clearing every axis leaves nothing to send")
        XCTAssertEqual(filters, LibraryFilters.none, "and clearing is exactly the empty set")
    }

    /// **One query item per value, never a comma-joined list.** The contract reads
    /// the two forms as the same thing, which is precisely why this client should
    /// not be the one holding the separator: the server splits every value it is
    /// handed, so the joined form bakes a rule it does not own into its own URL.
    func testEachSelectedValueIsItsOwnQueryItem() {
        var filters = LibraryFilters.none
        filters.toggle("Steven Kotler", in: .authors)
        filters.toggle("Margaret Weis", in: .authors)
        filters.toggle(LibraryFilters.Format.epub)
        filters.toggle(LibraryFilters.Format.pdf)

        let authors = filters.queryItems.filter { $0.name == "authors" }
        XCTAssertEqual(authors.map(\.value), ["Margaret Weis", "Steven Kotler"], "one item per value, sorted so the same set always composes the same URL")
        XCTAssertEqual(filters.queryItems.filter { $0.name == "formats" }.map(\.value), ["epub", "pdf"])
        XCTAssertEqual(filters.queryItems.filter { $0.name == "readStatus" }.count, 0)
    }

    /// **A value carrying the separator is a limit of the wire, recorded rather
    /// than hidden.** The server splits every value on `,` before it matches, so
    /// `William Strixrud, PhD` — a real author on the probe profile — is a filter
    /// that matches nothing in either spelling. What this client can keep is its own
    /// half of the rule: it never *joins* values with a comma, so the only comma a
    /// request can carry is one that was in the value.
    func testAValueCarryingACommaIsSentVerbatimBecauseTheSplitIsTheServers() {
        var filters = LibraryFilters.none
        filters.toggle("William Strixrud, PhD", in: .authors)

        XCTAssertEqual(filters.queryItems.count, 1)
        XCTAssertEqual(filters.queryItems[0].name, "authors")
        XCTAssertEqual(filters.queryItems[0].value, "William Strixrud, PhD")
    }

    /// **3.2's rule, one axis over.** The contract refuses an unknown `formats` or
    /// `readStatus` value with a 400 rather than defaulting it, so a value invented
    /// here would reach a reader as a broken library. These three lists are the
    /// contract's own, read off `../musaeum/src/types/book.types.ts:17-22` and
    /// `electron/main/services/api/shape.ts:77-81`.
    func testTheFilterVocabularyIsTheContractsOwn() {
        XCTAssertEqual(LibraryFilters.Format.allCases.map(\.rawValue), ["epub", "mobi", "azw3", "pdf"])
        XCTAssertEqual(LibraryFilters.statusOrder.map(\.rawValue), ["unread", "reading", "read"])
        XCTAssertEqual(LibraryFilters.ratingRange, 1...5, "a book's rating is 1…5, so 0 would be every book and 6 would be none")
    }

    // MARK: 3.10 — the vocabulary the sheet binds to

    /// The two vocabulary rows are drawn from the contract and need **no request at
    /// all**, which is what lets a reader see and clear a filter with the Mac
    /// asleep. A count of `nil` is "the facets are not in hand" and is not a zero.
    func testTheVocabularyRowsSurviveNoFacetsAtAll() throws {
        let bare = LibraryFilters.statusOptions(nil)
        XCTAssertEqual(bare.map(\.label), ["Unread", "Reading", "Read"], "the Mac's own labels, in the contract's own order")
        XCTAssertTrue(bare.allSatisfy { $0.count == nil })
        XCTAssertTrue(LibraryFilters.formatOptions(nil).allSatisfy { $0.count == nil })
        XCTAssertEqual(LibraryFilters.formatOptions(nil).map(\.label), ["EPUB", "MOBI", "AZW3", "PDF"])

        let facets = try facetsFixture()
        XCTAssertEqual(LibraryFilters.statusOptions(facets).map(\.count), [0, 1, 0], "the Mac's own counts, on the contract's own three")
        XCTAssertEqual(LibraryFilters.formatOptions(facets).map(\.count), [5324, 0, 0, 0], "a format the library holds none of is shown with a zero rather than hidden, so the row never re-orders itself")
    }

    /// The three long lists are the facet arrays themselves, in the order the server
    /// sent them — no client-side rank and no top-N cut.
    func testTheFacetAxesAreTheContractsOwnListsInItsOwnOrder() throws {
        let facets = try facetsFixture()
        XCTAssertEqual(LibraryFilters.Axis.authors.values(in: facets).map(\.value), ["James S. A. Corey"])
        XCTAssertEqual(LibraryFilters.Axis.series.values(in: facets).map(\.value), ["The Expanse"])
        XCTAssertEqual(LibraryFilters.Axis.tags.values(in: facets).map(\.value), ["space opera"])
        for axis in LibraryFilters.Axis.allCases {
            XCTAssertFalse(axis.title.isEmpty)
            XCTAssertFalse(axis.prompt.isEmpty, "a list with no narrow field is a list nobody reaches the bottom of")
        }
    }

    /// The sheet's own fetch, decided where it can be: **which request it makes,
    /// and when**. No unit case can see the sheet — that is the frame's job — but
    /// the annex's reading ("fetched when the sheet is opened, not with each
    /// library page") is a claim about requests, and this is the instrument for it.
    func testTheFacetsAreFetchedWhenTheSheetAsksAndNeverWithALibraryPage() async throws {
        try stubFacetsAndLibrary()
        let model = makeModel()

        await model.start()
        XCTAssertEqual(libraryRequests().count, 1)
        XCTAssertEqual(facetRequests().count, 0, "starting the screen does not fetch counts nobody has asked to see")
        XCTAssertNil(model.facets)

        await model.loadFacets()
        XCTAssertEqual(model.facetsPhase, .loaded)
        XCTAssertEqual(model.facets?.authors.first?.value, "James S. A. Corey")
        XCTAssertEqual(facetRequests().count, 1, "one request per open")

        await model.toggle(ReadingStatus.reading)
        XCTAssertEqual(facetRequests().count, 1, "and a filter change is not a reason to fetch them again")
    }

    /// A failed facet fetch is not a failed library (CD7): the facets go missing,
    /// the two vocabulary rows do not, and the failure has somewhere to be said.
    func testAFailedFacetFetchLeavesTheVocabularyRowsUsable() async throws {
        let health = try fixture("health")
        let unfiltered = try page(ids: ["a", "b"], total: 2)
        StubURLProtocol.configure { request in
            guard let url = request.url, !url.path.hasSuffix("/api/health") else {
                return StubURLProtocol.Response(status: 200, body: health)
            }
            if url.path.hasSuffix("/api/library/facets") {
                return StubURLProtocol.Response(status: 500, body: Data("{\"error\":\"handler failed\"}".utf8))
            }
            return StubURLProtocol.Response(status: 200, body: unfiltered)
        }
        let model = makeModel()

        await model.start()
        await model.loadFacets()

        XCTAssertNil(model.facets)
        guard case .failed = model.facetsPhase else {
            return XCTFail("a failed facet fetch has to be a state the sheet can render, not a silence")
        }
        XCTAssertEqual(LibraryFilters.statusOptions(model.facets).count, 3, "the contract's own three need no request")
        XCTAssertEqual(LibraryFilters.formatOptions(model.facets).count, 4)
    }

    // MARK: 3.12 — the filters ride on every page, and clearing restores the library

    func testTheFiltersRideOnThePageAfterTheFirstToo() async throws {
        try stubPages(
            first: try page(ids: ["a", "b"], total: 3),
            second: try page(ids: ["c"], total: 3, offset: 2)
        )
        let model = makeModel()

        await model.toggle("James S. A. Corey", in: .authors)
        XCTAssertEqual(model.books.map(\.id), ["a", "b"])
        await model.loadNextPageIfNeeded(current: try XCTUnwrap(model.books.last))

        XCTAssertEqual(model.books.map(\.id), ["a", "b", "c"], "the page after the first arrived at all")
        let requests = libraryRequests()
        XCTAssertEqual(requests.count, 2)
        for request in requests {
            XCTAssertEqual(query(request)["authors"], "James S. A. Corey", "the filter rides every page, not only the first")
            XCTAssertNil(query(request)["readStatus"], "and an axis with nothing in it is still not a parameter")
            XCTAssertEqual(query(request)["limit"], "100")
        }
        XCTAssertEqual(query(requests[0])["offset"], "0")
        XCTAssertEqual(query(requests[1])["offset"], "2")
    }

    /// **The half that makes the first half worth having.** A filter that narrowed
    /// the library and then could not be undone would be a trap; the count coming
    /// back is what says the whole library is on screen again.
    func testClearingTheFiltersAsksForTheWholeLibraryAgain() async throws {
        try stubFiltered(
            filtered: try page(ids: ["a"], total: 1),
            unfiltered: try page(ids: ["a", "b"], total: 8)
        )
        let model = makeModel()

        await model.toggle(ReadingStatus.reading)
        XCTAssertEqual(model.total, 1)
        XCTAssertEqual(model.books.map(\.id), ["a"])
        XCTAssertTrue(model.hasActiveFilters)
        XCTAssertEqual(query(try XCTUnwrap(libraryRequests().last))["readStatus"], "reading")

        await model.clearFilters()

        XCTAssertEqual(model.total, 8, "clearing restored the library the Mac reports")
        XCTAssertEqual(model.books.map(\.id), ["a", "b"])
        XCTAssertFalse(model.hasActiveFilters)
        let cleared = try XCTUnwrap(libraryRequests().last)
        for name in ["readStatus", "formats", "minRating", "authors", "series", "tags"] {
            XCTAssertNil(query(cleared)[name], "a cleared axis is not a parameter at all")
        }
    }

    /// The funnel's own guard: a change that changes nothing asks the Mac for
    /// nothing, the same rule `chooseSort` and `search` already hold.
    func testAFilterChangeThatChangesNothingAsksTheMacForNothing() async throws {
        try stubFiltered(filtered: try page(ids: ["a"], total: 1), unfiltered: try page(ids: ["a"], total: 1))
        let model = makeModel()

        await model.toggle(ReadingStatus.reading)
        let before = libraryRequests().count

        await model.setFilters(model.filters)
        await model.toggle(ReadingStatus.reading)  // twice is once: it was on, so this turns it off
        XCTAssertEqual(libraryRequests().count, before + 1, "the same set asked for nothing; the toggle-off asked for one")

        let after = libraryRequests().count
        await model.clearFilters()  // already empty
        XCTAssertEqual(libraryRequests().count, after, "clearing a clear set is not a request")
    }

    // MARK: 3.13 — a filter the reader cannot see the cause of

    /// The indicator's number, and what it means: **every value the reader has
    /// selected**, across every axis. Counting axes instead would put "2" over a
    /// library narrowed by four values.
    func testTheIndicatorCountsEveryValueAcrossEveryAxis() {
        var filters = LibraryFilters.none
        filters.toggle("Steven Kotler", in: .authors)
        filters.toggle("Margaret Weis", in: .authors)
        filters.toggle(LibraryFilters.Format.epub)
        filters.minRating = 3

        XCTAssertEqual(filters.selectedCount, 4)
        XCTAssertTrue(filters.isActive)

        filters.toggle("Margaret Weis", in: .authors)
        XCTAssertEqual(filters.selectedCount, 3, "turning one value off is one fewer filter")

        filters.clear()
        XCTAssertFalse(filters.isActive)
        XCTAssertEqual(filters.selectedCount, 0)
    }

    /// **The third empty screen, and why it is not the empty library.** A filter
    /// that matched nothing reaches the same empty grid a search does, and the two
    /// facts deserve different sentences — the Mac reports books, and these filters
    /// excluded all of them. Reading "the Mac reports no books yet" over a library
    /// of 7,100 is the defect this case exists to prevent.
    func testAFilterThatMatchedNothingIsNotAnEmptyLibrary() {
        var filters = LibraryFilters.none
        filters.toggle(ReadingStatus.read)
        filters.toggle(LibraryFilters.Format.pdf)

        let withFilters = LibraryQuery(filters: filters)
        XCTAssertEqual(LibraryEmptyState.of(withFilters, isEmpty: true), .noFilterMatches(2))
        XCTAssertNil(LibraryEmptyState.of(withFilters, isEmpty: false), "there is something to show")

        // A term outranks a filter: it is the narrower question and the one the
        // card can quote. The screen's control clears both.
        let withBoth = LibraryQuery(text: "zzz", filters: filters)
        XCTAssertEqual(LibraryEmptyState.of(withBoth, isEmpty: true), .noMatches("zzz"))

        // And no narrowing at all is still the library that is empty.
        XCTAssertEqual(LibraryEmptyState.of(LibraryQuery(), isEmpty: true), .libraryIsEmpty)
        XCTAssertEqual(LibraryEmptyState.of(LibraryQuery(text: "   ", filters: filters), isEmpty: true), .noFilterMatches(2), "whitespace is not a term, so the filters are the cause")
    }

    // MARK: The probe's own encoding

    /// The seam's string is what makes a filter run decidable with no tap, so it has
    /// to come back exactly as it went in — a lossy encoding would let a run log one
    /// filter set and apply another.
    func testTheProbeEncodingRoundTripsThroughTheAppsOwnParser() {
        let raw = "status=unread|reading|read;format=epub;rating=4;author=Steven Kotler;series=The Expanse;tag=running"
        let parsed = LibraryFilters.probe(raw)

        XCTAssertTrue(parsed.ignored.isEmpty)
        XCTAssertEqual(parsed.filters.readStatus, [.unread, .reading, .read])
        XCTAssertEqual(parsed.filters.formats, [.epub])
        XCTAssertEqual(parsed.filters.minRating, 4)
        XCTAssertEqual(parsed.filters.authors, ["Steven Kotler"])
        XCTAssertEqual(parsed.filters.series, ["The Expanse"])
        XCTAssertEqual(parsed.filters.tags, ["running"])
        XCTAssertEqual(parsed.filters.probeEncoding, "status=read|reading|unread;format=epub;rating=4;author=Steven Kotler;series=The Expanse;tag=running")

        // The round trip is on the *set*, not on the string: what travels back is
        // the same narrowing whatever order it was written in.
        XCTAssertEqual(LibraryFilters.probe(parsed.filters.probeEncoding).filters, parsed.filters)
        XCTAssertEqual(LibraryFilters.probe("author=B|A").filters.probeEncoding, "author=A|B", "the same set composes the same string")
        XCTAssertTrue(LibraryFilters.probe("").filters == .none, "an empty seam is not a filter")
    }

    /// **A token this build cannot use is reported, not dropped.** A seam silently
    /// ignored is a run that looks green and decides nothing — which is why the sort
    /// seam logs its fallback too.
    func testTheProbeParserSaysWhatItCouldNotUse() {
        let (filters, ignored) = LibraryFilters.probe("rating=9;format=docx;nonsense=1;status=reading;ratingish")

        XCTAssertEqual(filters.readStatus, [.reading])
        XCTAssertNil(filters.minRating, "9 is not a rating a book can carry")
        XCTAssertTrue(filters.formats.isEmpty)
        XCTAssertEqual(ignored.count, 4, "the out-of-range rating, the unknown format, the unknown axis and the token with no value")
    }

    // MARK: Helpers

    private nonisolated func facetRequests() -> [URLRequest] {
        StubURLProtocol.requests.filter { $0.url?.path.hasSuffix("/api/library/facets") == true }
    }

    private nonisolated func stubFacetsAndLibrary() throws {
        let health = try fixture("health")
        let facets = try fixture("facets")
        let unfiltered = try page(ids: ["a", "b"], total: 2)
        let filtered = try page(ids: ["a"], total: 1)
        StubURLProtocol.configure { request in
            guard let url = request.url, !url.path.hasSuffix("/api/health") else {
                return StubURLProtocol.Response(status: 200, body: health)
            }
            if url.path.hasSuffix("/api/library/facets") {
                return StubURLProtocol.Response(status: 200, body: facets)
            }
            let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            let isFiltered = items.contains { ["formats", "readStatus", "authors", "series", "tags", "minRating"].contains($0.name) }
            return StubURLProtocol.Response(status: 200, body: isFiltered ? filtered : unfiltered)
        }
    }
}
