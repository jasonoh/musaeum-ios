import Foundation

/// **What this client decides about a shelf before any view draws it** — whether
/// the open scope is a queue, what order it opens in, and whether a book may be
/// moved in it. Pure rules, in their own file, so a case reaches them without a
/// screen (the repo's own convention: a rule a view would otherwise own is a rule
/// no test can hold).
///
/// `kind` is the wire's plain string on purpose (`ContractModels.swift` — an enum
/// there would refuse a kind the contract could legitimately grow), so the one
/// place that *branches* on it is here. The contract names two kinds this build
/// answers — `manual` and `queue` — and anything else is treated as a manual
/// shelf, which is what a client written before a third kind would do anyway.
enum ShelfScope {
    /// A shelf whose book order is the reader's own: index 0 is the top. Takes the
    /// optional scope directly, because every caller here has one — *no shelf open*
    /// is not a queue, and that is the answer rather than a crash.
    static func isQueue(_ shelf: Shelf?) -> Bool {
        shelf?.kind == "queue"
    }

    /// **The sort a shelf opens in — or `nil`, which means "send none".**
    ///
    /// A manual shelf keeps the Mac's own default sent explicitly (`shelf_added
    /// desc`, the *Date Added to Shelf* order slice 7a mirrored). A queue's order
    /// is its content, and the contract's default for a queue *is* that order
    /// (`shelf_position` ascending) — so the honest encoding of "the queue's own
    /// order" is the absence of a `sort`, and nothing this client sends can get it
    /// wrong or persist it. `nil` is reachable only here; every other path through
    /// `LibraryQuery.sort` carries a value.
    static func openingSort(for shelf: Shelf) -> LibrarySort? {
        isQueue(shelf) ? nil : LibrarySort(field: .shelfAdded, direction: .desc)
    }

    /// **Whether a book in this scope may be moved to an end** — the thing that
    /// decides if the card's context menu exists at all.
    ///
    /// Two facts, in this order: the scope is a queue, and the Mac has not
    /// answered `404` to a move. The 404 is the contract's own reading for a Mac
    /// that lacks the route (the same reading a pre-shelves Mac's 404 already gets),
    /// and it is why the menu is **absent** rather than disabled there.
    static func offersMove(in shelf: Shelf?, route: QueueMoveRoute) -> Bool {
        guard isQueue(shelf) else { return false }
        return route != .unavailable
    }
}

/// What this session has learned about the Mac's place route
/// (`PUT /api/shelves/{id}/books/{bookId}/position`).
///
/// Three states for the reason `shelvesSupported` has three: **unknown is not
/// absent**. A run that has not moved anything has learned nothing, and a Mac that
/// has not answered is not a Mac without the route — only a `404` on the route
/// itself says that, and only that withdraws the menu.
enum QueueMoveRoute: Equatable, Sendable {
    case unknown
    case available
    case unavailable
}

/// Which end of a queue a move names. The wire carries exactly these two values
/// and no third place: `{"to":"top"}` or `{"to":"bottom"}` — the contract refuses
/// a `before`/`after` anchor by design, and the phone's two rows are top and end.
enum ShelfMoveEdge: String, Sendable {
    case top
    case bottom
}
