import SwiftUI

/// The shelf that works when the Mac does not. Everything here comes off the
/// phone's own disk — the payload the server sent, the file, and a cover — so
/// this screen makes no request at all (the workstream's D14).
struct DownloadsScreen: View {
    @Environment(DownloadStore.self) private var downloads
    @Environment(LocalPositions.self) private var positions

    @State private var reading: ReadingRequest?

    var body: some View {
        Group {
            if downloads.shelf.isEmpty {
                MessageCard(
                    title: "Nothing downloaded yet",
                    message: "A book you download from the library reads here with the Mac asleep, shut, or off the network.",
                    action: "Back to the library"
                ) { }
            } else {
                shelf
            }
        }
        .background(Palette.ink)
        .navigationTitle("Downloaded")
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(item: $reading) { request in
            ReaderScreen(request: request)
        }
    }

    private var shelf: some View {
        List {
            ForEach(downloads.shelf) { record in
                row(record)
                    .listRowBackground(Palette.surface)
                    .listRowSeparatorTint(Palette.hairline)
            }
            .onDelete { offsets in
                for index in offsets {
                    let record = downloads.shelf[index]
                    try? downloads.remove(id: record.id)
                    positions.forget(bookId: record.id)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    @ViewBuilder
    private func row(_ record: DownloadedBook) -> some View {
        if let book = try? record.book(), let fileURL = downloads.fileURL(for: record.id) {
            Button {
                reading = ReadingRequest(book: book, fileURL: fileURL, serverPercent: nil)
            } label: {
                HStack(spacing: 12) {
                    CoverImage(data: downloads.coverData(for: record.id), cornerRadius: 4)
                        .frame(width: 44)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(book.title)
                            .font(.display(15))
                            .foregroundStyle(Palette.parchment)
                            .lineLimit(2)
                        Text(localStatus(book, record))
                            .font(.caption2)
                            .foregroundStyle(Palette.muted)
                    }
                    Spacer()
                    Image(systemName: "book").foregroundStyle(Palette.gold)
                }
            }
            .buttonStyle(.plain)
        } else {
            // The payload is stored verbatim and read back through the strict
            // decoder, so a record that no longer matches the contract fails
            // loudly here rather than opening the wrong book.
            Text("This download cannot be read — its record no longer matches the contract. Remove and download it again.")
                .font(.caption)
                .foregroundStyle(Palette.danger)
        }
    }

    private func localStatus(_ book: ContractBook, _ record: DownloadedBook) -> String {
        let bytes = ByteCountFormatter.string(fromByteCount: Int64(record.bytes), countStyle: .file)
        if let fraction = positions.fraction(for: book.id) {
            return "\(bytes) · you are \(Int((fraction * 100).rounded()))% in"
        }
        if let percent = book.reading.percent {
            return "\(bytes) · the Mac is \(Int((percent * 100).rounded()))% in"
        }
        return bytes
    }
}
