import SwiftUI

/// One book, fetched fresh by id (`GET /api/books/{id}`) so the reading state on
/// screen is the current one — and the place the app decides to download.
@MainActor
@Observable
final class BookDetailModel {
    enum Phase: Equatable {
        case loading
        case loaded(ContractBook)
        case failed(String)
    }

    enum Transfer: Equatable {
        case idle
        case working
        /// A PDF-only book while the Mac lays it out; `nil` until the first 202 says where.
        case preparing(ReflowProgress?)
        case done
        case failed(String)
    }

    private(set) var phase: Phase = .loading
    private(set) var transfer: Transfer = .idle
    private(set) var cover: Data?

    /// The Mac's shelves: `[]` until asked, then the contract's own list.
    private(set) var shelves: [Shelf] = []
    /// Whether the Mac has the shelf feature at all — the same three states the
    /// library's probe has (`nil` unknown, `false` a 404), because it is the
    /// same question. The *Shelves* row draws only on `true` (AC34's rule
    /// reaching the detail, which is the feature's only other surface).
    private(set) var shelvesSupported: Bool?
    /// The shelf whose write is in flight, so a second tap cannot race the
    /// first — and so exactly one row shows the spinner.
    private(set) var toggling: String?
    /// The failure line under the checklist, cleared by the next attempt (CD7:
    /// a failure is a surface, not a dialog).
    private(set) var shelfFailure: String?

    private let client: MusaeumClient
    private let downloads: DownloadStore
    private let pause: @Sendable (Duration) async throws -> Void

    /// The running download, owned here so leaving the screen can cancel the poll.
    private(set) var downloadTask: Task<Void, Never>?

    init(
        client: MusaeumClient,
        downloads: DownloadStore,
        pause: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.client = client
        self.downloads = downloads
        self.pause = pause
    }

    /// True while a download is in flight, whichever kind.
    var isTransferring: Bool {
        switch transfer {
        case .working, .preparing: true
        default: false
        }
    }

    /// The entry point for the button. `transfer` is set here, synchronously, so a
    /// second tap in the same turn finds the download already under way. Only the
    /// reflow poll is kept as a cancellable task: an ordinary download keeps running
    /// after the screen goes away and lands in the shared store, as it always has.
    func startDownload(_ book: ContractBook) {
        guard !isTransferring else { return }
        switch DownloadPlan.of(book) {
        case .reflow:
            transfer = .preparing(nil)
            downloadTask = Task { [weak self] in
                await self?.download(book)
                self?.downloadTask = nil
            }
        case .format:
            transfer = .working
            Task { await download(book) }
        case nil:
            Task { await download(book) }
        }
    }

    /// Leaving the screen mid-pass: the reflow poll stops, nothing is adopted.
    /// A no-op for an ordinary download, which is not kept as a task.
    func cancelDownload() {
        downloadTask?.cancel()
    }

    var book: ContractBook? {
        if case let .loaded(book) = phase { return book }
        return nil
    }

    func load(seed: ContractBook) async {
        if case .loaded = phase {} else { phase = .loaded(seed) }
        do {
            let refreshed = try await client.book(id: seed.id)
            phase = .loaded(refreshed)
            await loadCover(refreshed, size: "full")
        } catch let error as ClientError {
            // The seed came off the library page and is real; a detail that could
            // not refresh is not a detail that failed.
            phase = .loaded(seed)
            transfers(from: error)
        } catch {
            phase = .loaded(seed)
        }
    }

    private func transfers(from error: ClientError) {
        transfer = .failed(error.description)
    }

    /// What shelves this Mac has. One small GET per detail open, and again when
    /// the checklist appears: both are the moment the answer is about to be
    /// drawn, and neither is the per-page cost the facet doctrine refuses.
    func loadShelves() async {
        do {
            shelves = try await client.shelves()
            shelvesSupported = true
        } catch let error as ClientError {
            if case .notFound = error {
                shelves = []
                shelvesSupported = false
                Probe.log("shelves unsupported (detail 404)")
            }
        } catch {}
    }

    /// **One toggle, one request** (F6): the act decides the method, and the
    /// book the Mac answers with replaces the row — never a local flip, which
    /// could only guess. A failure leaves the checklist exactly as it was: the
    /// Mac's writes are idempotent (D10), so the retry is a second tap and
    /// nothing has to be unwound.
    func toggle(_ shelf: Shelf) async {
        guard toggling == nil, let current = book else { return }
        toggling = shelf.id
        defer { toggling = nil }
        shelfFailure = nil
        let on = current.shelves.contains(shelf.id)
        do {
            let updated = on
                ? try await client.removeFromShelf(shelfId: shelf.id, bookId: current.id)
                : try await client.addToShelf(shelfId: shelf.id, bookId: current.id)
            phase = .loaded(updated)
            Probe.log("shelf \(on ? "removed" : "added") book=\(current.id) shelf=\(shelf.id) shelves=\(updated.shelves.joined(separator: ","))")
            // The shelf's own count moved with the write, so the list's number
            // is refetched rather than guessed — one small GET per toggle.
            await loadShelves()
        } catch let error as ClientError {
            shelfFailure = error.description
            Probe.log("shelf toggle failed book=\(current.id) shelf=\(shelf.id) error=\(error)")
        } catch {
            shelfFailure = String(describing: error)
        }
    }

    func loadCover(_ book: ContractBook, size: String) async {
        guard book.cover.full || size == "thumb" else { return }
        cover = try? await client.cover(id: book.id, size: size, version: book.cover.version)
    }

    /// The downward half of the workstream, end to end: the book's payload, its
    /// file, and a cover for the shelf that must work with the Mac asleep.
    func download(_ book: ContractBook) async {
        guard let plan = DownloadPlan.of(book) else {
            transfer = .failed("the Mac holds no format this app can read")
            return
        }
        switch plan {
        case let .format(format):
            await downloadFormat(book, format: format)
        case .reflow:
            await downloadReflow(book)
        }
    }

    private func downloadFormat(_ book: ContractBook, format: String) async {
        transfer = .working
        do {
            let payload = try await client.bookData(id: book.id)
            let (file, _) = try await client.download(id: book.id, format: format)
            let coverData = try? await client.cover(id: book.id, size: "thumb", version: book.cover.version)
            let record = try downloads.adopt(
                temporaryFile: file,
                payload: payload,
                book: book,
                format: format,
                cover: coverData
            )
            transfer = .done
            Probe.log("downloaded book=\(book.id) format=\(format) bytes=\(record.bytes) cover=\(coverData?.count ?? 0)")
        } catch let error as ClientError {
            transfer = .failed(error.description)
            Probe.log("download failed book=\(book.id) error=\(error)")
        } catch {
            transfer = .failed(String(describing: error))
            Probe.log("download failed book=\(book.id) error=\(error)")
        }
    }

    /// A PDF-only book: the Mac lays it out and the phone keeps the EPUB. Nothing is
    /// adopted unless the 200's file arrived; a cancelled poll leaves the screen idle.
    private func downloadReflow(_ book: ContractBook) async {
        transfer = .preparing(nil)
        do {
            let payload = try await client.bookData(id: book.id)
            let (file, _) = try await client.downloadReflow(id: book.id, pause: pause) { [weak self] state in
                self?.transfer = .preparing(state)
            }
            try Task.checkCancellation()
            var pages = 0
            if case let .preparing(last?) = transfer { pages = last.total }
            let coverData = try? await client.cover(id: book.id, size: "thumb", version: book.cover.version)
            let record = try downloads.adopt(
                temporaryFile: file,
                payload: payload,
                book: book,
                format: "epub",
                cover: coverData
            )
            transfer = .done
            Probe.log("reflow downloaded book=\(book.id) bytes=\(record.bytes) pages=\(pages) cover=\(coverData?.count ?? 0)")
        } catch {
            if Task.isCancelled || error is CancellationError {
                transfer = .idle
                Probe.log("reflow cancelled book=\(book.id)")
            } else if let error = error as? ClientError {
                transfer = .failed(error.description)
                Probe.log("reflow failed book=\(book.id) error=\(error)")
            } else {
                transfer = .failed(String(describing: error))
                Probe.log("reflow failed book=\(book.id) error=\(error)")
            }
        }
    }
}

struct BookDetailScreen: View {
    let book: ContractBook
    let library: LibraryModel?

    @Environment(SettingsStore.self) private var settings
    @Environment(DownloadStore.self) private var downloads
    @Environment(LocalPositions.self) private var positions

    @State private var model: BookDetailModel?
    @State private var reading: ReadingRequest?
    @State private var sharing: ShareRequest?
    @State private var shareFailure: String?
    /// The checklist's own presentation — its own state, the shape `reading`
    /// and `sharing` already use.
    @State private var showingShelves = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                hero
                if let model {
                    actions(model)
                    if let detail = model.book { facts(detail) }
                }
            }
            .padding(20)
        }
        .background(Palette.ink)
        .navigationTitle(book.title)
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { model?.cancelDownload() }
        .task {
            guard model == nil, let base = settings.baseURL else { return }
            let model = BookDetailModel(
                client: MusaeumClient(base: base, token: settings.token),
                downloads: downloads
            )
            self.model = model
            await model.load(seed: book)
            await model.loadShelves()
            // **The write's own instrument.** `simctl` can tap no check, so
            // `ACTION=shelf-toggle SHELF=<id>` drives the model's own toggle —
            // the same call the sheet makes — and logs the membership before and
            // after. The sheet itself stays a frame for the owner.
            if Probe.action == "shelf-toggle", let id = Probe.shelfID {
                if let shelf = model.shelves.first(where: { $0.id == id }) {
                    let before = (model.book?.shelves ?? []).joined(separator: ",")
                    Probe.log("probe: shelf-toggle before book=\(book.id) shelves=\(before)")
                    await model.toggle(shelf)
                    let after = (model.book?.shelves ?? []).joined(separator: ",")
                    Probe.log("probe: shelf-toggle after book=\(book.id) shelves=\(after) failure=\(model.shelfFailure ?? "-")")
                } else {
                    Probe.log("probe: shelf-toggle \(id) is not among the \(model.shelves.count) this Mac reports")
                }
            }
        }
        .fullScreenCover(item: $reading) { request in
            ReaderScreen(request: request)
        }
        .sheet(item: $sharing, onDismiss: { downloads.sweepStaging() }) { request in
            ShareSheet(fileURL: request.fileURL)
        }
        .sheet(isPresented: $showingShelves) {
            if let model { ShelfChecklistSheet(model: model) }
        }
    }

    private var hero: some View {
        HStack(alignment: .top, spacing: 16) {
            CoverImage(data: model?.cover ?? library?.covers[book.id], cornerRadius: 8)
                .frame(width: 124)
            VStack(alignment: .leading, spacing: 6) {
                Text(book.title)
                    .font(.display(22, weight: .semibold))
                    .foregroundStyle(Palette.parchment)
                if let author = book.author {
                    Text(author).font(.callout).foregroundStyle(Palette.muted)
                }
                if let series = book.seriesName {
                    Text(series + (book.seriesIndex.map { " #\(Int($0))" } ?? ""))
                        .font(.caption)
                        .foregroundStyle(Palette.gold)
                }
                if let percent = book.reading.percent {
                    Text("\(Int((percent * 100).rounded()))% read on the Mac")
                        .font(.caption)
                        .foregroundStyle(Palette.muted)
                }
                if !book.formats.isEmpty {
                    Text(book.formats.joined(separator: " · ").uppercased())
                        .font(.caption2)
                        .foregroundStyle(Palette.muted)
                }
            }
        }
    }

    @ViewBuilder
    private func actions(_ model: BookDetailModel) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let fileURL = downloads.fileURL(for: book.id) {
                Button {
                    reading = ReadingRequest(book: model.book ?? book, fileURL: fileURL, serverPercent: book.reading.percent)
                } label: {
                    Label("Read", systemImage: "book")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Palette.gold, in: .rect(cornerRadius: 12))
                        .foregroundStyle(Palette.ink)
                }
                // **The second thing you can do with a book that is on the phone.**
                // It sits under *Read* because that is the decision it follows:
                // the book is here, and now it can leave.
                Button {
                    share(model.book ?? book)
                } label: {
                    Label("Share", systemImage: "square.and.arrow.up")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Palette.raised, in: .rect(cornerRadius: 12))
                        .foregroundStyle(Palette.parchment)
                }
                Button(role: .destructive) {
                    try? downloads.remove(id: book.id)
                    positions.forget(bookId: book.id)
                } label: {
                    Text("Remove the download").font(.footnote)
                }
            } else {
                Button {
                    model.startDownload(model.book ?? book)
                } label: {
                    HStack {
                        if model.isTransferring { ProgressView().tint(Palette.ink) }
                        Text(model.isTransferring ? "Downloading…" : "Download to this phone")
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Palette.gold, in: .rect(cornerRadius: 12))
                    .foregroundStyle(Palette.ink)
                }
                .disabled(model.isTransferring)
            }

            switch model.transfer {
            case let .failed(message):
                Text(message).font(.footnote).foregroundStyle(Palette.danger)
            case let .preparing(state):
                Text(Self.preparingLine(state)).font(.footnote).foregroundStyle(Palette.muted)
            case .done:
                Text("Downloaded — it reads with the Mac asleep.").font(.footnote).foregroundStyle(Palette.gold)
            default:
                EmptyView()
            }

            if let shareFailure {
                Text(shareFailure).font(.footnote).foregroundStyle(Palette.danger)
            }
        }
    }

    static func preparingLine(_ state: ReflowProgress?) -> String {
        guard let state, state.total > 0 else { return "Preparing a readable copy…" }
        return "Preparing a readable copy… \(state.completed) of \(state.total) pages"
    }

    /// **A share is a file leaving, and it needs no Mac at all.** What the door
    /// hands the sheet is the phone's own copy of the book, staged under a name a
    /// recipient can read; the only thing that can go wrong is the copy itself,
    /// which is what the line above the button says when it does.
    private func share(_ book: ContractBook) {
        do {
            guard let request = try ShareRequest.staged(for: book, in: downloads) else { return }
            shareFailure = nil
            sharing = request
        } catch {
            shareFailure = "The book's file could not be prepared for sharing."
            Probe.log("share failed book=\(book.id) error=\(String(describing: error))")
        }
    }

    @ViewBuilder
    private func facts(_ book: ContractBook) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if let summary = book.summary, !summary.isEmpty {
                Text(summary)
                    .font(.callout)
                    .foregroundStyle(Palette.parchment.opacity(0.9))
            }
            if !book.tags.isEmpty {
                Text(book.tags.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(Palette.muted)
            }
            detailRows(book)
            if let model, model.shelvesSupported == true {
                shelvesRow(model)
            }
        }
        .padding(.top, 4)
    }

    /// The book's shelves, and the door to the checklist. The value is read from
    /// **the model's own book** — the same freshly-fetched row the rest of this
    /// screen shows — and *None* is a fact, not an absence.
    private func shelvesRow(_ model: BookDetailModel) -> some View {
        let names = model.shelves
            .filter { (model.book?.shelves ?? []).contains($0.id) }
            .map(\.name)
        return Button {
            showingShelves = true
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Shelves")
                    .font(.caption)
                    .foregroundStyle(Palette.muted)
                    .frame(width: 88, alignment: .leading)
                Text(names.isEmpty ? "None" : names.joined(separator: ", "))
                    .font(.caption)
                    .foregroundStyle(Palette.parchment)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(Palette.muted)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Shelves")
    }

    private func detailRows(_ book: ContractBook) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            row("Publisher", book.publisher)
            row("Published", book.publishedDate)
            row("Language", book.language)
            row("ISBN", book.isbn13 ?? book.isbn10)
            row("Rating", book.rating.map { String(repeating: "★", count: $0) })
            row("Size", book.fileSizeBytes.map { ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file) })
            row("Status", book.reading.status.rawValue)
        }
    }

    @ViewBuilder
    private func row(_ label: String, _ value: String?) -> some View {
        if let value, !value.isEmpty {
            HStack(alignment: .top) {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(Palette.muted)
                    .frame(width: 88, alignment: .leading)
                Text(value)
                    .font(.caption)
                    .foregroundStyle(Palette.parchment)
            }
        }
    }
}

/// What the reader needs to open: the book, its local file, and the fraction the
/// Mac holds. Note what is *not* here — no path from the wire, and no position:
/// the Mac's CFI is a coordinate no other engine can use.
struct ReadingRequest: Identifiable {
    let book: ContractBook
    let fileURL: URL
    let serverPercent: Double?
    var id: String { book.id }
}
