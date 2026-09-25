import CoreGraphics

/// The reader's two gesture rules, kept pure so a test can reach them without a
/// view. Readium hands us taps that are not on a link (`didTapAt`); SwiftUI hands
/// us the drag.
enum ReaderGestures {
    enum Zone: Equatable {
        case previous
        case toggle
        case next
    }

    /// Thirds of the page's width (RP8). A boundary is the middle's, and a view
    /// with no width yet toggles rather than turning a page.
    static func zone(x: CGFloat, width: CGFloat) -> Zone {
        guard width > 0 else { return .toggle }
        let third = width / 3
        if x < third { return .previous }
        if x > width - third { return .next }
        return .toggle
    }

    /// How far down a drag must travel to close the book (RP2).
    static let closeTravel: CGFloat = 80
    /// The strip at the top the system keeps for Notification Center.
    static let systemEdge: CGFloat = 44

    /// A predominantly vertical, downward drag of at least `closeTravel`, not
    /// started in the system's edge.
    static func closes(startY: CGFloat, dx: CGFloat, dy: CGFloat) -> Bool {
        startY >= systemEdge && dy >= closeTravel && dy > 2 * abs(dx)
    }
}
