/// How the library's wordmark is finished. The letterforms are the Mac's —
/// Iowan Old Style caps, tracked 0.18 em, in the gold (`src/components/layout/Sidebar.tsx`)
/// — and the style is only the surface they are struck on.
///
/// `embossed` is the pick; the others stay while the owner compares them on the
/// device (a DEBUG long-press on the wordmark cycles them).
enum WordmarkStyle: CaseIterable, Sendable {
    /// Raised metal: a light top edge, a dark lip below, a gold gradient face.
    case embossed
    /// Letterpress: cut into the bar — dark above, a lit lip below.
    case engraved
    /// Stepped depth down and to the right, as if cast.
    case extruded
    /// The Mac's own wordmark, unfinished.
    case flat

    /// The next style in declaration order, wrapping.
    var next: WordmarkStyle {
        let all = Self.allCases
        let index = all.firstIndex(of: self)!
        return all[(index + 1) % all.count]
    }
}
