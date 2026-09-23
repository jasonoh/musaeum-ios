import ReadiumNavigator
import SwiftUI

/// The reader. It opens at a **fraction** and, once a page is turned, keeps the
/// engine's precise coordinate locally so the phone's own resume is exact.
struct ReaderScreen: View {
    let request: ReadingRequest

    @Environment(LocalPositions.self) private var positions
    @Environment(\.dismiss) private var dismiss

    @State private var model: ReaderModel

    init(request: ReadingRequest) {
        self.request = request
        _model = State(initialValue: ReaderModel(book: request.book))
    }

    var body: some View {
        ZStack {
            Palette.ink.ignoresSafeArea()
            switch model.phase {
            case .loading:
                ProgressView().tint(Palette.gold)
            case .ready:
                if let navigator = model.navigator {
                    ReaderHost(navigator: navigator)
                        .ignoresSafeArea(edges: .bottom)
                }
            case let .failed(message):
                MessageCard(
                    title: "This book did not open",
                    message: message,
                    action: "Close"
                ) { dismiss() }
            }
        }
        .safeAreaInset(edge: .top) {
            bar
        }
        .task {
            await model.load(
                fileURL: request.fileURL,
                serverPercent: request.serverPercent,
                positions: positions
            )
        }
    }

    private var bar: some View {
        HStack(spacing: 12) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.headline)
                    .foregroundStyle(Palette.gold)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(request.book.title)
                    .font(.display(14))
                    .foregroundStyle(Palette.parchment)
                    .lineLimit(1)
                if let fraction = model.landingFraction {
                    Text("\(Int((fraction * 100).rounded()))%")
                        .font(.caption2)
                        .foregroundStyle(Palette.muted)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Palette.surface)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Palette.hairline).frame(height: 1)
        }
    }
}
