import SwiftUI

/// The library on the phone: one page of the contract's paginated list, a cover
/// grid, and the next page fetched when the last row is reached.
@MainActor
@Observable
final class LibraryModel {
    enum Phase: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    private(set) var books: [ContractBook] = []
    private(set) var total = 0
    private(set) var health: Health?
    private(set) var covers: [String: Data] = [:]
    private(set) var coversFailed: Set<String> = []

    private let client: MusaeumClient
    private let pipeline: CoverPipeline
    private var nextOffset = 0
    private var isLastPage = false
    private var loadingMore = false
    private var inFlightCovers: Set<String> = []

    /// The contract's own default page size; 500 is its cap and there is no
    /// reason to ask for it from a phone.
    static let pageSize = 100

    init(client: MusaeumClient, pipeline: CoverPipeline = CoverPipeline()) {
        self.client = client
        self.pipeline = pipeline
    }

    var hasMore: Bool { !isLastPage && books.count < total }

    func start() async {
        phase = .loading
        books = []
        covers = [:]
        coversFailed = []
        nextOffset = 0
        isLastPage = false
        do {
            health = try await client.health()
            let page = try await client.library(limit: Self.pageSize, offset: 0)
            books = page.books
            total = page.total
            nextOffset = page.nextOffset
            isLastPage = page.isLastPage
            phase = .loaded
            Probe.log("library page count=\(books.count) total=\(total) limit=\(page.limit) offline=\(health?.library.rawValue ?? "?")")
        } catch let error as ClientError {
            phase = .failed(error.description)
            Probe.log("library failed \(error)")
        } catch {
            phase = .failed(String(describing: error))
            Probe.log("library failed \(error)")
        }
    }

    func loadNextPageIfNeeded(current book: ContractBook) async {
        guard book.id == books.last?.id, hasMore, !loadingMore else { return }
        loadingMore = true
        defer { loadingMore = false }
        do {
            let page = try await client.library(limit: Self.pageSize, offset: nextOffset)
            let known = Set(books.map(\.id))
            books.append(contentsOf: page.books.filter { !known.contains($0.id) })
            total = page.total
            nextOffset = page.nextOffset
            isLastPage = page.isLastPage
            Probe.log("library page=2 count=\(books.count) total=\(total)")
        } catch {
            // A page that failed is not a library that failed: what is on screen stays.
            Probe.log("library page failed \(error)")
            isLastPage = true
        }
    }

    func cover(for book: ContractBook, size: String = "thumb") async {
        guard covers[book.id] == nil, !coversFailed.contains(book.id), !inFlightCovers.contains(book.id) else { return }
        guard book.cover.thumb || size == "full" else { return }
        inFlightCovers.insert(book.id)
        defer { inFlightCovers.remove(book.id) }
        do {
            let data = try await pipeline.data(
                for: client.coverRequest(id: book.id, size: size, version: book.cover.version)
            )
            covers[book.id] = data
        } catch {
            coversFailed.insert(book.id)
            Probe.log("cover failed id=\(book.id) error=\(String(describing: error))")
        }
    }
}

struct LibraryScreen: View {
    @Environment(SettingsStore.self) private var settings

    @State private var model: LibraryModel?
    @State private var detail: ContractBook?

    var body: some View {
        NavigationStack {
            Group {
                if let model {
                    content(model)
                } else {
                    ProgressView().tint(Palette.gold)
                }
            }
            .background(Palette.ink)
            .navigationTitle("Library")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        DownloadsScreen()
                    } label: {
                        Image(systemName: "arrow.down.circle")
                    }
                }
            }
            .navigationDestination(item: $detail) { book in
                BookDetailScreen(book: book, library: model)
            }
        }
        .task {
            if model == nil, let client = makeClient() {
                let model = LibraryModel(client: client)
                self.model = model
                await model.start()
            }
        }
    }

    private func makeClient() -> MusaeumClient? {
        guard let base = settings.baseURL else { return nil }
        return MusaeumClient(base: base, token: settings.token)
    }

    @ViewBuilder
    private func content(_ model: LibraryModel) -> some View {
        switch model.phase {
        case .idle, .loading:
            ProgressView().tint(Palette.gold)
        case let .failed(message):
            MessageCard(title: "The Mac is not answering", message: message, action: "Try again") {
                Task { await model.start() }
            }
        case .loaded where model.books.isEmpty:
            MessageCard(
                title: "Nothing in the library",
                message: "The connection works, and the Mac reports no books yet.",
                action: "Refresh"
            ) { Task { await model.start() } }
        case .loaded:
            grid(model)
        }
    }

    private func grid(_ model: LibraryModel) -> some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 112), spacing: 14)],
                spacing: 18
            ) {
                ForEach(model.books) { book in
                    Button { detail = book } label: {
                        BookGridCell(book: book, cover: model.covers[book.id], isDownloaded: false)
                    }
                    .buttonStyle(.plain)
                    .task {
                        await model.cover(for: book)
                        await model.loadNextPageIfNeeded(current: book)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            if model.hasMore {
                ProgressView().tint(Palette.gold).padding(.bottom, 24)
            } else {
                Text("\(model.total) books")
                    .font(.footnote)
                    .foregroundStyle(Palette.muted)
                    .padding(.bottom, 24)
            }
        }
        .refreshable { await model.start() }
        .overlay(alignment: .top) {
            if model.health?.library == .offline {
                Text("The Mac's library share is not mounted — covers and downloads will fail until it is")
                    .font(.caption)
                    .foregroundStyle(Palette.muted)
                    .padding(8)
                    .frame(maxWidth: .infinity)
                    .background(Palette.raised)
            }
        }
    }
}

struct BookGridCell: View {
    let book: ContractBook
    let cover: Data?
    let isDownloaded: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .bottomTrailing) {
                CoverImage(data: cover, cornerRadius: 6)
                if isDownloaded {
                    Image(systemName: "arrow.down.circle.fill")
                        .foregroundStyle(Palette.gold)
                        .padding(6)
                }
            }
            Text(book.title)
                .font(.display(13))
                .foregroundStyle(Palette.parchment)
                .lineLimit(2, reservesSpace: true)
                .multilineTextAlignment(.leading)
            Text(book.author ?? "Unknown")
                .font(.caption2)
                .foregroundStyle(Palette.muted)
                .lineLimit(1)
        }
    }
}

/// A cover, or the title's own initials while it loads or when the server could
/// not serve it — a grid of grey rectangles reads as broken; a grid of titles
/// reads as a library.
struct CoverImage: View {
    let data: Data?
    let cornerRadius: CGFloat

    var body: some View {
        Group {
            if let data, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    Palette.raised
                    Image(systemName: "book.closed")
                        .font(.title2)
                        .foregroundStyle(Palette.muted.opacity(0.6))
                }
            }
        }
        .aspectRatio(2 / 3, contentMode: .fit)
        .clipShape(.rect(cornerRadius: cornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius)
                .stroke(Palette.hairline, lineWidth: 1)
        )
    }
}

struct MessageCard: View {
    let title: String
    let message: String
    let action: String
    let perform: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Text(title)
                .font(.display(20, weight: .semibold))
                .foregroundStyle(Palette.parchment)
            Text(message)
                .font(.callout)
                .foregroundStyle(Palette.muted)
                .multilineTextAlignment(.center)
            Button(action: perform) {
                Text(action)
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(Palette.gold, in: .capsule)
                    .foregroundStyle(Palette.ink)
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
