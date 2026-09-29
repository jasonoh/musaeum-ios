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
    /// The seven fields the contract's `sort` accepts — six anywhere, and
    /// `shelf_added` **only inside a shelf** (D8): the server refuses it without
    /// a `shelf` to order by, with a 400, so nothing outside a scope may send it.
    enum Field: String, CaseIterable, Sendable {
        case title
        case author
        case series
        case dateAdded = "date_added"
        case rating
        case readStatus = "read_status"
        case shelfAdded = "shelf_added"
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
        // The Mac's own strings (`../musaeum/src/types/book.types.ts:219-221`),
        // like every other label here — and its natural direction is `desc`
        // (`:249`), which is what D8 makes the default inside a shelf.
        case (.shelfAdded, .desc): "Date Added to Shelf, Newest First"
        case (.shelfAdded, .asc): "Date Added to Shelf, Oldest First"
        }
    }

    /// **What the bar draws, where the Mac's own wording will not fit.**
    ///
    /// `label` is the Mac's phrase and stays the Mac's phrase: it is what the sort
    /// menu offers, and a phone that *named* an order differently from the Mac would
    /// be two names for one question. The bar is not a name, though — it is a 402 pt
    /// phone, and the Mac's shelf phrase measures **255.5 pt** at the bar's own
    /// 17 pt (`scripts/measure-bar-text.swift`), against a whole budget of about
    /// 120 pt — the width *Recently Added*, the longest of the eight, already takes.
    /// That is not a label that wants truncating in front of a reader; it is a
    /// sentence written for a menu row, and the bar is where it gets its short form.
    ///
    /// The short form keeps what the control is *for* — which order the list is in —
    /// and drops what the screen already says: the scope chip beside the search field
    /// names the open shelf, so the bar names the shelf's own axis and its direction.
    /// The menu still offers the Mac's whole sentence, and the wire still carries
    /// `shelf_added`, so nothing else about the order changes.
    ///
    /// **It is also the fix for the owner's bleed of 2026-09-29** — 255 pt of label
    /// beside a wordmark is a row wider than the phone, and the row took the whole
    /// page with it (`docs/evidence/shelf-bar/`). Reversal is one line: this property
    /// is the only place the bar's wording lives.
    var barLabel: String {
        switch (field, direction) {
        case (.shelfAdded, .desc): "Shelf: Newest"
        case (.shelfAdded, .asc): "Shelf: Oldest"
        default: label
        }
    }

    /// Where the phone starts, and the Mac's own default.
    static let `default` = LibrarySort(field: .title, direction: .asc)

    /// The Mac's curated shortcuts for the whole library, in its own order.
    static let allBooksOptions: [LibrarySort] = [
        LibrarySort(field: .title, direction: .asc),
        LibrarySort(field: .title, direction: .desc),
        LibrarySort(field: .author, direction: .asc),
        LibrarySort(field: .series, direction: .asc),
        LibrarySort(field: .dateAdded, direction: .desc),
        LibrarySort(field: .dateAdded, direction: .asc),
        LibrarySort(field: .rating, direction: .desc),
        LibrarySort(field: .readStatus, direction: .asc),
    ]

    /// The two *Date Added to Shelf* pairs — **drawn inside a shelf only** (F2):
    /// the order is meaningless outside one, and the server refuses
    /// `sort=shelf_added` without a `shelf` with a 400, so a menu that offered
    /// it outside would be offering a refusal.
    static let shelfAddedOptions: [LibrarySort] = [
        LibrarySort(field: .shelfAdded, direction: .desc),
        LibrarySort(field: .shelfAdded, direction: .asc),
    ]

    /// What the sort menu draws: the All Books eight, plus the shelf pairs when
    /// a shelf is open.
    static func options(inShelf: Bool) -> [LibrarySort] {
        inShelf ? allBooksOptions + shelfAddedOptions : allBooksOptions
    }

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
              let direction = Direction(rawValue: parts[1]),
              // **`shelf_added` is refused here** (F2): it is inside-only, and
              // the model never persists it — a sort chosen inside a shelf is the
              // scope's own order, restored from `priorSort` and not from
              // storage. A stored key naming it could only come from a build
              // that did not know the rule, and outside a shelf the server
              // answers it with a 400.
              field != .shelfAdded
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
    /// The shelf this screen is scoped to (slice 7a), or `nil` for the whole
    /// library. It sits here for the same reason `filters` does: every request
    /// is composed from the whole query at once, and a scope kept on the model
    /// instead would be a second thing a page two could forget — 3.3's failure.
    ///
    /// It carries the whole `Shelf`, not an id: the label beside the field and
    /// the empty shelf's own sentence both need the name, and a second
    /// id-and-name pair would be a second vocabulary for one thing.
    var shelf: Shelf?
    /// The axes a term cannot express (slice 3b): read status, format, a rating
    /// floor, and the author/series/tag values.
    ///
    /// It sits inside the query rather than beside it because it answers the same
    /// question the sort and the term answer — *what is this screen asking the Mac
    /// for* — and because every request has to be composed from all of it at
    /// once. A second property on the model would be a second thing a `request`
    /// could forget, and forgetting it is the failure 3.3 and 3.12 both name.
    var filters: LibraryFilters = .none

    /// What the field's prompt says — the scope's own name when one is open
    /// (the Mac's copy, `Search “To Read”`, R3), the stock line otherwise.
    /// A rule rather than a view's private string, so a case can decide it.
    var searchPlaceholder: String {
        shelf.map { "Search “\($0.name)”" } ?? "Search titles, authors, series…"
    }

    /// The term that actually travels, or `nil` when the whole library is meant.
    var term: String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var isSearching: Bool { term != nil }
}

// MARK: - Nothing to show

/// Which of the **four** "nothing to show" screens applies.
///
/// This distinction only becomes reachable once search exists, and it is the
/// difference between "the connection works and the Mac has no books", "this
/// term matched none of them" and "these filters matched none of them" — three
/// states that were one screen while the only way to get an empty grid was an
/// empty library.
///
/// **The third case is slice 3b's, and it is 3.13 arriving through the copy
/// rather than through a control.** A filter with nothing to match reaches an
/// empty grid exactly as a search does, and the two facts deserve different
/// sentences — the library has books, and these filters excluded all of them. A
/// screen saying "the Mac reports no books yet" over a library of 7,100 is a
/// lie the reader has no way to catch, which is the same class of defect as an
/// indicator nobody can see.
///
/// Decided from **view state the app already holds**, never from a new count:
/// every case is `books.isEmpty`, and what tells them apart is whether a term was
/// asked for and whether any filter is on. Corollary the slice-1 record already
/// insisted on and this keeps intact: *empty* and *still loading* are separate
/// states, and the phase — not this — is what tells those two apart, so a cold
/// start does not flash "nothing matches".
enum LibraryEmptyState: Equatable, Sendable {
    /// The Mac reports no books at all: there is no library to browse.
    case libraryIsEmpty
    /// **A shelf is open and it holds nothing.** Its own case and its own
    /// sentence, because `libraryIsEmpty` would say *the Mac reports no books
    /// yet* over a library of thousands — the exact lie slice 3b fixed for the
    /// filters, one scope further out.
    case shelfIsEmpty(String)
    /// The library has books and this term matched none of them. Carries the
    /// trimmed term, which is what the sentence names.
    case noMatches(String)
    /// The library has books, no term was asked for, and the filters excluded all
    /// of them. Carries how many values are on, which is what the sentence and the
    /// clear control both name.
    case noFilterMatches(Int)

    /// `nil` when there is something to show. Two things arrive as arguments
    /// rather than as assumptions, so the answer is true for **every** input: the
    /// emptiness (a caller cannot ask this of a grid with books in it and be handed
    /// a screen it has not earned) and the query itself — whose `term` is already
    /// the trimmed one, so the rule for "is this a search at all" stays in exactly
    /// one place rather than being re-stated here.
    ///
    /// A **term outranks a filter** when both are on and nothing matched: the term
    /// is the narrower question and the one the sentence can quote, and the
    /// screen's clear control undoes both in one press rather than offering to
    /// clear half of the cause.
    static func of(_ query: LibraryQuery, isEmpty: Bool) -> LibraryEmptyState? {
        guard isEmpty else { return nil }
        if let term = query.term { return .noMatches(term) }
        let filters = query.filters.selectedCount
        if filters > 0 { return .noFilterMatches(filters) }
        // The scope is the outermost narrowing, so it is asked last: a term or a
        // filter inside a shelf is still the narrower question, and only an
        // otherwise-unexplained empty grid is the shelf's own emptiness.
        if let shelf = query.shelf { return .shelfIsEmpty(shelf.name) }
        return .libraryIsEmpty
    }
}
