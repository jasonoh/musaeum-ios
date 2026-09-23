import Foundation

/// **What the library screen is asking the Mac for** — the whole library, or a
/// search of it, in one order — as pure rules, so every one of them has a decider
/// that never needs a screen.
///
/// The three types here are deliberately not three files, on the Mac's own
/// precedent (`src/types/book.types.ts` carries `BookSort`, its labels, its guard
/// and `BookFilters` together): the concern is one thing, and splitting it would
/// scatter "what a sort is" across three places that then have to agree.
///
/// **Everything the contract decides is mirrored, not re-derived.** The order is
/// the server's — `GET /api/library` sorts on the Mac's own stored sort keys
/// (`../musaeum/docs/rest-api.md`), which is why nothing here compares two books:
/// a client-side sort could only reorder the page it happens to hold, and would
/// disagree with the Mac the moment a second page arrived.

// MARK: - The sort

/// The Mac's own eight curated options, in its own order, with its own wording.
///
/// Read off `src/components/layout/Toolbar.tsx` (`SORT_OPTIONS`) and
/// `src/types/book.types.ts` (`SORT_LABELS` / `sortLabel`) rather than invented:
/// a phone sort and a Mac sort that named the same order differently would be two
/// names for one question.
struct LibrarySort: Equatable, Hashable, Sendable {
    /// The six fields the contract's `sort` accepts. A seventh would be a 400.
    enum Field: String, CaseIterable, Sendable {
        case title
        case author
        case series
        case dateAdded = "date_added"
        case rating
        case readStatus = "read_status"
    }

    enum Direction: String, CaseIterable, Sendable {
        case asc
        case desc
    }

    let field: Field
    let direction: Direction

    /// The contract's `sort` parameter.
    var wireField: String { field.rawValue }

    /// The contract's `dir` parameter. Always sent, never left to the server's
    /// natural direction, even though its rule is the same rule: a request whose
    /// meaning depends on a default is a request whose meaning moves when the
    /// contract does.
    var wireDirection: String { direction.rawValue }

    /// The same words the Mac's dropdown shows — `sortLabel()`'s text, verbatim,
    /// for every pair the menu can produce (not only the eight shortcuts: a
    /// restored preference may name any of the twelve).
    var label: String {
        switch (field, direction) {
        case (.title, .asc): "Title A–Z"
        case (.title, .desc): "Title Z–A"
        case (.author, .asc): "Author A–Z"
        case (.author, .desc): "Author Z–A"
        case (.series, .asc): "Series"
        case (.series, .desc): "Series (reversed)"
        case (.dateAdded, .asc): "Oldest First"
        case (.dateAdded, .desc): "Recently Added"
        case (.rating, .asc): "Lowest Rated"
        case (.rating, .desc): "Highest Rated"
        case (.readStatus, .asc): "Read Status"
        case (.readStatus, .desc): "Read Status (reversed)"
        }
    }

    /// Where the phone starts, and the Mac's own default.
    static let `default` = LibrarySort(field: .title, direction: .asc)

    /// The Mac's curated shortcuts, in its own order.
    static let options: [LibrarySort] = [
        LibrarySort(field: .title, direction: .asc),
        LibrarySort(field: .title, direction: .desc),
        LibrarySort(field: .author, direction: .asc),
        LibrarySort(field: .series, direction: .asc),
        LibrarySort(field: .dateAdded, direction: .desc),
        LibrarySort(field: .dateAdded, direction: .asc),
        LibrarySort(field: .rating, direction: .desc),
        LibrarySort(field: .readStatus, direction: .asc),
    ]

    /// How this is stored: `field:direction`.
    ///
    /// **The shape is ours, not the Mac's.** The Mac persists a `BookSort`
    /// *object* and guards that with `isBookSort` (`book.types.ts:218`); `key(sort)`
    /// in `Toolbar.tsx` is a React key, not a stored value. What the two apps share
    /// is the field/direction vocabulary and the guard's *effect*, not the
    /// encoding — the phone owns its own storage, and one string is the whole of it.
    var storedKey: String { "\(field.rawValue):\(direction.rawValue)" }

    /// A stored or supplied key, decoded — **guarded**, the same way the Mac's
    /// `isBookSort` guards its persisted value.
    ///
    /// Storage is only as trustworthy as the build that wrote it, and the
    /// contract's own rule makes an unguarded value expensive rather than
    /// untidy: `sort=athor` is **refused with a 400** rather than defaulted
    /// ("a client that asked for `sort=athor` and silently received title order
    /// could never learn it had a typo"), so a preference this build no longer
    /// knows would surface to the reader as a broken library. Anything
    /// unrecognised falls back to the default.
    ///
    /// A *direction* is not restricted to the eight shortcuts: a value naming any
    /// of the twelve pairs the labels above cover is a sort the Mac can produce,
    /// and refusing it here would be this file inventing a rule the Mac does not
    /// have.
    static func stored(_ raw: String?) -> LibrarySort {
        guard let raw else { return .default }
        let parts = raw.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2,
              let field = Field(rawValue: parts[0]),
              let direction = Direction(rawValue: parts[1])
        else { return .default }
        return LibrarySort(field: field, direction: direction)
    }
}

// MARK: - The query

/// What the screen is narrowing the library to: a sort, and optionally a term.
///
/// Two of the Mac's decisions live here rather than in a view, because both are
/// rules a case can decide and neither is obvious:
///
/// - **A query of nothing but spaces is not a search.** The Mac trims before it
///   judges (`library.store.ts` — `query.trim() ? searchBooks : list`), and the
///   contract refuses a malformed *parameter* with a 400, so a client that sent
///   bare whitespace would be composing a question nothing can answer.
/// - **The sort stays live while searching.** That is what makes the same query
///   return the same books in the same order on both devices — the contract's own
///   sentence about why relevance is only the *default* when no sort is given
///   ("a search whose default were title order would disagree with the Mac's own
///   results"), and the Mac's own established behaviour.
struct LibraryQuery: Equatable, Sendable {
    var sort: LibrarySort = .default
    var text: String = ""

    /// The term that actually travels, or `nil` when the whole library is meant.
    var term: String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var isSearching: Bool { term != nil }
}

// MARK: - Nothing to show

/// Which of the **two** "nothing to show" screens applies.
///
/// This distinction only becomes reachable once search exists, and it is the
/// difference between "the connection works and the Mac has no books" and "this
/// term matched none of them" — two states that were the same screen while the
/// only way to get an empty grid was an empty library.
///
/// Decided from **view state the app already holds**, never from a new count:
/// both states are `books.isEmpty`, and what tells them apart is whether a term
/// was asked for. Corollary the slice-1 record already insisted on and this keeps
/// intact: *empty* and *still loading* are separate states, and the phase — not
/// this — is what tells those two apart, so a cold start does not flash "nothing
/// matches".
enum LibraryEmptyState: Equatable, Sendable {
    /// The Mac reports no books at all: there is no library to browse.
    case libraryIsEmpty
    /// The library has books and this term matched none of them. Carries the
    /// trimmed term, which is what the sentence names.
    case noMatches(String)

    /// `nil` when there is something to show. Two things arrive as arguments
    /// rather than as assumptions, so the answer is true for **every** input: the
    /// emptiness (a caller cannot ask this of a grid with books in it and be handed
    /// a screen it has not earned) and the query itself — whose `term` is already
    /// the trimmed one, so the rule for "is this a search at all" stays in exactly
    /// one place rather than being re-stated here.
    static func of(_ query: LibraryQuery, isEmpty: Bool) -> LibraryEmptyState? {
        guard isEmpty else { return nil }
        guard let term = query.term else { return .libraryIsEmpty }
        return .noMatches(term)
    }
}
