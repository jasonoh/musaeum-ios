import ReadiumShared
import XCTest

@testable import Musaeum

final class ReaderTocEntryTests: XCTestCase {
    private let toc = [
        Link(href: "OEBPS/c01.htm", title: "One"),
        Link(
            href: "OEBPS/c02.htm", title: "Two",
            children: [
                Link(href: "OEBPS/c02.htm#a", title: "Two A"),
                Link(href: "OEBPS/c03.htm", title: "Two B"),
            ]
        ),
        Link(href: "OEBPS/c04.htm", title: "  "),
    ]

    func testFlatteningKeepsReadingOrderAndDepth() {
        let entries = ReaderTocEntry.flatten(toc)
        XCTAssertEqual(entries.map(\.title), ["One", "Two", "Two A", "Two B", "Untitled"])
        XCTAssertEqual(entries.map(\.depth), [0, 0, 1, 1, 0])
        XCTAssertEqual(entries.map(\.id), [0, 1, 2, 3, 4])
    }

    func testAFragmentIsNotPartOfTheResource() {
        XCTAssertEqual(ReaderTocEntry.resource("OEBPS/c02.htm#a"), "OEBPS/c02.htm")
    }

    func testALeadingSlashIsNotPartOfTheResource() {
        XCTAssertEqual(ReaderTocEntry.resource("/OEBPS/c02.htm"), "OEBPS/c02.htm")
    }

    /// The first match in reading order — the chapter, not its subsection.
    func testTheCurrentEntryIsTheFirstForItsResource() {
        let entries = ReaderTocEntry.flatten(toc)
        XCTAssertEqual(ReaderTocEntry.current(href: "OEBPS/c02.htm", in: entries)?.title, "Two")
        XCTAssertEqual(ReaderTocEntry.current(href: "/OEBPS/c03.htm#x", in: entries)?.title, "Two B")
    }

    func testAnUnlistedResourceHasNoEntry() {
        let entries = ReaderTocEntry.flatten(toc)
        XCTAssertNil(ReaderTocEntry.current(href: "OEBPS/notes.htm", in: entries))
        XCTAssertNil(ReaderTocEntry.current(href: nil, in: entries))
    }
}
