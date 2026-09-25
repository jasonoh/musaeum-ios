import UIKit

/// Where Readium may set text (final review, Important 1). Readium's own rule is
/// the window's safe area, raised to its configured 34 pt (compact height) or
/// 62 pt (regular); the hidden footer sits *above* the safe area, so at a
/// landscape 34, or a larger Dynamic Type caption, a full page printed its last
/// line under the percentage. This keeps Readium's floor and reserves the
/// footer's own height on top of the safe area.
enum ReaderInsets {
    /// The footer's distance above the safe area — `ReaderChrome` draws with it.
    static let footerPadding: CGFloat = 4
    /// Air between the last text line and the footer.
    static let footerGap: CGFloat = 8

    static func content(safeArea: UIEdgeInsets, compactHeight: Bool, footerLine: CGFloat) -> UIEdgeInsets {
        let floor: CGFloat = compactHeight ? 34 : 62
        let footer = safeArea.bottom + footerPadding + footerLine + footerGap
        return UIEdgeInsets(
            top: max(safeArea.top, floor),
            left: safeArea.left,
            bottom: max(footer, floor),
            right: safeArea.right
        )
    }
}
