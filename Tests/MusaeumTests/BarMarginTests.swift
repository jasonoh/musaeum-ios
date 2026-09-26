import XCTest

@testable import Musaeum

/// The library rows' side margin follows the bar's, not the safe area's: the
/// measurements are `BarMargin`'s own; these cases hold the rule to them.
final class BarMarginTests: XCTestCase {
    /// Portrait: no side inset, and the rows keep the 16 pt they always had.
    func testNoSideInsetKeepsTheBase() {
        XCTAssertEqual(BarMargin.from(safeInset: 0), 16)
    }

    /// Landscape on iPhone 17 Pro: a 62 pt safe area, and the bar measured 38–40 pt in.
    func testLandscapeSafeAreaLandsOnTheBar() {
        XCTAssertEqual(BarMargin.from(safeInset: 62), 38)
    }

    /// A small inset never brings the rows closer to the edge than portrait does.
    func testSmallInsetNeverGoesBelowTheBase() {
        XCTAssertEqual(BarMargin.from(safeInset: 20), 16)
    }
}
