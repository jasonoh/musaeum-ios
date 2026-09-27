import SwiftUI

/// **The library's name, set the way the Mac sets it**: Iowan Old Style caps
/// tracked 0.18 em in the gold, then finished per `WordmarkStyle`.
///
/// Every finishing layer is the same `Text` offset by a fraction of a point, so
/// the style changes the surface and never the footprint — the header's fit
/// (`LibraryScreen.screenTitle`) measures one width whatever the style.
struct Wordmark: View {
    var style: WordmarkStyle = .embossed
    var size: CGFloat

    /// The Mac's `tracking-[0.18em]`.
    private var tracking: CGFloat { size * 0.18 }

    /// The finishing layers' offset: a hair at the bar's size, scaled with it.
    private var lift: CGFloat { max(0.75, size / 28) }

    var body: some View {
        face
            .background { finish }
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

    @ViewBuilder
    private var face: some View {
        switch style {
        case .flat:
            letters(Palette.gold)
        case .engraved:
            letters(LinearGradient(colors: [Palette.goldDeep, Palette.gold], startPoint: .top, endPoint: .bottom))
        case .embossed, .extruded:
            letters(LinearGradient(colors: [Palette.goldLight, Palette.gold, Palette.goldDeep], startPoint: .top, endPoint: .bottom))
        }
    }

    @ViewBuilder
    private var finish: some View {
        switch style {
        case .flat:
            EmptyView()
        case .embossed:
            ZStack {
                letters(Color.black.opacity(0.7)).offset(y: lift * 1.5).blur(radius: lift * 0.6)
                letters(Palette.goldLight.opacity(0.55)).offset(y: -lift * 0.75)
            }
        case .engraved:
            ZStack {
                letters(Color.white.opacity(0.14)).offset(y: lift)
                letters(Color.black.opacity(0.85)).offset(y: -lift)
            }
        case .extruded:
            ZStack {
                letters(Color.black.opacity(0.55)).offset(x: lift * 3.5, y: lift * 3.5).blur(radius: lift * 1.5)
                // Half-point steps, so the depth reads as one solid side rather than
                // a stack of copies; the far steps darken like a face turned from the light.
                ForEach(Array(stride(from: 6, through: 1, by: -1)), id: \.self) { step in
                    letters(Palette.goldDeep.mix(with: .black, by: Double(step) * 0.07))
                        .offset(x: lift * CGFloat(step) * 0.4, y: lift * CGFloat(step) * 0.4)
                }
            }
        }
    }
}
