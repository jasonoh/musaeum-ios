import Foundation

/// Which fraction the reader opens at.
///
/// Two positions can exist for one book and neither is authoritative: the Mac's
/// `reading.percent` (which is what travels, per the workstream's D5) and the
/// phone's own last position. **The reader opens at whichever is further along.**
///
/// Why not the phone's own, always: a Mac that read further than the phone would
/// be ignored, and carrying where you got to across machines is the entire point
/// of the workstream. Why not the Mac's, always: a phone whose report has not
/// been sent yet would jump backwards on every open. Why no clock comparison:
/// the two machines' clocks are the residual the Mac-side design already records
/// (D6), the *write* direction needs it because a regression there drags the
/// library backwards, and here a regression would only lose the reader's own page.
enum InitialFraction {
    /// `nil` when neither side knows anything, which means "open at the start" —
    /// and is not the same as `0`, which is a position.
    static func initial(local: Double?, server: Double?) -> Double? {
        let clamped = [local, server].compactMap { $0?.clampedToUnit() }
        return clamped.max()
    }
}

extension Double {
    /// A fraction, bounded. The contract promises `0…1`; a client that trusts it
    /// blindly hands `goToFraction(1.4)` to an engine.
    func clampedToUnit() -> Double { Swift.min(Swift.max(self, 0), 1) }
}
