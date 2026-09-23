import XCTest

@testable import Musaeum

/// The rule that decides where the reader opens, decided in both directions —
/// this is the one piece of the cross-device claim a unit case *can* carry.
final class InitialFractionTests: XCTestCase {
    func testThePhoneKeepsItsPlaceWhenTheMacIsBehind() {
        XCTAssertEqual(InitialFraction.initial(local: 0.70, server: 0.42), 0.70)
    }

    func testTheMacIsHonouredWhenItReadFurther() {
        XCTAssertEqual(InitialFraction.initial(local: 0.70, server: 0.80), 0.80)
    }

    func testTheMacsFractionIsUsedWhenThePhoneHasNeverOpenedIt() {
        XCTAssertEqual(InitialFraction.initial(local: nil, server: 0.42), 0.42)
    }

    func testThePhonesOwnPositionIsUsedWhenTheMacHasNoIdea() {
        XCTAssertEqual(InitialFraction.initial(local: 0.61, server: nil), 0.61)
    }

    /// Nothing known on either side is not 0 — it is "open at the start", and the
    /// engine is handed no locator at all.
    func testNeitherSideKnowingIsNotAPosition() {
        XCTAssertNil(InitialFraction.initial(local: nil, server: nil))
    }

    /// A fraction the contract promises is 0…1; a client that trusts a number it
    /// did not check hands the engine whatever arrived.
    func testAFractionOutsideTheUnitIntervalIsClamped() {
        XCTAssertEqual(InitialFraction.initial(local: 1.4, server: nil), 1.0)
        XCTAssertEqual(InitialFraction.initial(local: -0.2, server: nil), 0.0)
        XCTAssertEqual(InitialFraction.initial(local: nil, server: 1.9), 1.0)
    }

    /// 0% is a position, not an absence: a book the Mac reported at 0 and the
    /// phone has never opened must still open at 0 rather than at "no locator".
    func testZeroIsAPosition() {
        XCTAssertEqual(InitialFraction.initial(local: nil, server: 0), 0)
    }
}
