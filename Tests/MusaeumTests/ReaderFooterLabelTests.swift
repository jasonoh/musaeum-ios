import ReadiumShared
import XCTest

@testable import Musaeum

final class ReaderFooterLabelTests: XCTestCase {
    private let toc = ReaderTocEntry.flatten([Link(href: "c01.htm", title: "Why Revolution Is Impossible Today")])

    func testThePercentIsRoundedToAWholeNumber() {
        XCTAssertEqual(ReaderFooterLabel.percent(0.164), "16%")
        XCTAssertEqual(ReaderFooterLabel.percent(0.165), "17%")
    }

    /// CD5: before the engine says where it is, the footer says nothing — not 0%.
    func testNoProgressionIsNoPercent() {
        XCTAssertNil(ReaderFooterLabel.percent(nil))
    }

    func testAnOutOfRangeProgressionIsClamped() {
        XCTAssertEqual(ReaderFooterLabel.percent(1.2), "100%")
        XCTAssertEqual(ReaderFooterLabel.percent(-0.1), "0%")
    }

    func testTheLocatorsOwnTitleWins() {
        XCTAssertEqual(ReaderFooterLabel.chapter(locatorTitle: "Chapter 4", href: "c01.htm", toc: toc), "Chapter 4")
    }

    func testTheContentsSupplyAMissingTitle() {
        XCTAssertEqual(
            ReaderFooterLabel.chapter(locatorTitle: nil, href: "c01.htm", toc: toc),
            "Why Revolution Is Impossible Today"
        )
        XCTAssertEqual(
            ReaderFooterLabel.chapter(locatorTitle: "  ", href: "c01.htm", toc: toc),
            "Why Revolution Is Impossible Today"
        )
    }

    func testNeitherIsNoChapter() {
        XCTAssertNil(ReaderFooterLabel.chapter(locatorTitle: nil, href: "notes.htm", toc: toc))
    }
}
