import Foundation

/// Everything this app knows about the wire shape lives here, and every member
/// is read from the contract document rather than from a running server:
/// `../musaeum/docs/rest-api.md`, API version 1. `scripts/vendor-contract-fixtures.sh`
/// extracts that document's own payload blocks into `Tests/Fixtures/contract/`,
/// and `ContractDecodeTests` decodes them, so the document and the models are
/// each other's decider.
///
/// **The rule that shapes this file (invariant 4):** the contract says every
/// field is *always present*, and a value the row does not hold is `null` —
/// "never absent". Synthesized `Codable` cannot tell an absent key from a
/// `null` one, so a member that went missing would decode to `nil` and a book
/// would quietly lose its title. Every model therefore reads through
/// `StrictObject`, which throws on an absent key and returns `nil` for a `null`.
enum ContractError: Error, Equatable, CustomStringConvertible {
    case missingField(String, at: String)
    case malformedField(String, at: String, value: String)
    case unsupportedAPIVersion(Int)

    var description: String {
        switch self {
        case let .missingField(field, path): "the contract requires \(path).\(field), and it is absent"
        case let .malformedField(field, path, value): "\(path).\(field) is not the shape the contract names: \(value)"
        case let .unsupportedAPIVersion(v): "the server speaks contract version \(v); this app speaks 1"
        }
    }
}

/// The contract version this app is written against.
let supportedAPIVersion = 1

struct AnyCodingKey: CodingKey {
    let stringValue: String
    var intValue: Int? { nil }
    init(_ string: String) { stringValue = string }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { nil }
}

/// A strict reader over one object of a contract payload.
struct StrictObject {
    let container: KeyedDecodingContainer<AnyCodingKey>
    let path: String

    private func require(_ key: String) throws {
        guard container.contains(AnyCodingKey(key)) else {
            throw ContractError.missingField(key, at: path)
        }
    }

    func value<T: Decodable>(_ key: String, as: T.Type) throws -> T {
        try require(key)
        do {
            return try container.decode(T.self, forKey: AnyCodingKey(key))
        } catch {
            throw ContractError.malformedField(key, at: path, value: String(describing: error))
        }
    }

    /// A member that is always present and non-null.
    func string(_ key: String) throws -> String { try value(key, as: String.self) }
    func int(_ key: String) throws -> Int { try value(key, as: Int.self) }
    func bool(_ key: String) throws -> Bool { try value(key, as: Bool.self) }
    func strings(_ key: String) throws -> [String] { try value(key, as: [String].self) }

    /// **The one deliberate exception to the always-present rule (invariant 4).**
    /// `shelves` is absent on a Mac older than the shelf slice: the member is not
    /// sent at all, and a required read would throw — taking the whole library
    /// down over a field the reader never sees. Absent and `null` both read as
    /// `[]`, because both spellings mean *this Mac reports no shelves*; every
    /// other member still throws when its key is missing.
    func stringsOrEmpty(_ key: String) throws -> [String] {
        let codingKey = AnyCodingKey(key)
        guard container.contains(codingKey) else { return [] }
        if (try? container.decodeNil(forKey: codingKey)) == true { return [] }
        return try value(key, as: [String].self)
    }

    /// **The second deliberate exception to the always-present rule (invariant 4).**
    /// `reflow` is absent from every payload a download stored before slice 8, and a download decodes its
    /// stored payload on every open — a required read would make each of them unopenable. Absent and `null`
    /// read as the default; a *present* member is still strict.
    func objectOrDefault<T: Decodable>(_ key: String, default fallback: T, as: T.Type = T.self) throws -> T {
        let codingKey = AnyCodingKey(key)
        guard container.contains(codingKey) else { return fallback }
        if (try? container.decodeNil(forKey: codingKey)) == true { return fallback }
        return try value(key, as: T.self)
    }

    /// A member that is always present and may be `null` — the contract's whole
    /// point, and the case synthesized decoding silently gets wrong.
    func optional<T: Decodable>(_ key: String, as: T.Type = T.self) throws -> T? {
        try require(key)
        do {
            return try container.decodeIfPresent(T.self, forKey: AnyCodingKey(key))
        } catch {
            throw ContractError.malformedField(key, at: path, value: String(describing: error))
        }
    }

    func optionalString(_ key: String) throws -> String? { try optional(key, as: String.self) }
    func optionalInt(_ key: String) throws -> Int? { try optional(key, as: Int.self) }
    func optionalDouble(_ key: String) throws -> Double? { try optional(key, as: Double.self) }
    func optionalDate(_ key: String) throws -> Date? {
        try optionalString(key).map { try ISO8601.parse($0, field: "\(path).\(key)") }
    }

    func object<T: Decodable>(_ key: String, as: T.Type = T.self) throws -> T { try value(key, as: T.self) }
}

/// The contract's timestamps are ISO 8601 with milliseconds (`2026-08-13T18:04:21.000Z`)
/// and are never a number. A value that does not parse is a contract breach, not
/// a date we should invent.
enum ISO8601 {
    nonisolated(unsafe) private static let withMillis: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    nonisolated(unsafe) private static let plain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func parse(_ text: String, field: String) throws -> Date {
        if let d = withMillis.date(from: text) ?? plain.date(from: text) { return d }
        throw ContractError.malformedField(field, at: field, value: text)
    }

    static func string(_ date: Date) -> String { withMillis.string(from: date) }
}

// MARK: - GET /api/health

enum LibraryState: String, Decodable, Equatable, Sendable {
    case online
    case offline
}

struct Health: Decodable, Equatable, Sendable {
    let apiVersion: Int
    let version: String
    let books: Int
    let library: LibraryState

    init(from decoder: any Decoder) throws {
        let o = StrictObject(container: try decoder.container(keyedBy: AnyCodingKey.self), path: "health")
        apiVersion = try o.int("apiVersion")
        version = try o.string("version")
        books = try o.int("books")
        let raw: String = try o.string("library")
        guard let state = LibraryState(rawValue: raw) else {
            throw ContractError.malformedField("library", at: "health", value: raw)
        }
        library = state
    }
}

// MARK: - a book (the `library` member, the detail route, and the reading reply)

enum ReadingStatus: String, Decodable, Equatable, Hashable, Sendable {
    case unread
    case reading
    case read
}

struct CoverInfo: Decodable, Equatable, Hashable, Sendable {
    let thumb: Bool
    let full: Bool
    /// The row's `lastModified`, which the client appends to its own cache key
    /// (`…?size=full&v=<version>`) — the route ignores it, and without it a
    /// replaced cover is answered from a cache.
    let version: String?

    init(from decoder: any Decoder) throws {
        let o = StrictObject(container: try decoder.container(keyedBy: AnyCodingKey.self), path: "book.cover")
        thumb = try o.bool("thumb")
        full = try o.bool("full")
        version = try o.optionalString("version")
    }
}

/// What the Mac says about laying a PDF out as an EPUB. `available` is the *server's* eligibility ("a PDF and no
/// EPUB"); the phone does not re-derive it. Read through `objectOrDefault`: absent in every pre-slice-8 payload.
struct Reflow: Decodable, Equatable, Hashable, Sendable {
    let available: Bool

    init(available: Bool) { self.available = available }

    init(from decoder: any Decoder) throws {
        let o = StrictObject(container: try decoder.container(keyedBy: AnyCodingKey.self), path: "book.reflow")
        available = try o.bool("available")
    }
}

/// The body of a `202` from `GET /api/books/{id}/file?format=reflow`: the pass is running.
struct ReflowProgress: Decodable, Equatable, Sendable {
    let phase: String
    let completed: Int
    let total: Int

    init(from decoder: any Decoder) throws {
        let o = StrictObject(container: try decoder.container(keyedBy: AnyCodingKey.self), path: "reflow progress")
        phase = try o.string("phase")
        completed = try o.int("completed")
        total = try o.int("total")
    }
}

/// The body of a `422`: the Mac looked and cannot lay this book out, and says why.
struct CannotReflowPayload: Decodable, Equatable, Sendable {
    let error: String
    let reason: String

    init(from decoder: any Decoder) throws {
        let o = StrictObject(container: try decoder.container(keyedBy: AnyCodingKey.self), path: "cannot reflow")
        error = try o.string("error")
        reason = try o.string("reason")
    }
}

/// The phone's whole view of where a book is. `percent` is a fraction
/// (`0.42` = 42%); `null` means the book has never been opened, which is *not*
/// the same as 0%. The Mac's CFI is deliberately not on the wire.
struct Reading: Decodable, Equatable, Hashable, Sendable {
    let status: ReadingStatus
    let percent: Double?
    let updatedAt: Date?

    init(from decoder: any Decoder) throws {
        let o = StrictObject(container: try decoder.container(keyedBy: AnyCodingKey.self), path: "book.reading")
        let raw: String = try o.string("status")
        guard let s = ReadingStatus(rawValue: raw) else {
            throw ContractError.malformedField("status", at: "book.reading", value: raw)
        }
        status = s
        percent = try o.optionalDouble("percent")
        updatedAt = try o.optionalDate("updatedAt")
    }
}

struct ContractBook: Decodable, Equatable, Hashable, Identifiable, Sendable {
    let id: String
    let title: String
    let author: String?
    let publisher: String?
    let publishedDate: String?
    let language: String?
    let summary: String?
    let isbn10: String?
    let isbn13: String?
    let goodreadsId: String?
    let openlibraryId: String?
    let seriesName: String?
    let seriesIndex: Double?
    let seriesTotal: Int?
    let tags: [String]
    let rating: Int?
    let dateAdded: Date?
    let lastModified: Date?
    /// In **preference order** — `epub`, `azw3`, `mobi`, `pdf` — so the first
    /// member is the file the reader would open. The row's own stored order is
    /// deliberately not on the wire.
    let formats: [String]
    let fileSizeBytes: Int?
    let cover: CoverInfo
    let reading: Reading
    /// The shelves this book is on, **ids only** — names come from
    /// `GET /api/shelves`, so a rename changes no book payload. Read through
    /// `stringsOrEmpty`: this is the contract's one member whose absence is not
    /// a refusal (see `StrictObject.stringsOrEmpty`), because a pre-shelves Mac
    /// omits it and the library must still decode.
    let shelves: [String]
    /// Whether the Mac can lay this book out as an EPUB. Read through `objectOrDefault` (absent = not available).
    let reflow: Reflow

    /// The format this client asks for: the wire's preference order is the
    /// server's own rule, so the client does not re-derive it.
    var preferredFormat: String? { formats.first }

    init(from decoder: any Decoder) throws {
        let o = StrictObject(container: try decoder.container(keyedBy: AnyCodingKey.self), path: "book")
        id = try o.string("id")
        title = try o.string("title")
        author = try o.optionalString("author")
        publisher = try o.optionalString("publisher")
        publishedDate = try o.optionalString("publishedDate")
        language = try o.optionalString("language")
        summary = try o.optionalString("description")
        isbn10 = try o.optionalString("isbn10")
        isbn13 = try o.optionalString("isbn13")
        goodreadsId = try o.optionalString("goodreadsId")
        openlibraryId = try o.optionalString("openlibraryId")
        seriesName = try o.optionalString("seriesName")
        seriesIndex = try o.optionalDouble("seriesIndex")
        seriesTotal = try o.optionalInt("seriesTotal")
        tags = try o.strings("tags")
        rating = try o.optionalInt("rating")
        dateAdded = try o.optionalDate("dateAdded")
        lastModified = try o.optionalDate("lastModified")
        formats = try o.strings("formats")
        fileSizeBytes = try o.optionalInt("fileSizeBytes")
        cover = try o.object("cover", as: CoverInfo.self)
        reading = try o.object("reading", as: Reading.self)
        shelves = try o.stringsOrEmpty("shelves")
        reflow = try o.objectOrDefault("reflow", default: Reflow(available: false))
    }
}

// MARK: - GET /api/library

struct LibraryPage: Decodable, Equatable, Sendable {
    let books: [ContractBook]
    /// Every row the query matches, independent of the page taken.
    let total: Int
    /// The window actually served — a clamped `limit` is visible here.
    let limit: Int
    let offset: Int

    init(from decoder: any Decoder) throws {
        let o = StrictObject(container: try decoder.container(keyedBy: AnyCodingKey.self), path: "library")
        books = try o.value("books", as: [ContractBook].self)
        total = try o.int("total")
        limit = try o.int("limit")
        offset = try o.int("offset")
    }

    /// Exactly the contract's own walk: pages until `offset + books.count >= total`.
    var isLastPage: Bool { offset + books.count >= total }
    var nextOffset: Int { offset + books.count }
}

// MARK: - GET /api/library/facets

struct Facet: Decodable, Equatable, Sendable {
    let value: String
    let count: Int

    init(from decoder: any Decoder) throws {
        let o = StrictObject(container: try decoder.container(keyedBy: AnyCodingKey.self), path: "facet")
        value = try o.string("value")
        count = try o.int("count")
    }
}

/// The filter counts, over the whole library — not narrowed by any filter the
/// list route was given, so a client can show what it may filter *to*.
struct Facets: Decodable, Equatable, Sendable {
    let authors: [Facet]
    let series: [Facet]
    let tags: [Facet]
    let formats: [Facet]
    let readStatus: [Facet]

    init(from decoder: any Decoder) throws {
        let o = StrictObject(container: try decoder.container(keyedBy: AnyCodingKey.self), path: "facets")
        authors = try o.value("authors", as: [Facet].self)
        series = try o.value("series", as: [Facet].self)
        tags = try o.value("tags", as: [Facet].self)
        formats = try o.value("formats", as: [Facet].self)
        readStatus = try o.value("readStatus", as: [Facet].self)
    }
}

// MARK: - GET /api/shelves, and the membership writes

/// One shelf as the route answers it (D6/D10): `count` is the books the library
/// holds on it, and `updatedAt` is the shelf file's own clock.
///
/// `kind` is decoded and **not branched on**: the document says the route
/// answers `"manual"` only, so the route is the filter — an enum here would
/// refuse a payload the contract could legitimately grow. `updatedAt` is drawn
/// nowhere (no screen asks when a shelf was last touched) but is decoded so the
/// golden decides the whole shape.
struct Shelf: Decodable, Equatable, Hashable, Identifiable, Sendable {
    let id: String
    let name: String
    let kind: String
    let count: Int
    let updatedAt: Date?

    init(from decoder: any Decoder) throws {
        let o = StrictObject(container: try decoder.container(keyedBy: AnyCodingKey.self), path: "shelf")
        id = try o.string("id")
        name = try o.string("name")
        kind = try o.string("kind")
        count = try o.int("count")
        updatedAt = try o.optionalDate("updatedAt")
    }
}

/// The `GET /api/shelves` envelope. The order is the contract's own
/// (alphabetical, `COLLATE NOCASE` then id) and this client lists shelves in it
/// rather than re-sorting: one order for the Mac's sidebar and the phone's menu.
struct Shelves: Decodable, Equatable, Sendable {
    let shelves: [Shelf]

    init(from decoder: any Decoder) throws {
        let o = StrictObject(container: try decoder.container(keyedBy: AnyCodingKey.self), path: "shelves")
        shelves = try o.value("shelves", as: [Shelf].self)
    }
}

/// The membership writes' reply: `200 { "book": … }`, the book read back **after**
/// the write (D10) — which is what lets the checklist refresh from the server's
/// own answer rather than from a local flip (F6).
struct MembershipResult: Decodable, Equatable, Sendable {
    let book: ContractBook

    init(from decoder: any Decoder) throws {
        let o = StrictObject(container: try decoder.container(keyedBy: AnyCodingKey.self), path: "membership")
        book = try o.object("book", as: ContractBook.self)
    }
}

// MARK: - the one write's reply (slice 2 consumes this; the shape is decoded now
// so the contract's block and the model cannot drift apart)

struct ReadingResult: Decodable, Equatable, Sendable {
    /// `true` when the report was written, `false` when it was refused as stale —
    /// a refusal is a 200, because nothing failed.
    let applied: Bool
    let book: ContractBook

    init(from decoder: any Decoder) throws {
        let o = StrictObject(container: try decoder.container(keyedBy: AnyCodingKey.self), path: "reading")
        applied = try o.bool("applied")
        book = try o.object("book", as: ContractBook.self)
    }
}

// MARK: - POST /api/books — the import the upload created

/// Which book an upload collided with, and on what evidence — the Mac's own
/// policy answer, not a question for a human (D3).
///
/// `existingAuthor` is **`null` when the matched book holds no author** — the
/// wire really sends `null` rather than a placeholder, and a client that decodes
/// it as a required string loses the whole `201` body over a book with no
/// author. `existingBookId`, `existingTitle` and `matchType` are always present.
struct DuplicateMatch: Decodable, Equatable, Sendable {
    enum MatchType: String, Decodable, Equatable, Sendable {
        case isbn
        case titleAuthor = "title_author"
    }

    let existingBookId: String
    let existingTitle: String
    let existingAuthor: String?
    let matchType: MatchType

    init(from decoder: any Decoder) throws {
        let o = StrictObject(container: try decoder.container(keyedBy: AnyCodingKey.self), path: "import.duplicate")
        existingBookId = try o.string("existingBookId")
        existingTitle = try o.string("existingTitle")
        existingAuthor = try o.optionalString("existingAuthor")
        let raw: String = try o.string("matchType")
        guard let type = MatchType(rawValue: raw) else {
            throw ContractError.malformedField("matchType", at: "import.duplicate", value: raw)
        }
        matchType = type
    }
}

/// The `201`'s payload: **the book as the row stood immediately after the import,
/// before hydration has finished** (the Mac's S7), which is why `seriesName`,
/// `cover.version` and the rest may still be `null` here and be filled in by the
/// pass that continues after the answer. The phone gets its id now — a second
/// fetch would only learn that the same book improved.
struct ImportResult: Decodable, Equatable, Sendable {
    let book: ContractBook
    /// The collision the Mac answered by policy, or `null` for the ordinary case.
    /// `duplicate` is always present as a key and is `null` rather than absent
    /// (invariant 4).
    let duplicate: DuplicateMatch?

    init(from decoder: any Decoder) throws {
        let o = StrictObject(container: try decoder.container(keyedBy: AnyCodingKey.self), path: "import")
        book = try o.object("book", as: ContractBook.self)
        duplicate = try o.optional("duplicate", as: DuplicateMatch.self)
    }
}

// MARK: - every refusal

struct APIErrorPayload: Decodable, Equatable, Sendable {
    let error: String

    init(from decoder: any Decoder) throws {
        let o = StrictObject(container: try decoder.container(keyedBy: AnyCodingKey.self), path: "error")
        error = try o.string("error")
    }
}

