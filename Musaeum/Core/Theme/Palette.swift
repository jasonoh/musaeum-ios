import SwiftUI

/// The Mac app's palette, in the phone's hand: warm near-black surfaces, amber
/// accent, warm off-white type, serif display faces for titles. The values are
/// lifted from the Mac's own tokens (`src/index.css`'s `:root`) so the two
/// devices read as one library rather than two apps.
enum Palette {
    static let ink = Color(red: 0.078, green: 0.071, blue: 0.063)
    static let surface = Color(red: 0.118, green: 0.106, blue: 0.094)
    static let raised = Color(red: 0.165, green: 0.149, blue: 0.133)
    static let parchment = Color(red: 0.925, green: 0.906, blue: 0.871)
    static let muted = Color(red: 0.604, green: 0.569, blue: 0.514)
    static let gold = Color(red: 0.855, green: 0.667, blue: 0.318)
    static let danger = Color(red: 0.804, green: 0.427, blue: 0.345)
    static let hairline = Color.white.opacity(0.08)
}

extension Font {
    /// Serif display type, the Mac's voice for a book's title.
    static func display(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }
}

extension View {
    func librarySurface() -> some View {
        background(Palette.ink.ignoresSafeArea())
    }
}
