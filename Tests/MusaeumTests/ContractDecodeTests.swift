import XCTest

@testable import Musaeum

/// The contract's own payload blocks, decoded.
///
/// The fixtures are not hand-written: `scripts/vendor-contract-fixtures.sh`
/// extracts them from `../musaeum/docs/rest-api.md`, which is the same text the
/// Mac repo's suite parses to decide its payload shaper. So this file decides
/// **whether this app can decode what the document promises**, and a field the
/// document names and these models do not is a failure here rather than a
/// surprise on a phone.
final class ContractDecodeTests: XCTestCase {
    private func fixture(_ name: String) throws -> Data {
        let bundle = Bundle(for: ContractDecodeTests.self)
        guard let url = bundle.url(forResource: name, withExtension: "json") else {
            throw XCTSkip("the contract fixture \(name).json is not in the test bundle — run scripts/vendor-contract-fixtures.sh")
        }
        return try Data(contentsOf: url)
    }

    private func decode<T: Decodable>(_ type: T.Type, _ name: String) throws -> T {
        try JSONDecoder().decode(type, from: try fixture(name))
    }

    func testBookFixtureCarriesReflow() throws {
        let book = try JSONDecoder().decode(ContractBook.self, from: fixture("book"))
        XCTAssertEqual(book.reflow, Reflow(available: false))
    }

    /// **Every payload stored before this slice lacks the key**, and downloads decode their stored payload on every open.
    func testAPayloadWithoutReflowStillDecodesAsNotAvailable() throws {
        var object = try JSONSerialization.jsonObject(with: fixture("book")) as! [String: Any]
        object.removeValue(forKey: "reflow")
        let data = try JSONSerialization.data(withJSONObject: object)
        XCTAssertEqual(try JSONDecoder().decode(ContractBook.self, from: data).reflow.available, false)
        object["reflow"] = NSNull()
        let nulled = try JSONSerialization.data(withJSONObject: object)
        XCTAssertEqual(try JSONDecoder().decode(ContractBook.self, from: nulled).reflow.available, false)
    }

    func testAPresentButMalformedReflowThrows() throws {
        var object = try JSONSerialization.jsonObject(with: fixture("book")) as! [String: Any]
        object["reflow"] = ["available": "yes"]
        let data = try JSONSerialization.data(withJSONObject: object)
        XCTAssertThrowsError(try JSONDecoder().decode(ContractBook.self, from: data))
        object["reflow"] = [String: Any]()
        let empty = try JSONSerialization.data(withJSONObject: object)
        XCTAssertThrowsError(try JSONDecoder().decode(ContractBook.self, from: empty))
    }

    func testHealthDecodes() throws {
        let health = try decode(Health.self, "health")
        XCTAssertEqual(health.apiVersion, 1)
        // The document's own block, which moved 0.1.0 → 0.5.0 without the
        // fixtures being re-vendored: the re-vendor of 2026-09-28 (the shelves
        // slice) brought it up to date and this assertion was the one stale
        // thing it exposed. It asserts **the document's value**, never a
        // version this app remembers the Mac having.
        XCTAssertEqual(health.version, "0.5.0")
        XCTAssertEqual(health.books, 7100)
        XCTAssertEqual(health.library, .online)
    }

    func testLibraryPageDecodesWithItsWindowAndTotal() throws {
        let page = try decode(LibraryPage.self, "library")
        XCTAssertEqual(page.total, 1)
        XCTAssertEqual(page.limit, 100)
        XCTAssertEqual(page.offset, 0)
        XCTAssertEqual(page.books.count, 1)
        XCTAssertTrue(page.isLastPage)
    }

    func testBookDecodesEveryMemberTheDocumentNames() throws {
        let book = try decode(ContractBook.self, "book")
        XCTAssertEqual(book.id, "6f1a1f2e-3c4d-4e5f-8a9b-0c1d2e3f4a5b")
        XCTAssertEqual(book.title, "Leviathan Wakes")
        XCTAssertEqual(book.author, "James S. A. Corey")
        XCTAssertEqual(book.publisher, "Orbit")
        XCTAssertEqual(book.publishedDate, "2011-06-15")
        XCTAssertEqual(book.language, "en")
        XCTAssertEqual(book.isbn10, "0316123266")
        XCTAssertEqual(book.isbn13, "9780316123265")
        XCTAssertEqual(book.goodreadsId, "8855321")
        XCTAssertEqual(book.openlibraryId, "OL25167455W")
        XCTAssertEqual(book.seriesName, "The Expanse")
        XCTAssertEqual(book.seriesIndex, 1)
        XCTAssertEqual(book.seriesTotal, 9)
        XCTAssertEqual(book.tags, ["space opera", "science fiction"])
        XCTAssertEqual(book.rating, 5)
        XCTAssertEqual(book.formats, ["epub", "mobi"])
        XCTAssertEqual(book.fileSizeBytes, 4_731_892)
        XCTAssertNotNil(book.dateAdded)
        XCTAssertNotNil(book.lastModified)
        XCTAssertNotNil(book.summary)
    }

    /// `formats` is in preference order on the wire, and the first member is the
    /// file the reader would open. The client takes that as given rather than
    /// re-deriving a preference of its own.
    func testPreferredFormatIsTheWiresOwnOrder() throws {
        let book = try decode(ContractBook.self, "book")
        XCTAssertEqual(book.preferredFormat, "epub")

        var reordered = try JSONSerialization.jsonObject(with: try fixture("book")) as! [String: Any]
        reordered["formats"] = ["pdf", "mobi"]
        let flipped = try JSONDecoder().decode(
            ContractBook.self,
            from: JSONSerialization.data(withJSONObject: reordered)
        )
        XCTAssertEqual(flipped.preferredFormat, "pdf")
    }

    func testCoverVersionAndReadingStateDecode() throws {
        let book = try decode(ContractBook.self, "book")
        XCTAssertTrue(book.cover.thumb)
        XCTAssertTrue(book.cover.full)
        XCTAssertEqual(book.cover.version, "2026-09-21T09:12:00.000Z")
        XCTAssertEqual(book.reading.status, .reading)
        XCTAssertEqual(book.reading.percent, 0.42)
        XCTAssertNotNil(book.reading.updatedAt)
    }

    func testFacetsDecode() throws {
        let facets = try decode(Facets.self, "facets")
        XCTAssertEqual(facets.authors.first?.value, "James S. A. Corey")
        XCTAssertEqual(facets.authors.first?.count, 9)
        XCTAssertEqual(facets.readStatus, [Facet.fixture(value: "reading", count: 1)])
    }

    func testReadingReplyDecodes() throws {
        let result = try decode(ReadingResult.self, "reading")
        XCTAssertTrue(result.applied)
        XCTAssertEqual(result.book.title, "Leviathan Wakes")
        XCTAssertEqual(result.book.reading.percent, 0.42)
    }

    func testErrorPayloadDecodes() throws {
        let payload = try decode(APIErrorPayload.self, "error")
        XCTAssertEqual(payload.error, "not found")
    }

    /// **The contract's central promise, decided:** "every field is always
    /// present; a value the row does not hold is `null` (never absent, never
    /// `0`), so a client's decoding is unconditional". A missing key must
    /// therefore throw rather than decode to `nil` — the difference between a
    /// book with no title and a book whose title stopped travelling.
    func testAMissingAlwaysPresentFieldIsRefused() throws {
        for field in ["title", "id", "formats", "cover", "reading", "tags"] {
            let stripped = try book(with: field, setTo: .remove)
            XCTAssertThrowsError(
                try JSONDecoder().decode(ContractBook.self, from: stripped),
                "\(field) is always present per the contract, so its absence must throw"
            ) { error in
                guard case let .missingField(name, _) = error as? ContractError else {
                    return XCTFail("expected a missing-field refusal for \(field), got \(error)")
                }
                XCTAssertEqual(name, field)
            }
        }
    }

    /// The other half: an explicit `null` is not an absence, and decodes.
    func testAnExplicitNullDecodesToNil() throws {
        for field in ["author", "publisher", "isbn10", "seriesName", "seriesIndex", "rating", "fileSizeBytes"] {
            let nulled = try book(with: field, setTo: .null)
            let decoded = try JSONDecoder().decode(ContractBook.self, from: nulled)
            switch field {
            case "author": XCTAssertNil(decoded.author)
            case "publisher": XCTAssertNil(decoded.publisher)
            case "isbn10": XCTAssertNil(decoded.isbn10)
            case "seriesName": XCTAssertNil(decoded.seriesName)
            case "seriesIndex": XCTAssertNil(decoded.seriesIndex)
            case "rating": XCTAssertNil(decoded.rating)
            case "fileSizeBytes": XCTAssertNil(decoded.fileSizeBytes)
            default: XCTFail("unhandled field \(field)")
            }
        }
    }

    /// `percent` is a nullable member with a real *value* grammar: `null` means
    /// "never opened", which is not 0%.
    func testReadingPercentDistinguishesNullFromZero() throws {
        let neverOpened = try library(with: "percent", inReadingOf: 0, setTo: .null)
        let page = try JSONDecoder().decode(LibraryPage.self, from: neverOpened)
        XCTAssertNil(page.books[0].reading.percent)

        let atZero = try library(with: "percent", inReadingOf: 0, setTo: .number(0))
        let zero = try JSONDecoder().decode(LibraryPage.self, from: atZero)
        XCTAssertEqual(zero.books[0].reading.percent, 0)
    }

    // MARK: the shelves (slice 7)

    func testShelvesPayloadDecodes() throws {
        let payload = try decode(Shelves.self, "shelves")
        XCTAssertEqual(payload.shelves.count, 1)
        let shelf = try XCTUnwrap(payload.shelves.first)
        XCTAssertEqual(shelf.id, "b2c3d4e5-6f70-4182-93a4-b5c6d7e8f901")
        XCTAssertEqual(shelf.name, "To Read")
        XCTAssertEqual(shelf.kind, "manual")
        XCTAssertEqual(shelf.count, 3)
        XCTAssertNotNil(shelf.updatedAt)
    }

    func testMembershipReplyDecodes() throws {
        let result = try decode(MembershipResult.self, "membership")
        XCTAssertEqual(result.book.id, "6f1a1f2e-3c4d-4e5f-8a9b-0c1d2e3f4a5b")
        XCTAssertEqual(result.book.shelves, ["b2c3d4e5-6f70-4182-93a4-b5c6d7e8f901"])
    }

    func testTheBookGoldenCarriesItsShelves() throws {
        let book = try decode(ContractBook.self, "book")
        XCTAssertEqual(book.shelves, ["b2c3d4e5-6f70-4182-93a4-b5c6d7e8f901"])
    }

    /// **The one deliberate exception to the always-present rule** (invariant 4,
    /// and D11 names it): a pre-shelves Mac omits `shelves`, and a required read
    /// would take the whole library down over a member the reader never sees.
    /// Absent reads as `[]`; so does an explicit `null` — both mean *this Mac
    /// reports no shelves*. Every other member's absence still throws, which the
    /// case above holds unchanged.
    func testBookShelvesAreTheOneAbsenceThatDecodes() throws {
        let absent = try book(with: "shelves", setTo: .remove)
        XCTAssertEqual(try JSONDecoder().decode(ContractBook.self, from: absent).shelves, [])

        let nulled = try book(with: "shelves", setTo: .null)
        XCTAssertEqual(try JSONDecoder().decode(ContractBook.self, from: nulled).shelves, [])
    }

    /// The shelf model itself is strict like every other — only the *book's*
    /// `shelves` member bends invariant 4; the payload that carries the shelf
    /// list does not.
    func testAShelfMissingAnAlwaysPresentFieldIsRefused() throws {
        for field in ["id", "name", "kind", "count"] {
            var object = try JSONSerialization.jsonObject(with: try fixture("shelves")) as! [String: Any]
            var shelves = object["shelves"] as! [[String: Any]]
            shelves[0] = applying(Mutation.remove, to: field, in: shelves[0])
            object["shelves"] = shelves
            let data = try JSONSerialization.data(withJSONObject: object)
            XCTAssertThrowsError(
                try JSONDecoder().decode(Shelves.self, from: data),
                "\(field) is always present per the contract, so its absence must throw"
            )
        }
    }

    // MARK: fixture surgery

    private enum Mutation {
        case remove
        case null
        case number(Double)
        case text(String)
    }

    private func book(with field: String, setTo mutation: Mutation) throws -> Data {
        var object = try JSONSerialization.jsonObject(with: try fixture("book")) as! [String: Any]
        object = applying(mutation, to: field, in: object)
        return try JSONSerialization.data(withJSONObject: object)
    }

    private func library(with field: String, inReadingOf index: Int, setTo mutation: Mutation) throws -> Data {
        var object = try JSONSerialization.jsonObject(with: try fixture("library")) as! [String: Any]
        var books = object["books"] as! [[String: Any]]
        var reading = books[index]["reading"] as! [String: Any]
        reading = applying(mutation, to: field, in: reading)
        books[index]["reading"] = reading
        object["books"] = books
        return try JSONSerialization.data(withJSONObject: object)
    }

    private func applying(_ mutation: Mutation, to field: String, in object: [String: Any]) -> [String: Any] {
        var object = object
        switch mutation {
        case .remove: object.removeValue(forKey: field)
        case .null: object[field] = NSNull()
        case let .number(value): object[field] = value
        case let .text(value): object[field] = value
        }
        return object
    }
}

private extension Facet {
    static func fixture(value: String, count: Int) -> Facet {
        let json = #"{"value":"\#(value)","count":\#(count)}"#
        // swiftlint:disable:next force_try
        return try! JSONDecoder().decode(Facet.self, from: Data(json.utf8))
    }
}
