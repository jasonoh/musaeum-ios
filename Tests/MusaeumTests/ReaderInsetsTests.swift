import UIKit
import XCTest

@testable import Musaeum

/// The page's insets reserve the hidden footer's own height above the safe area,
/// so no line of text sets under it (final review, Important 1).
final class ReaderInsetsTests: XCTestCase {
    private let portrait = UIEdgeInsets(top: 62, left: 0, bottom: 34, right: 0)
    private let landscape = UIEdgeInsets(top: 0, left: 62, bottom: 21, right: 62)

    /// At the default caption size this is Readium's own 62 — nothing reflows.
    func testPortraitAtTheDefaultSizeKeepsReadiumsInset() {
        let inset = ReaderInsets.content(safeArea: portrait, compactHeight: false, footerLine: 16)
        XCTAssertEqual(inset.top, 62)
        XCTAssertEqual(inset.bottom, 62)
    }

    /// Landscape: Readium's 34 is under the footer; ours clears it.
    func testLandscapeClearsTheFooter() {
        let inset = ReaderInsets.content(safeArea: landscape, compactHeight: true, footerLine: 16)
        XCTAssertEqual(inset.bottom, 21 + ReaderInsets.footerPadding + 16 + ReaderInsets.footerGap)
        XCTAssertEqual(inset.top, 34)
    }

    /// A larger Dynamic Type caption grows the reserve with it.
    func testALargerCaptionGrowsTheReserve() {
        let inset = ReaderInsets.content(safeArea: portrait, compactHeight: false, footerLine: 30)
        XCTAssertEqual(inset.bottom, 34 + ReaderInsets.footerPadding + 30 + ReaderInsets.footerGap)
    }

    func testTheSidesAreTheSafeAreas() {
        let inset = ReaderInsets.content(safeArea: landscape, compactHeight: true, footerLine: 16)
        XCTAssertEqual(inset.left, 62)
        XCTAssertEqual(inset.right, 62)
    }
}
