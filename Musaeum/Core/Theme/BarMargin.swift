import CoreGraphics

/// **The navigation bar's own side margin, which the library's header and rows
/// keep.**
///
/// The library screen draws its own bar now, but the margin is the one the
/// system's bar measured — so its edges sit where every other screen's bar does.
///
/// The bar does not draw at the content's safe area. Measured on iPhone 17 Pro /
/// iOS 26.1 (3× frames, 2026-09-25): in portrait, with no side inset, the bar's
/// trailing capsule and a row padded 16 pt both end 16.3 pt from the edge. In
/// landscape, with a 62 pt safe area each side, the bar's title starts 40 pt in and
/// its capsule ends 38.3 pt in, while a 16 pt row inside the safe area sat 78 pt in —
/// the 40 pt step the owner reported as "mismatched". So the bar comes about 24 pt
/// *into* the safe area, and never closer than the 16 pt it keeps in portrait.
///
/// This is a measurement of the system's layout, not an API: a device or an iOS
/// release that moves the bar needs a new frame and a new number here.
enum BarMargin {
    /// The margin the bar keeps when there is no side safe area.
    static let base: CGFloat = 16

    /// How far the bar reaches into a side safe area.
    static let intoSafeArea: CGFloat = 24

    /// The distance from the screen edge the bar's content keeps, for a side safe
    /// area of `safeInset`.
    static func from(safeInset: CGFloat) -> CGFloat {
        max(base, safeInset - intoSafeArea)
    }
}
