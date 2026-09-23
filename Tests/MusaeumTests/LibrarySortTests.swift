import XCTest

@testable import Musaeum

/// The library's narrowing rules, decided with no screen anywhere near them:
/// which options the phone offers and how it words them, what each puts on the
/// wire, the guard on a stored preference, whether a term is a search at all, and
/// which of the two "nothing to show" screens applies.
///
/// Nothing here touches a stub — every rule is pure — so the interesting half of
/// this slice's decisions (what a *request* carries, and what a superseded answer
/// does) lives in `LibraryQueryTests`, where a model is actually driven.
@MainActor
final class LibrarySortTests: XCTestCase {

    // MARK: The options (3.1)

    /// The Mac's own eight shortcuts, in its own order, with its own words. Read
    /// off `Toolbar.tsx`'s `SORT_OPTIONS` and `book.types.ts`'s `SORT_LABELS`: a
    /// phone sort and a Mac sort that named one order two ways would be two names
    /// for one question.
    func testThePhoneOffersTheMacsOwnEightOptionsInItsOwnOrder() {
        XCTAssertEqual(LibrarySort.options.map(\.storedKey), [
            "title:asc",
            "title:desc",
            "author:asc",
            "series:asc",
            "date_added:desc",
            "date_added:asc",
            "rating:desc",
            "read_status:asc",
        ])
        XCTAssertEqual(LibrarySort.options.map(\.label), [
            "Title A–Z",
            "Title Z–A",
            "Author A–Z",
            "Series",
            "Recently Added",
            "Oldest First",
            "Highest Rated",
            "Read Status",
        ])
        XCTAssertEqual(LibrarySort.default, LibrarySort(field: .title, direction: .asc))
        XCTAssertEqual(LibrarySort.options.first, LibrarySort.default, "the menu opens on the order the library opens in")
    }

    /// The other half of 3.1: a *restored* preference may name any of the twelve
    /// pairs the labels cover, not only the eight the menu offers. Author Z–A is a
    /// sort the Mac's list header can produce, so the phone can hold one — and a
    /// label that fell back to the field's name for it would be this file
    /// inventing less than the Mac has.
    func testEveryPairHasTheMacsOwnWording() {
        XCTAssertEqual(LibrarySort(field: .author, direction: .desc).label, "Author Z–A")
        XCTAssertEqual(LibrarySort(field: .series, direction: .desc).label, "Series (reversed)")
        XCTAssertEqual(LibrarySort(field: .rating, direction: .asc).label, "Lowest Rated")
        XCTAssertEqual(LibrarySort(field: .readStatus, direction: .desc).label, "Read Status (reversed)")
        XCTAssertEqual(LibrarySort(field: .dateAdded, direction: .asc).label, "Oldest First")
    }

    /// **3.2 — every option is a request the contract accepts.** The contract
    /// refuses an unknown `sort` or `dir` with a **400** rather than defaulting it
    /// ("a client that asked for `sort=athor` and silently received title order
    /// could never learn it had a typo"), so a value invented here would surface to
    /// a reader as a library that looks broken rather than as one in the wrong
    /// order. This case is what holds the menu and the contract's own six values
    /// together.
    func testEveryOptionIsAValueTheContractAccepts() {
        let contractFields = ["title", "author", "series", "date_added", "rating", "read_status"]
        XCTAssertEqual(Set(LibrarySort.Field.allCases.map(\.rawValue)), Set(contractFields), "the enum and the contract's six fields are one list")

        let everyPair = LibrarySort.Field.allCases.flatMap { field in
            LibrarySort.Direction.allCases.map { LibrarySort(field: field, direction: $0) }
        }
        XCTAssertEqual(everyPair.count, 12)
        for pair in everyPair {
            XCTAssertTrue(contractFields.contains(pair.wireField), "\(pair.storedKey) names a field the contract does not")
            XCTAssertTrue(["asc", "desc"].contains(pair.wireDirection), "\(pair.storedKey) names a direction the contract does not")
            XCTAssertFalse(pair.label.isEmpty)
        }
        for option in LibrarySort.options {
            XCTAssertTrue(everyPair.contains(option), "\(option.storedKey) is offered but is not a pair the contract accepts")
        }
    }

    // MARK: The stored preference (3.7, 3.8)

    /// **3.8 — the guard.** Storage is only as trustworthy as the build that wrote
    /// it, and the contract makes an unguarded value expensive rather than untidy.
    func testAStoredSortThisBuildDoesNotKnowFallsBackToTheDefault() {
        XCTAssertEqual(LibrarySort.stored(nil), .default)
        XCTAssertEqual(LibrarySort.stored(""), .default)
        XCTAssertEqual(LibrarySort.stored("athor:desc"), .default, "a field no build ever had")
        XCTAssertEqual(LibrarySort.stored("title"), .default, "a value with no direction")
        XCTAssertEqual(LibrarySort.stored("title:descending"), .default, "a direction the contract does not take")
        XCTAssertEqual(LibrarySort.stored("title:desc:extra"), .default)
        XCTAssertEqual(LibrarySort.stored(":asc"), .default)

        // …and every value the build *does* know survives the round trip, the
        // eight the menu offers included.
        for option in LibrarySort.options {
            XCTAssertEqual(LibrarySort.stored(option.storedKey), option)
        }
        XCTAssertEqual(LibrarySort.stored("author:desc"), LibrarySort(field: .author, direction: .desc))
        XCTAssertEqual(LibrarySort.stored("read_status:desc"), LibrarySort(field: .readStatus, direction: .desc))
    }

    /// **3.7 — the chosen sort survives a relaunch**, at the store's own boundary.
    /// A second store over the same defaults is what a relaunch looks like, which
    /// is the shape `StoreTests` already uses for the download index.
    func testTheChosenSortSurvivesARelaunch() {
        let defaults = UserDefaults(suiteName: "musaeum-tests-\(UUID().uuidString)")!
        let keychain = KeychainStore(service: "dev.jasonoh.Musaeum.tests")
        let settings = SettingsStore(defaults: defaults, keychain: keychain)
        XCTAssertEqual(settings.librarySort, .default, "a fresh install opens in title order")

        settings.save(librarySort: LibrarySort(field: .dateAdded, direction: .desc))

        let reopened = SettingsStore(defaults: defaults, keychain: keychain)
        XCTAssertEqual(reopened.librarySort, LibrarySort(field: .dateAdded, direction: .desc))

        // A credential clear is not a preference clear: which order you like your
        // library in is not a secret.
        reopened.clear()
        XCTAssertEqual(SettingsStore(defaults: defaults, keychain: keychain).librarySort, LibrarySort(field: .dateAdded, direction: .desc))
    }

    // MARK: Whether a term is a search at all (3.4)

    /// **A query of nothing but spaces is not a search.** The Mac trims before it
    /// judges, and the contract refuses a malformed *parameter* with a 400 — so a
    /// client that sent bare whitespace would be composing a question nothing can
    /// answer.
    func testAQueryOfNothingButSpacesIsNotASearch() {
        XCTAssertNil(LibraryQuery(text: "").term)
        XCTAssertNil(LibraryQuery(text: "   ").term)
        XCTAssertNil(LibraryQuery(text: "\n\t ").term)
        XCTAssertFalse(LibraryQuery(text: "  ").isSearching)

        XCTAssertEqual(LibraryQuery(text: "  dune  ").term, "dune", "the term that travels is the trimmed one")
        XCTAssertTrue(LibraryQuery(text: "dune").isSearching)
    }

    /// The sort stays live while searching: one state, not two, which is what
    /// makes the same query return the same order on both machines.
    func testASearchKeepsItsSort() {
        let query = LibraryQuery(sort: LibrarySort(field: .author, direction: .desc), text: "dune")
        XCTAssertEqual(query.sort.wireField, "author")
        XCTAssertEqual(query.sort.wireDirection, "desc")
        XCTAssertEqual(query.term, "dune")
        XCTAssertTrue(query.isSearching)
    }

    // MARK: Nothing to show

    /// Which "nothing to show" screen applies — and specifically that the answer is
    /// **total**: it says `nil` when there is something to show, so it cannot hand
    /// a caller a "nothing matches" screen over a grid that has books in it.
    func testTheEmptyStateDistinguishesAnEmptyLibraryFromNoMatches() {
        XCTAssertNil(LibraryEmptyState.of(LibraryQuery(text: ""), isEmpty: false))
        XCTAssertNil(LibraryEmptyState.of(LibraryQuery(text: "dune"), isEmpty: false))

        XCTAssertEqual(LibraryEmptyState.of(LibraryQuery(text: ""), isEmpty: true), .libraryIsEmpty)
        XCTAssertEqual(
            LibraryEmptyState.of(LibraryQuery(text: "  dune  "), isEmpty: true),
            .noMatches("dune"),
            "the sentence names the term that travelled, not the field's raw text"
        )
        XCTAssertEqual(
            LibraryEmptyState.of(LibraryQuery(text: "   "), isEmpty: true),
            .libraryIsEmpty,
            "whitespace is not a search, empty or not"
        )
    }
}
