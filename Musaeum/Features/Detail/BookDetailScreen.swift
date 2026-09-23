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
        case done
        case failed(String)
    }

    private(set) var phase: Phase = .loading
    private(set) var transfer: Transfer = .idle
    private(set) var cover: Data?

    private let client: MusaeumClient
    private let downloads: DownloadStore

    init(client: MusaeumClient, downloads: DownloadStore) {
        self.client = client
        self.downloads = downloads
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

    func loadCover(_ book: ContractBook, size: String) async {
        guard book.cover.full || size == "thumb" else { return }
        cover = try? await client.cover(id: book.id, size: size, version: book.cover.version)
    }

    /// The downward half of the workstream, end to end: the book's payload, its
    /// file, and a cover for the shelf that must work with the Mac asleep.
    func download(_ book: ContractBook) async {
        guard let format = book.preferredFormat else {
            transfer = .failed("the Mac holds no format this app can read")
            return
        }
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
}

struct BookDetailScreen: View {
    let book: ContractBook
    let library: LibraryModel?

    @Environment(SettingsStore.self) private var settings
    @Environment(DownloadStore.self) private var downloads
    @Environment(LocalPositions.self) private var positions

    @State private var model: BookDetailModel?
    @State private var reading: ReadingRequest?

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
        .task {
            guard model == nil, let base = settings.baseURL else { return }
            let model = BookDetailModel(
                client: MusaeumClient(base: base, token: settings.token),
                downloads: downloads
            )
            self.model = model
            await model.load(seed: book)
        }
        .fullScreenCover(item: $reading) { request in
            ReaderScreen(request: request)
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
                Button(role: .destructive) {
                    try? downloads.remove(id: book.id)
                    positions.forget(bookId: book.id)
                } label: {
                    Text("Remove the download").font(.footnote)
                }
            } else {
                Button {
                    Task { await model.download(model.book ?? book) }
                } label: {
                    HStack {
                        if model.transfer == .working { ProgressView().tint(Palette.ink) }
                        Text(model.transfer == .working ? "Downloading…" : "Download to this phone")
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Palette.gold, in: .rect(cornerRadius: 12))
                    .foregroundStyle(Palette.ink)
                }
                .disabled(model.transfer == .working)
            }

            switch model.transfer {
            case let .failed(message):
                Text(message).font(.footnote).foregroundStyle(Palette.danger)
            case .done:
                Text("Downloaded — it reads with the Mac asleep.").font(.footnote).foregroundStyle(Palette.gold)
            default:
                EmptyView()
            }
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
        }
        .padding(.top, 4)
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
