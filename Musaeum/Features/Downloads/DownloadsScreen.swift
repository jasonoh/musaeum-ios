import SwiftUI

/// The shelf that works when the Mac does not. Everything here comes off the
/// phone's own disk — the payload the server sent, the file, and a cover — so
/// this screen makes no request at all (the workstream's D14).
struct DownloadsScreen: View {
    @Environment(DownloadStore.self) private var downloads
    @Environment(LocalPositions.self) private var positions

    @State private var reading: ReadingRequest?
    @State private var sharing: ShareRequest?
    @State private var shareFailure: String?
    @State private var showingShareFailure = false

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
        .sheet(item: $sharing, onDismiss: { downloads.sweepStaging() }) { request in
            ShareSheet(fileURL: request.fileURL)
        }
        // A row has no line to put a failure in, so this screen's goes where a
        // sheet can still be dismissed from: the shelf's own alert, with the one
        // thing worth saying. Reaching it at all means the file went away between
        // the row rendering and the tap.
        .alert("That book could not be shared", isPresented: $showingShareFailure) {
            Button("OK", role: .cancel) { shareFailure = nil }
        } message: {
            Text(shareFailure ?? "")
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

    /// **The row's two glyphs, at one ink box — and the numbers are measurements.**
    ///
    /// SF Symbols each fill their own em box, so two symbols at one font size do
    /// not draw two equal marks. Measured at 3× on the built app
    /// (`docs/evidence/downloads-row-alignment/`, 2026-09-24), the row's pair at
    /// `.body` came out `square.and.arrow.up` **56 px** tall against `book`'s
    /// **46** — a fifth taller, and the whole of "the read and share icons are not
    /// properly aligned": one glyph stands out of the pair, and the row has
    /// nothing else to say which of the two was the right size. Their ink centres
    /// were level within a third of a point (`493.5` against `492.5`), so it is
    /// size and not position.
    ///
    /// This is the library bar's own defect one screen over, and it takes the
    /// bar's own rule (`LibraryScreen.symbolSizes`): **equal ink**, so each glyph
    /// gets the size its own shape needs rather than a shared `.body`. The read
    /// glyph keeps the size it has — it is the row's own tap — and the share
    /// glyph, the one this door arrived beside it, is the one that moves.
    ///
    /// A third glyph would measure its own and join this table.
    private static let readGlyphSize: CGFloat = 17
    private static let shareGlyphSize: CGFloat = 14

    @ViewBuilder
    private func row(_ record: DownloadedBook) -> some View {
        if let book = try? record.book(), let fileURL = downloads.fileURL(for: record.id) {
            HStack(spacing: 0) {
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
                        Image(systemName: "book")
                            .font(.system(size: Self.readGlyphSize))
                            .foregroundStyle(Palette.gold)
                    }
                }
                .buttonStyle(.plain)

                // Two trailing glyphs, and they must not read as one control: gold
                // is what the row's own tap does (open the book), and this one is
                // muted, because sending a book to someone is the row's second
                // thing. It has its own tap target rather than sharing the row's.
                Button {
                    share(book)
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: Self.shareGlyphSize))
                        .foregroundStyle(Palette.muted)
                        .frame(width: 44, height: 44)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Share \(book.title)")
            }
        } else {
            // The payload is stored verbatim and read back through the strict
            // decoder, so a record that no longer matches the contract fails
            // loudly here rather than opening the wrong book.
            Text("This download cannot be read — its record no longer matches the contract. Remove and download it again.")
                .font(.caption)
                .foregroundStyle(Palette.danger)
        }
    }

    /// The shelf's door, and the same call the detail screen makes: the phone's
    /// own copy, staged under a name a recipient can read. Reaching the failure
    /// branch means the file went away between the row rendering and this tap.
    private func share(_ book: ContractBook) {
        do {
            guard let request = try ShareRequest.staged(for: book, in: downloads) else { return }
            shareFailure = nil
            sharing = request
        } catch {
            shareFailure = "The book's file could not be prepared for sharing. Remove the download and fetch it again."
            showingShareFailure = true
            Probe.log("share failed book=\(book.id) error=\(String(describing: error))")
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
