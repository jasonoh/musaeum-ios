import XCTest

@testable import Musaeum

/// Where a tap on the page lands, and which drag closes the book (RP8, RP2).
final class ReaderGesturesTests: XCTestCase {
    func testTheLeftThirdTurnsBack() {
        XCTAssertEqual(ReaderGestures.zone(x: 10, width: 300), .previous)
    }

    func testTheMiddleThirdTogglesTheChrome() {
        XCTAssertEqual(ReaderGestures.zone(x: 150, width: 300), .toggle)
    }

    func testTheRightThirdTurnsForward() {
        XCTAssertEqual(ReaderGestures.zone(x: 290, width: 300), .next)
    }

    /// A boundary belongs to the middle: a tap that could go either way shows the
    /// chrome rather than losing the reader's page.
    func testBothBoundariesToggle() {
        XCTAssertEqual(ReaderGestures.zone(x: 100, width: 300), .toggle)
        XCTAssertEqual(ReaderGestures.zone(x: 200, width: 300), .toggle)
    }

    /// Mid-layout the view can report no width; nothing turns.
    func testAZeroWidthViewToggles() {
        XCTAssertEqual(ReaderGestures.zone(x: 0, width: 0), .toggle)
    }

    func testALongDownwardDragCloses() {
        XCTAssertTrue(ReaderGestures.closes(startY: 200, dx: 10, dy: 120))
    }

    func testAShortDragDoesNotClose() {
        XCTAssertFalse(ReaderGestures.closes(startY: 200, dx: 0, dy: 79))
    }

    func testADiagonalDragDoesNotClose() {
        XCTAssertFalse(ReaderGestures.closes(startY: 200, dx: 70, dy: 120))
    }

    func testAnUpwardDragDoesNotClose() {
        XCTAssertFalse(ReaderGestures.closes(startY: 400, dx: 0, dy: -200))
    }

    /// The top 44 pt belong to Notification Center.
    func testADragFromTheSystemEdgeDoesNotClose() {
        XCTAssertFalse(ReaderGestures.closes(startY: 20, dx: 0, dy: 200))
    }
}
