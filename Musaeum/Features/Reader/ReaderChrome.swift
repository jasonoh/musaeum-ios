import SwiftUI

/// The reader's furniture (RP1): hidden, a faint `Chapter · %` footer; shown, a
/// top bar and a bottom strip. It overlays the page rather than insetting it, so
/// raising it never reflows the text, and its empty middle passes taps through
/// to Readium.
struct ReaderChrome: View {
    let title: String
    let chapter: String?
    let percent: String?
    let shown: Bool
    let hasContents: Bool
    let onClose: () -> Void
    let onContents: () -> Void
    let onTypography: (() -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            if shown {
                topBar.transition(.move(edge: .top).combined(with: .opacity))
            }
            Spacer(minLength: 0)
            if shown {
                bottomStrip.transition(.move(edge: .bottom).combined(with: .opacity))
            } else {
                progressLabel
                    .padding(.horizontal, 32)
                    .padding(.bottom, 4)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: shown)
    }

    private var topBar: some View {
        HStack(spacing: 4) {
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.headline)
                    .foregroundStyle(Palette.gold)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Close book")
            Text(title)
                .font(.display(15))
                .foregroundStyle(Palette.parchment)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
            if let onTypography {
                Button(action: onTypography) {
                    Text("Aa")
                        .font(.display(17))
                        .foregroundStyle(Palette.gold)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Typography")
            } else {
                Color.clear.frame(width: 44, height: 44)
            }
        }
        .padding(.horizontal, 8)
        .background(Palette.surface.ignoresSafeArea(edges: .top))
        .overlay(alignment: .bottom) {
            Rectangle().fill(Palette.hairline).frame(height: 1)
        }
    }

    private var bottomStrip: some View {
        HStack(spacing: 12) {
            Button(action: onContents) {
                Label(hasContents ? "Contents" : "No contents in this book", systemImage: "list.bullet")
                    .font(.subheadline)
            }
            .foregroundStyle(hasContents ? Palette.gold : Palette.muted)
            .disabled(!hasContents)
            Spacer(minLength: 8)
            progressLabel
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Palette.surface.ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) {
            Rectangle().fill(Palette.hairline).frame(height: 1)
        }
    }

    /// A long chapter truncates; the percent never does.
    private var progressLabel: some View {
        HStack(spacing: 4) {
            if let chapter {
                Text(chapter).lineLimit(1).truncationMode(.tail)
                if percent != nil { Text("·") }
            }
            if let percent {
                Text(percent).monospacedDigit().fixedSize()
            }
        }
        .font(.caption)
        .foregroundStyle(Palette.muted)
    }
}
