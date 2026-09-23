import SwiftUI

/// The library on the phone: one page of the contract's paginated list, a cover
/// grid, and the next page fetched when the last row is reached — with the Mac's
/// own sort and its full-text search on top.
///
/// The order is the **server's** (`docs/rest-api.md` → `GET /api/library`): the
/// sort runs on the same stored sort keys the Mac sorts by, which is why nothing
/// here compares two books and why a search returns the same books in the same
/// order on both devices.
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

    /// What the screen is showing: the whole library, or a search of it, in one
    /// order. Settable only through the three methods below, because every change
    /// to it has to re-fetch — a `query` a view could assign directly would leave
    /// the screen and the request disagreeing, which is the whole class of bug
    /// this shape prevents.
    private(set) var query: LibraryQuery

    private let client: MusaeumClient
    private let pipeline: CoverPipeline
    private let persistSort: (LibrarySort) -> Void

    private var nextOffset = 0
    private var isLastPage = false
    private var loadingMore = false
    private var inFlightCovers: Set<String> = []

    /// **Every answer belongs to a generation, and only the current one lands.**
    /// A search is one request per settled keystroke, and over a tailnet the older
    /// answer can arrive after the newer one — so without this the grid would
    /// paint the results of a query the reader has already typed past. The
    /// superseded task is cancelled too; this is the half that decides what
    /// happens when a cancellation loses that race.
    private var generation = 0

    /// The contract's own default page size; 500 is its cap and there is no
    /// reason to ask for it from a phone.
    static let pageSize = 100

    init(
        client: MusaeumClient,
        sort: LibrarySort = .default,
        pipeline: CoverPipeline = CoverPipeline(),
        persistSort: @escaping (LibrarySort) -> Void = { _ in }
    ) {
        self.client = client
        self.pipeline = pipeline
        self.persistSort = persistSort
        query = LibraryQuery(sort: sort)
    }

    var hasMore: Bool { !isLastPage && books.count < total }

    /// Which "nothing to show" screen applies, or `nil` when there is something to
    /// show. Meaningful only in `.loaded`: *empty* and *still loading* are separate
    /// states, and it is the phase that tells those two apart, so a cold start does
    /// not flash "nothing matches" before the first page has arrived.
    var emptyState: LibraryEmptyState? {
        LibraryEmptyState.of(query, isEmpty: books.isEmpty)
    }

    /// The footer's count. A search says **matches**: "8 books" under a grid of two
    /// would be the sort of copy defect a reader notices straight away.
    var resultCountLabel: String {
        query.isSearching ? "\(total) match\(total == 1 ? "" : "es")" : "\(total) book\(total == 1 ? "" : "s")"
    }

    // MARK: Loading

    func start() async {
        generation += 1
        let mine = generation
        phase = .loading
        books = []
        covers = [:]
        coversFailed = []
        nextOffset = 0
        isLastPage = false
        do {
            let health = try await client.health()
            let page = try await request(offset: 0)
            guard mine == generation else { return }
            self.health = health
            books = page.books
            total = page.total
            nextOffset = page.nextOffset
            isLastPage = page.isLastPage
            phase = .loaded
            // `first=` is not decoration: the order is the thing this slice is
            // about, and a frame can catch the grid mid-flight — one did, showing
            // the previous order while the log already recorded the new one. The
            // rendered array is what the log reports, so the order is decided by a
            // line the app wrote about itself rather than by reading pixels.
            let showing = books.prefix(3).map(\.title).joined(separator: " | ")
            Probe.log("library page count=\(books.count) total=\(total) limit=\(page.limit) offline=\(health.library.rawValue) sort=\(query.sort.storedKey) q=\(query.term ?? "-") first=\(showing)")
            if books.isEmpty {
                Probe.log("library empty kind=\(emptyState.map(String.init(describing:)) ?? "none") macBooks=\(health.books)")
            }
        } catch is CancellationError {
            // A superseded search is not a failure: reporting it as one would put
            // "the Mac is not answering" under a request the reader replaced.
            return
        } catch let error as ClientError {
            guard mine == generation else { return }
            phase = .failed(error.description)
            Probe.log("library failed \(error)")
        } catch {
            guard mine == generation else { return }
            phase = .failed(String(describing: error))
            Probe.log("library failed \(error)")
        }
    }

    func loadNextPageIfNeeded(current book: ContractBook) async {
        guard book.id == books.last?.id, hasMore, !loadingMore else { return }
        loadingMore = true
        defer { loadingMore = false }
        let mine = generation
        do {
            let page = try await request(offset: nextOffset)
            guard mine == generation else { return }
            let known = Set(books.map(\.id))
            books.append(contentsOf: page.books.filter { !known.contains($0.id) })
            total = page.total
            nextOffset = page.nextOffset
            isLastPage = page.isLastPage
            Probe.log("library page=2 count=\(books.count) total=\(total)")
        } catch is CancellationError {
            return
        } catch {
            guard mine == generation else { return }
            // A page that failed is not a library that failed: what is on screen stays.
            Probe.log("library page failed \(error)")
            isLastPage = true
        }
    }

    /// **Every page carries the same narrowing as the first** — the sort, its
    /// direction and the term. A page 2 fetched without them answers with the
    /// unfiltered library from row 101, which is the one way a paged list can lie
    /// without any single request being wrong.
    private func request(offset: Int) async throws -> LibraryPage {
        try await client.library(
            limit: Self.pageSize,
            offset: offset,
            sort: query.sort.wireField,
            direction: query.sort.wireDirection,
            query: query.term
        )
    }

    // MARK: Changing what is shown

    /// Searches, or returns to the whole library when the term is emptied. A call
    /// with the term already in force is a no-op, which is what lets the field's
    /// debounce and an explicit clear both end up here.
    func search(_ text: String) async {
        guard text != query.text else { return }
        query.text = text
        await start()
    }

    /// Choosing a sort is remembering it. The persistence is a parameter of the
    /// model rather than a call the screen has to remember to make *beside* this
    /// one, so no second path can change the order and forget to record it.
    func chooseSort(_ sort: LibrarySort) async {
        guard sort != query.sort else { return }
        query.sort = sort
        persistSort(sort)
        await start()
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
    /// The field's own text. SwiftUI owns it (`.searchable`) and the model is told
    /// about a **settled** value only: the debounce lives in the `.task(id:)`
    /// below, where the typing is, rather than inside the model.
    @State private var searchText = ""

    /// The Mac's own debounce (`src/components/shared/SearchBar.tsx`: 150 ms).
    /// FTS is fast — the app's own search answers in 18 ms — so this is not about
    /// the server's cost, it is about not sending a request per character.
    private static let searchDebounce = Duration.milliseconds(150)

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
            // Always shown, not revealed by scrolling: a search nobody can find is
            // the same as no search, and this is the drawer that keeps it in sight.
            .searchable(
                text: $searchText,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Search titles, authors, series…"
            )
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { sortMenu }
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
        // **The debounce and the cancellation in one primitive.** `.task(id:)`
        // cancels its predecessor when the id changes, so a keystroke supersedes
        // the request before it; the model's generation guard is the other half,
        // for the answer that arrives after a cancellation lost the race.
        .task(id: searchText) {
            guard model != nil else { return }
            try? await Task.sleep(for: Self.searchDebounce)
            guard !Task.isCancelled, let model else { return }
            await model.search(searchText)
        }
        .task {
            if model == nil, let client = makeClient() {
                let model = LibraryModel(
                    client: client,
                    sort: settings.librarySort,
                    persistSort: { settings.save(librarySort: $0) }
                )
                self.model = model
                await model.start()
                await applyProbeSeam(model)
            }
        }
    }

    /// The Mac's eight curated options, as a menu whose label **is** the current
    /// order — so the state that decides the list is readable from the screen.
    ///
    /// **The explicit `HStack` is load-bearing, and two cheaper spellings were
    /// measured and rejected.** A toolbar renders a `Label` icon-only, and
    /// `.labelStyle(.titleAndIcon)` does not override it here: the first build
    /// shipped a bare ⇅ glyph, the build that added the style shipped the same
    /// glyph, and each time it was a *live frame* that caught it. That is worse
    /// than a cosmetic miss — the sort is **remembered**, so a bare glyph means the
    /// app can open reordered with no visible cause, which is the exact dissonance
    /// the remembered sort was chosen to avoid. The probe's `sort=` log line is not
    /// on the phone's screen.
    private var sortMenu: some View {
        Menu {
            Picker("Sort", selection: sortSelection) {
                ForEach(LibrarySort.options, id: \.self) { option in
                    Text(option.label).tag(option)
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "arrow.up.arrow.down")
                Text(model?.query.sort.label ?? LibrarySort.default.label)
            }
        }
    }

    private var sortSelection: Binding<LibrarySort> {
        Binding(
            get: { model?.query.sort ?? LibrarySort.default },
            set: { chosen in Task { await model?.chooseSort(chosen) } }
        )
    }

    private func makeClient() -> MusaeumClient? {
        guard let base = settings.baseURL else { return nil }
        return MusaeumClient(base: base, token: settings.token)
    }

    /// A probe run names a term and a sort with no tap, and **both go through the
    /// app's own doors**: the sort through `chooseSort`, which is what makes it
    /// remembered, and the term through the field's own state as well as the
    /// model, so a frame shows what the run asked for rather than an empty field
    /// over filtered results.
    private func applyProbeSeam(_ model: LibraryModel) async {
        if let raw = Probe.sort {
            let parsed = LibrarySort.stored(raw)
            if parsed.storedKey != raw {
                // A value silently defaulted is a run that decides nothing —
                // slice 1's "the new file was never in the target" trap in another
                // costume — so it says so rather than looking green.
                Probe.log("probe: sort '\(raw)' is not one this build knows — using \(parsed.storedKey)")
            }
            await model.chooseSort(parsed)
        }
        if let term = Probe.query {
            searchText = term
            await model.search(term)
        }
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
        case .loaded:
            if let empty = model.emptyState {
                emptyCard(model, empty)
            } else {
                grid(model)
            }
        }
    }

    /// The two "nothing to show" screens, and they are different sentences because
    /// they are different facts: one is a library with no books in it, and the
    /// other is a term that matched none of them — which the reader can act on.
    @ViewBuilder
    private func emptyCard(_ model: LibraryModel, _ state: LibraryEmptyState) -> some View {
        switch state {
        case .libraryIsEmpty:
            MessageCard(
                title: "Nothing in the library",
                message: "The connection works, and the Mac reports no books yet.",
                action: "Refresh"
            ) { Task { await model.start() } }
        case let .noMatches(term):
            MessageCard(
                title: "Nothing matches",
                message: "No book in this library matches “\(term)”.",
                action: "Clear search"
            ) {
                searchText = ""
                Task { await model.search("") }
            }
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
                Text(model.resultCountLabel)
                    .font(.footnote)
                    .foregroundStyle(Palette.muted)
                    .padding(.bottom, 24)
            }
        }
        // A pull re-runs the *current* query: `start()` composes every request from
        // `query`, so a refresh cannot quietly show the whole library.
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
