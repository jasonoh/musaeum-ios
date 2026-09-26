import XCTest

@testable import Musaeum

/// The library header's rule: **the list's direction decides, and the header's own
/// band is the floor.**
///
/// The rule is decided here because it is a pure function of one reading. The two
/// things it cannot decide are the frame that goes with it
/// (`docs/evidence/header-recede/`): that the bar *slides* rather than jumps, and
/// that nothing blank appears behind it.
///
/// **Every position below is past the band unless the case is about the band.** A case
/// that starts inside the floor is answered by the floor rather than by the travel it
/// names, and reads green while deciding nothing.
final class HeaderRevealTests: XCTestCase {
    /// The band the app measures on the probe profile in portrait — 219 pt: a 62 pt
    /// status bar, the header's own measured 180 pt, and the 39 pt downloaded strip.
    /// It is the number the app prints for itself, `library list band=219 header=180
    /// viewport=621 content=1279`, rather than one chosen here: the floor is a real
    /// measurement or the cases below are deciding arithmetic nobody runs.
    private let band: CGFloat = 219

    /// Feeds a run of positions, in the order a finger would produce them, with each
    /// reading's delta taken from the one before it — the shape the screen feeds the
    /// rule (`onScrollGeometryChange`'s old and new, one reading per frame).
    @discardableResult
    private func feed(
        _ positions: [CGFloat],
        into reveal: inout HeaderReveal,
        from start: CGFloat? = nil,
        band: CGFloat? = nil
    ) -> Bool {
        var previous = start ?? positions.first ?? 0
        var verdict = reveal.hidden
        for position in positions {
            verdict = reveal.update(progress: position, delta: position - previous, band: band ?? self.band)
            previous = position
        }
        return verdict
    }

    /// A push that never reaches the travel: the header stays where it was, which is
    /// the case that keeps a slow drag from moving the bar at all.
    func testAPushUnderTheTravelLeavesTheHeaderIn() {
        var reveal = HeaderReveal()
        let verdict = feed([240, 262, 276], into: &reveal)
        XCTAssertFalse(verdict, "36 pt of travel: the bar has not been asked to move")
    }

    /// The same push carried past it: the header goes.
    func testAPushPastTheTravelSendsTheHeaderAway() {
        var reveal = HeaderReveal()
        let verdict = feed([240, 275, 310], into: &reveal)
        XCTAssertTrue(verdict)
    }

    /// **The floor.** 160 pt of push with the travel well and truly earned, and the
    /// header still cannot leave: the list has not gone by the band, so the space
    /// behind the header is the list's own top margin rather than content — a bar that
    /// left here would slide away to reveal the background.
    func testTheHeaderCannotLeaveBeforeItsOwnBandHasGoneBy() {
        var reveal = HeaderReveal()
        let verdict = feed([100, 160], into: &reveal, from: 0)
        XCTAssertFalse(verdict, "160 pt of 219: the travel is spent, and the band is not")
    }

    /// One point past the band, with the same travel: it goes.
    func testOnePointPastTheBandIsEnough() {
        var reveal = HeaderReveal()
        let verdict = feed([220], into: &reveal, from: 0)
        XCTAssertTrue(verdict)
    }

    /// The half of the gesture that makes it Safari's: a pull of the same size brings
    /// it back with the list still scrolled well past the band.
    func testAPullOfTheSameSizeBringsItBack() {
        var reveal = HeaderReveal()
        feed([240, 320], into: &reveal)
        XCTAssertTrue(reveal.hidden)
        let verdict = feed([270], into: &reveal, from: 320)
        XCTAssertFalse(verdict, "−50 pt with the list still 270 pt in is a pull, not a return to the top")
    }

    /// A change of mind starts a new run, **including its size**: +40, −10, +40, −10 is
    /// two 40 pt pushes with a blip between them, not one 70 pt push, so the header
    /// still has not been asked to move. (Alternating runs of *equal* size would pass
    /// with or without the reset — they cancel — so this case is written with the
    /// unequal pair that can only pass one way.)
    func testAChangeOfMindDiscardsTheRunItInterrupted() {
        var reveal = HeaderReveal()
        let verdict = feed([240, 280, 270, 310, 300], into: &reveal)
        XCTAssertFalse(verdict, "the run is 40 pt at its longest, and the travel is 44")
    }

    /// A finger that is nearly still — alternating single points — never moves the bar,
    /// which is what the travel is for.
    func testJitterNeverMovesTheHeader() {
        var reveal = HeaderReveal()
        let positions: [CGFloat] = (0..<40).map { 300 + CGFloat($0 % 2) * 3 - 3 }
        let verdict = feed(positions, into: &reveal, from: 300)
        XCTAssertFalse(verdict)
    }

    /// Pull-to-refresh: the list goes past its own start, the header is in — whatever
    /// came before the pull — and the push that follows has to earn its own travel
    /// rather than spending the pull's.
    func testAPullAtTheTopNeverHidesTheHeader() {
        var reveal = HeaderReveal()
        feed([240, 320], into: &reveal)
        XCTAssertTrue(reveal.hidden)
        let pulled = feed([240, 60, -50], into: &reveal)
        XCTAssertFalse(pulled)
        let afterThePull = feed([-50, 60, 130], into: &reveal)
        XCTAssertFalse(afterThePull, "130 pt of progress is still inside the 219 pt band")
    }

    /// An unmeasured band hides nothing: before layout has reported it the rule has no
    /// floor, and a rule with no floor must not act.
    func testAnUnmeasuredBandHidesNothing() {
        var reveal = HeaderReveal()
        let verdict = feed([400], into: &reveal, from: 0, band: 0)
        XCTAssertFalse(verdict)
    }

    /// A jump into the middle of the list — the probe's own seam, and the same path a
    /// scroll-to-top takes in reverse — leaves the header out; a jump back to the start
    /// brings it in, which is also what a new search does to the list.
    func testAJumpIntoTheListHidesItAndAJumpBackShowsIt() {
        var reveal = HeaderReveal()
        let jumped = feed([900], into: &reveal, from: 0)
        XCTAssertTrue(jumped)
        let back = feed([0], into: &reveal, from: 900)
        XCTAssertFalse(back)
    }

    /// **The delta is the travel, not the position.** The screen hands the box one
    /// reading per frame and the box takes the difference; a box that passed the
    /// position on as the travel would answer every frame as though the reader had
    /// dragged the whole list again, and the header would never come back.
    @MainActor
    func testTheBoxTakesItsDeltaFromTheLastReading() {
        let box = HeaderRevealBox()
        XCTAssertTrue(box.feed(progress: 500, band: band), "a jump into the list")
        XCTAssertTrue(box.feed(progress: 520, band: band), "+20 pt: not yet")
        XCTAssertTrue(box.feed(progress: 480, band: band), "−40 pt: a change of mind, 40 short of the travel")
        XCTAssertFalse(box.feed(progress: 440, band: band), "−40 pt more: the header comes back, 440 pt in")
    }
}
