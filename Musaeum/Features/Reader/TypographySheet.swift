import SwiftUI

/// The desktop's typography popover, as a half-height sheet so the page stays
/// visible while it changes (RP5). Every change restyles the open page live.
struct TypographySheet: View {
    @Binding var prefs: ReaderPrefs

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            row("Typeface") {
                Picker("Typeface", selection: $prefs.typeface) {
                    Text("Serif").tag(ReaderPrefs.Typeface.serif)
                    Text("Sans").tag(ReaderPrefs.Typeface.sans)
                }
                .pickerStyle(.segmented)
            }
            row("Size") {
                HStack {
                    Button("A−") { prefs.fontSize = max(prefs.fontSize - 1, ReaderPrefs.fontSizeRange.lowerBound) }
                        .font(.display(14))
                    Spacer()
                    Text("\(Int(prefs.fontSize))").monospacedDigit().foregroundStyle(Palette.parchment)
                    Spacer()
                    Button("A+") { prefs.fontSize = min(prefs.fontSize + 1, ReaderPrefs.fontSizeRange.upperBound) }
                        .font(.display(20))
                }
                .foregroundStyle(Palette.gold)
            }
            row("Line height") {
                Slider(value: $prefs.lineHeight, in: ReaderPrefs.lineHeightRange, step: 0.1)
            }
            row("Spacing") {
                Slider(value: $prefs.margin, in: ReaderPrefs.marginRange, step: 8)
            }
            row("Page") {
                Picker("Page", selection: $prefs.theme) {
                    Text("Ink").tag(ReaderPrefs.Theme.ink)
                    Text("Paper").tag(ReaderPrefs.Theme.paper)
                }
                .pickerStyle(.segmented)
            }
        }
        .tint(Palette.gold)
        .padding(20)
        .frame(maxHeight: .infinity, alignment: .top)
        .presentationDetents([.medium])
        .presentationBackground(Palette.surface)
    }

    private func row(_ label: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).font(.caption).foregroundStyle(Palette.muted)
            content()
        }
    }
}
