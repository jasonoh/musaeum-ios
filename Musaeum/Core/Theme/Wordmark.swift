import SwiftUI

/// **The library's name, set the way the Mac sets it**: Iowan Old Style caps
/// tracked 0.18 em in the gold (`src/components/layout/Sidebar.tsx`), embossed —
/// a gold gradient face, a lit top edge, a dark lip below.
///
/// The finish was chosen on the device against engraved, extruded and flat; all
/// four are in the history at the commit that introduced this view.
///
/// Every finishing layer is the same `Text` offset by a fraction of a point and
/// drawn as a background, so the finish never changes the footprint — the
/// header's fit (`LibraryScreen.screenTitle`) measures the letters alone.
struct Wordmark: View {
    var size: CGFloat

    /// The Mac's `tracking-[0.18em]`.
    private var tracking: CGFloat { size * 0.18 }

    /// The finishing layers' offset: a hair at the bar's size, scaled with it.
    private var lift: CGFloat { max(0.75, size / 28) }

    var body: some View {
        letters(LinearGradient(colors: [Palette.goldLight, Palette.gold, Palette.goldDeep], startPoint: .top, endPoint: .bottom))
            .background {
                ZStack {
                    letters(Color.black.opacity(0.7)).offset(y: lift * 1.5).blur(radius: lift * 0.6)
                    letters(Palette.goldLight.opacity(0.55)).offset(y: -lift * 0.75)
                }
            }
            // `.tracking` spaces after the last letter too; the Mac pulls the same
            // slack back with `translate-x-[0.13em]`. Here it is given back, so the
            // word ends where its last letter does.
            .padding(.trailing, -tracking)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Musaeum")
    }

    private func letters(_ fill: some ShapeStyle) -> some View {
        Text("MUSAEUM")
            .font(.custom("IowanOldStyle-Bold", fixedSize: size))
            .tracking(tracking)
            .foregroundStyle(fill)
            .lineLimit(1)
            .fixedSize()
    }
}
