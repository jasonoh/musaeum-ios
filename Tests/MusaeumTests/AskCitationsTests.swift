import ReadiumShared
import XCTest

@testable import Musaeum

final class AskCitationsTests: XCTestCase {
    private func entry(_ id: Int, _ title: String) -> ReaderTocEntry {
        ReaderTocEntry(id: id, title: title, depth: 0, link: Link(href: "ch\(id).xhtml"))
    }

    private lazy var toc = [
        entry(0, "Introduction"), entry(1, "The Ledger of Small Debts"), entry(2, "Untitled"), entry(3, "Ch"),
    ]

    func testAnAnswerThatNamesASectionOffersItCaseInsensitively() {
        let found = AskCitations.entries(in: "See “the ledger of small debts” for the origin.", toc: toc)
        XCTAssertEqual(found.map(\.id), [1])
    }

    func testAnAnswerThatNamesNoSectionOffersNothing() {
        XCTAssertEqual(AskCitations.entries(in: "It is about frugality.", toc: toc).map(\.id), [])
    }

    func testUntitledAndVeryShortTitlesNeverMatch() {
        XCTAssertEqual(AskCitations.entries(in: "untitled ch ch ch", toc: toc).map(\.id), [])
    }

    func testDiacriticsAndRepeatedTitlesAreNormalised() {
        let toc = [entry(0, "Café Society"), entry(1, "Café Society")]
        XCTAssertEqual(AskCitations.entries(in: "As in cafe society, the point is…", toc: toc).map(\.id), [0])
    }

    func testTheListIsCapped() {
        let toc = (0..<6).map { entry($0, "Chapter number \($0)") }
        let answer = (0..<6).map { "Chapter number \($0)" }.joined(separator: ", ")
        XCTAssertEqual(AskCitations.entries(in: answer, toc: toc, limit: 3).count, 3)
    }
}
