import CoreGraphics

/// When the library's chrome gives way, and when it comes back.
///
/// **A travel rule, not a position rule.** Which way the list is moving decides,
/// and how far it has moved that way — not where it is. A reader who flicks the
/// grid away and then pulls back twenty points wants the chrome back, and no rule
/// keyed on position can say that; Safari's own chrome behaves the same way, which
/// is the behaviour the owner asked for. The two distances below exist because a
/// finger jitters: a rule that answered every reading would flicker the bar on a
/// drag that is nearly still.
///
/// **The chrome cannot leave before the band above the list has gone by.** Until
/// the list has scrolled past `band`, the space the chrome would vacate is not
/// content yet — the list's own top margin sits there — so a chrome that left
/// that early would slide away to reveal the background. `band` is the whole
/// chrome's height, **measured by the layout** rather than computed: three of the
/// header's four paddings move with the vertical size class and the strips
/// beneath it come and go, so a constant here would be a second copy of the
/// layout waiting to drift from it. The app prints its own reading at launch
/// (`library list band=… header=… viewport=… content=…`).
///
/// The rule is a pure function of one reading so a case can decide it without a
/// screen. What no case here can decide is the animation, or whether the bar reads
/// as receding rather than as being yanked — that is a frame's judgement.
struct HeaderReveal: Equatable {
    /// How far the list must travel one way before the header moves.
    ///
    /// UIKit's own `hidesBarsOnSwipe` decides the same thing from a pan's
    /// translation with a threshold of this order, and the number matters more at
    /// the low end than the high: too small and a bar flickers while a finger
    /// rests, too large and the header feels stuck to the top of the screen.
    static let travel: CGFloat = 44

    /// Whether the header is out of the way.
    private(set) var hidden = false

    /// The current run of travel, signed: positive is the list moving up (the
    /// reader pushing it away), negative is the list coming back down.
    private var run: CGFloat = 0

    /// Feeds one scroll reading and answers whether the header should be out.
    ///
    /// - `progress`: how far the list has scrolled past its own start — 0 at rest,
    ///   negative while a pull-to-refresh is being dragged.
    /// - `delta`: the movement since the previous reading.
    /// - `band`: the header's own band, `HeaderReveal`'s reason above.
    mutating func update(progress: CGFloat, delta: CGFloat, band: CGFloat) -> Bool {
        // Nothing measured yet, or the list has not yet gone by the header's own
        // band: the header is in, and a pull at the top is a refresh — the one
        // gesture that must never be answered by hiding what is being pulled.
        guard band > 0, progress >= band else {
            run = 0
            hidden = false
            return hidden
        }
        guard delta != 0 else { return hidden }
        // A change of mind starts a new run: a reader who pushes 40 pt down and
        // then 40 pt back has asked for the header, not for nothing.
        if (delta > 0) != (run > 0) { run = 0 }
        run += delta
        if run >= Self.travel {
            hidden = true
            run = 0
        } else if run <= -Self.travel {
            hidden = false
            run = 0
        }
        return hidden
    }
}

/// `HeaderReveal`'s own state, held **outside SwiftUI's invalidation path**.
///
/// The rule is fed one reading per scroll frame, and a `@State` write per frame
/// would re-evaluate the library screen's body for every point of travel. A
/// reference in `@State` cannot do that — mutating the box does not touch the
/// `State` storage — so only the rule's verdict is `@State`, and that changes
/// twice per gesture rather than sixty times a second.
@MainActor
final class HeaderRevealBox {
    private var reveal = HeaderReveal()

    /// The list's own last position, which the delta the rule needs is taken from.
    private(set) var progress: CGFloat = 0

    /// Feeds one reading and answers whether the chrome should be out.
    @discardableResult
    func feed(progress: CGFloat, band: CGFloat) -> Bool {
        let delta = progress - self.progress
        self.progress = progress
        return reveal.update(progress: progress, delta: delta, band: band)
    }
}
