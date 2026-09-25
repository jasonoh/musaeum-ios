import SwiftUI

/// The book's contents (RP6): nested entries indented a step per level, the
/// current one in gold and scrolled into view. A tap jumps and closes.
struct ContentsSheet: View {
    let entries: [ReaderTocEntry]
    let currentID: Int?
    let onSelect: (ReaderTocEntry) -> Void

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                List(entries) { entry in
                    Button {
                        onSelect(entry)
                    } label: {
                        Text(entry.title)
                            .font(.display(entry.depth == 0 ? 17 : 15))
                            .foregroundStyle(entry.id == currentID ? Palette.gold : Palette.parchment)
                            .padding(.leading, CGFloat(entry.depth) * 16)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .id(entry.id)
                    .listRowBackground(Palette.surface)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(Palette.surface)
                .onAppear {
                    if let currentID { proxy.scrollTo(currentID, anchor: .center) }
                }
            }
            .navigationTitle("Contents")
            .navigationBarTitleDisplayMode(.inline)
            // Rows scrolled up must not show through the title (6a's contents frame).
            .toolbarBackground(Palette.surface, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(Palette.surface)
    }
}
