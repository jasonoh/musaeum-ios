import XCTest

@testable import Musaeum

/// The DEBUG long-press on the wordmark steps through every finish and comes back.
final class WordmarkStyleTests: XCTestCase {
    /// The pick leads, so the first press shows the next candidate.
    func testEmbossedStepsToEngraved() {
        XCTAssertEqual(WordmarkStyle.embossed.next, .engraved)
    }

    /// The last finish wraps to the first, so no press ever lands nowhere.
    func testCycleVisitsEveryStyleAndWraps() {
        var seen: [WordmarkStyle] = []
        var style = WordmarkStyle.embossed
        for _ in WordmarkStyle.allCases {
            seen.append(style)
            style = style.next
        }
        XCTAssertEqual(seen, WordmarkStyle.allCases)
        XCTAssertEqual(style, .embossed)
    }
}
