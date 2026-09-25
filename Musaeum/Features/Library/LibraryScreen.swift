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

    /// The Mac's own facet counts, fetched **when the filter sheet opens** and
    /// never with a library page: a request per page for counts nobody has asked
    /// to see, on a screen whose whole cost model is latency.
    private(set) var facets: Facets?
    private(set) var facetsPhase: Phase = .idle

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

    /// The narrowing the filter sheet edits, and what every request is composed
    /// from — read-only here, because every change goes through the funnel below.
    var filters: LibraryFilters { query.filters }
    var hasActiveFilters: Bool { query.filters.isActive }
    var activeFilterCount: Int { query.filters.selectedCount }

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
            Probe.log("library page count=\(books.count) total=\(total) limit=\(page.limit) offline=\(health.library.rawValue) sort=\(query.sort.storedKey) q=\(query.term ?? "-") filters=\(query.filters.probeEncoding.isEmpty ? "-" : query.filters.probeEncoding) first=\(showing)")
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
            query: query.term,
            filters: query.filters.queryItems
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

    // MARK: The filters

    /// **One funnel for every filter change**, for the same reason choosing a sort
    /// is one: a request is composed from the whole `query`, so a path that changed
    /// a filter without re-fetching would leave the screen and the request
    /// disagreeing — the class of bug 3.3 and 3.12 both name, where the *first*
    /// page is right and every page after it is the unfiltered library. A change
    /// that changes nothing asks the Mac for nothing.
    func setFilters(_ new: LibraryFilters) async {
        guard new != query.filters else { return }
        query.filters = new
        await start()
    }

    func toggle(_ status: ReadingStatus) async {
        var updated = query.filters
        updated.toggle(status)
        await setFilters(updated)
    }

    func toggle(_ format: LibraryFilters.Format) async {
        var updated = query.filters
        updated.toggle(format)
        await setFilters(updated)
    }

    func toggle(_ value: String, in axis: LibraryFilters.Axis) async {
        var updated = query.filters
        updated.toggle(value, in: axis)
        await setFilters(updated)
    }

    func setRatingFloor(_ value: Int?) async {
        var updated = query.filters
        updated.minRating = value
        await setFilters(updated)
    }

    /// Off, without touching the term: the sheet's **Clear all** and the bar's own
    /// Clear, which is a control about filters and should not quietly empty a
    /// search field the reader can see.
    func clearFilters() async {
        var updated = query.filters
        updated.clear()
        await setFilters(updated)
    }

    /// Undo **everything** narrowing the library, in one request. This is the empty
    /// card's control, where the term and the filters are two halves of one cause
    /// and clearing them one at a time would paint the library twice.
    func clearNarrowing() async {
        query.filters.clear()
        query.text = ""
        await start()
    }

    /// The Mac's facet counts, fetched when the sheet opens.
    ///
    /// **A failure here is not a failure of the library** (CD7). The sheet's two
    /// vocabulary rows — read status and format — are drawn from the contract and
    /// need no request at all, so a reader can still see and clear a filter while
    /// the Mac is asleep; only the author, series and tag rows go missing, and they
    /// say so. Counts already in hand stay on screen through a failed refresh
    /// rather than blinking away.
    func loadFacets() async {
        if facets == nil { facetsPhase = .loading }
        do {
            let fetched = try await client.facets()
            facets = fetched
            facetsPhase = .loaded
            let formats = fetched.formats.map { "\($0.value):\($0.count)" }.joined(separator: ",")
            let statuses = fetched.readStatus.map { "\($0.value):\($0.count)" }.joined(separator: ",")
            Probe.log("facets authors=\(fetched.authors.count) series=\(fetched.series.count) tags=\(fetched.tags.count) formats=\(formats) statuses=\(statuses)")
        } catch is CancellationError {
            return
        } catch let error as ClientError {
            if facets == nil { facetsPhase = .failed(error.description) }
            Probe.log("facets failed \(error)")
        } catch {
            if facets == nil { facetsPhase = .failed(String(describing: error)) }
            Probe.log("facets failed \(error)")
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
        } catch is CancellationError {
            // **A cover a refetch replaced is not a cover that failed.** This is
            // `load`'s own discipline one scale down: there, a superseded search
            // must not put "the Mac is not answering" under a request the reader
            // replaced; here, a cover cancelled by a reload must not be written
            // into `coversFailed` — that set is permanent for the model's life, so
            // a card would stay blank until the next launch on a Mac that answered
            // every request it was asked. The upload's own refetch is one way to
            // land here (the reload arrives while covers are still loading), and it
            // is not a failure of anything. Left out of the set, the next pass
            // simply asks again.
            return
        } catch {
            coversFailed.insert(book.id)
            Probe.log("cover failed id=\(book.id) error=\(String(describing: error))")
        }
    }
}

struct LibraryScreen: View {
    @Environment(SettingsStore.self) private var settings

    /// **The phone's own shelf, read here for one reason: to know whether it holds
    /// anything.** The door to it is this screen's (`downloadsRow`) since the bar
    /// could not keep four controls and the longest order label at once.
    @Environment(DownloadStore.self) private var downloads

    @State private var model: LibraryModel?
    @State private var detail: ContractBook?
    /// The field's own text. SwiftUI owns it (`.searchable`) and the model is told
    /// about a **settled** value only: the debounce lives in the `.task(id:)`
    /// below, where the typing is, rather than inside the model.
    @State private var searchText = ""
    /// The filter sheet, presented from the toolbar. A probe can open it
    /// (`MUSAEUM_PROBE_SHEET`) because `simctl` cannot tap: without that the
    /// sheet's own contents would be a claim no instrument could decide.
    @State private var showingFilters = false

    /// **The phone's own shelf, as a pushed screen the probe can reach** —
    /// `MUSAEUM_PROBE_DOWNLOADS=1`, for the same reason the sheet has a variable:
    /// `DownloadsScreen` is behind a `NavigationLink`, `simctl` taps nothing, and
    /// a row whose geometry is being judged is not a claim a source read settles.
    @State private var showingDownloads = false

    /// **The upload's state belongs to the screen, not to the sheet.** An outcome
    /// has to survive the sheet closing (the annex's own reason for the library
    /// screen's row), and the probe's upload run has to go through exactly the door
    /// the picker uses.
    @State private var uploads: UploadModel?
    @State private var showingUpload = false

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
                // **Three controls in the bar, not four, and the missing one is the
                // only *destination* of the four.** Measured on the built app at
                // 402 pt with the widest order label (`Recently Added`,
                // `docs/evidence/toolbar-alignment/`): four trailing items overflow,
                // which iOS answers by taking the sort control *and* the shelf ring
                // off the bar into a `•••` — hiding the remembered order that 3a's
                // label exists to show. **A leading item is not a way out**, which
                // was measured too and is why this reads as one group: the same ring
                // in `.topBarLeading` left the trailing cluster overflowing
                // (`Send · filter · •••`), so the toolbar's width is one budget, not
                // one per group. Three trailing items measure 307 pt and the longest
                // label stays inline, where the same three with the ring beside them
                // come to roughly 363 pt and iOS collapses the cluster; the shelf
                // keeps a door on the screen itself (`downloadsRow`).
                ToolbarItem(placement: .topBarTrailing) { uploadButton }
                ToolbarItem(placement: .topBarTrailing) { filterButton }
                ToolbarItem(placement: .topBarTrailing) { sortMenu }
            }
            .navigationDestination(item: $detail) { book in
                BookDetailScreen(book: book, library: model)
            }
            // The same destination the shelf's own door pushes, reached by state
            // rather than by a tap — one destination, so a probe's frame and the
            // reader's are the same screen.
            .navigationDestination(isPresented: $showingDownloads) {
                DownloadsScreen()
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
                let uploadModel = UploadModel()
                uploads = uploadModel
                await model.start()
                await applyProbeSeam(model, client: client)
                // **What a share left for a run that was not there yet.** A book
                // handed over while the app was closed (or not yet configured) is
                // sitting in this app's own `Documents/Inbox`, and this is where it
                // is taken.
                await takePending(uploads: uploadModel, client: client)
                if Probe.openSheet { showingFilters = true }
                if Probe.openUploadSheet { showingUpload = true }
                // **The share door's own screen, without a tap.** A detail is
                // reached by tapping a cover, so this is the only instrument that
                // can put the door in a frame (`MUSAEUM_PROBE_DETAIL`).
                if let id = Probe.detailBookID, let opened = model.books.first(where: { $0.id == id }) {
                    Probe.log("probe detail book=\(id) title=\(opened.title)")
                    detail = opened
                } else if let id = Probe.detailBookID {
                    Probe.log("probe: the library has no book \(id) to open a detail for")
                }
                // **The shelf's own screen, without a tap** — the row geometry
                // this run measures is a frame's business, and `simctl` cannot
                // reach a `NavigationLink`. The line reports what the seam *did*
                // (consumed, and what the shelf held), because a seam that is
                // never consumed reads as a run that found nothing; whether the
                // screen that arrived is the shelf is the frame's to say, and the
                // frame is the decider this seam exists for.
                if Probe.openDownloads {
                    showingDownloads = true
                    Probe.log("probe downloads shelf rows=\(downloads.shelf.count)")
                }
            }
        }
        .sheet(isPresented: $showingFilters) {
            if let model { FilterSheet(model: model) }
        }
        .sheet(isPresented: $showingUpload) {
            if let uploads, let client = makeClient() {
                UploadSheet(model: uploads, client: client)
            }
        }
        // **A book the Mac has just created, and a list that is a page behind.**
        // F3's decision: the returned book is *not* inserted where this client
        // thinks it belongs — the Mac's own sort keys decide a book's place, and a
        // local insertion is exactly the drift invariant 1 exists to prevent. The
        // page the reader is looking at is re-fetched instead, so the order on
        // screen is the server's. The reversal condition the annex names is a
        // re-fetch that visibly loses the reader's scroll position or their search.
        .onChange(of: uploads?.phase) { _, phase in
            guard case .settled(.added) = phase else { return }
            Task { await model?.start() }
        }
        // **A book another app handed over** — the "Copy to Musaeum" half of the
        // share sheet. iOS has already copied the file into this app's own
        // container and opened us; the send goes through the same door the picker
        // uses, so a share is one more way into one path rather than a second
        // upload of its own.
        .onOpenURL { url in
            guard let uploads, let client = makeClient() else { return }
            Task { await take(url, uploads: uploads, client: client) }
        }
    }

    /// The hand-off's one door: what the system left is sent through the app's own
    /// upload path, or refused in the app's own words — and the system's copy is
    /// discarded either way, because a book that has been taken is not this app's
    /// to keep.
    private func take(_ url: URL, uploads: UploadModel, client: MusaeumClient) async {
        switch UploadInbox.incoming(url) {
        case let .success(file):
            await uploads.send(file: file, to: client)
        case let .failure(refusal):
            uploads.refuse(refusal)
        }
        UploadInbox.discard(url)
    }

    private func takePending(uploads: UploadModel, client: MusaeumClient) async {
        for url in UploadInbox.pending() {
            await take(url, uploads: uploads, client: client)
        }
    }

    /// **Equal ink, not one point size — and it is the only sizing rule in this
    /// bar.**
    ///
    /// SF Symbols each fill their own em box, so four symbols at one font size do
    /// not read as four equal marks. Measured on the built app (simulator, 3×,
    /// `frame-bar-before.png`, 2026-09-24) at the toolbar's own symbol size, the
    /// ink boxes came out `square.and.arrow.up` **71 px**, `line.3.horizontal.decrease.circle`
    /// **65**, `arrow.up.arrow.down` **61** and `arrow.down.circle` **65** — the
    /// share glyph a fifth taller than the sort arrows beside it. That is the whole
    /// of "the `Send` set is misaligned with everything to its right": one control
    /// in four stood taller than the other three, and because its ink is
    /// bottom-heavy the pair's optical centre sat 3 px low as well.
    ///
    /// Ink is linear in the font size (measured at two sizes per symbol, a slope of
    /// 3.6–4.2 px per point), so each symbol is given the size its own shape needs
    /// to land on the bar's one box: the `circle` family's own, 65 px ≈ 21.7 pt, at
    /// the toolbar's own 17 pt. These are the numbers that slope gives.
    ///
    /// A new control measures its own and adds it here. **The rule is equal ink, so
    /// an eyeballed size is the defect this table exists to prevent** — the same
    /// reason the sort and filter labels are explicit `HStack`s rather than
    /// `Label`s (3.13).
    private static let symbolSizes: [String: CGFloat] = [
        "square.and.arrow.up": 15.5,
        "arrow.up.arrow.down": 18,
    ]

    /// The toolbar's own symbol size, which is what the `circle` family measured at.
    private static let barSymbolSize: CGFloat = 17

    /// **The one optical nudge in the bar, and it is a measurement too.**
    ///
    /// Equal ink is not yet level ink: `square.and.arrow.up` draws its 65 px box
    /// **3 px lower inside its own frame** than the `circle` family draws its own —
    /// measured on the same frame after the sizes above were applied, its ink box
    /// was `y 222…286` against the rings' `y 219…283`. That 1 pt is the same
    /// magnitude as the misalignment this bar was fixed for, so it is corrected
    /// rather than shrugged at. A symbol with no entry is already centred in its
    /// frame.
    private static let symbolOffsets: [String: CGFloat] = [
        "square.and.arrow.up": -1,
    ]

    /// **The bar's one grammar, written once so the four controls cannot drift
    /// apart again.**
    ///
    /// Each control used to be spelled out at its own call site, and the four
    /// spellings drew the four sizes above. The colours were no rule either:
    /// `Palette.gold` appeared twice — on the sort label and on the downloads
    /// glyph — only because a `Menu` label and a `NavigationLink` inherit the
    /// app's `tint` while a `Button` with its own `foregroundStyle` does not. In
    /// this bar gold now means exactly one thing: **the library is narrowed.**
    /// Everything else is parchment.
    ///
    /// One symbol box, one type size, one spacing, one colour rule — and a control
    /// added later is built here rather than spelled out again.
    private func barControl(_ symbol: String, _ text: String? = nil, narrowed: Bool = false) -> some View {
        HStack(spacing: Self.barSpacing) {
            Image(systemName: symbol)
                .font(.system(size: Self.symbolSizes[symbol] ?? Self.barSymbolSize))
                .offset(y: Self.symbolOffsets[symbol] ?? 0)
            if let text { Text(text) }
        }
        .font(.body)
        .foregroundStyle(narrowed ? Palette.gold : Palette.parchment)
    }

    /// The gap between a control's glyph and its words, for the same reason: one
    /// number, so no control can sit loose against its own label.
    private static let barSpacing: CGFloat = 5

    /// The upload's way in — the one control that starts a send.
    ///
    /// **The explicit `HStack` is load-bearing here, for the reason the sort and
    /// filter controls each paid for once (3.13): a toolbar renders a `Label`
    /// icon-only, and a toolbar item that is a bare glyph is a control the reader
    /// has to guess at.** Measured twice on this screen, so this one is spelled
    /// out from the start — through `barControl`, so it is also the size of the
    /// three beside it.
    private var uploadButton: some View {
        Button {
            showingUpload = true
        } label: {
            barControl("square.and.arrow.up", "Send")
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
    ///
    /// Its words are parchment like every other control's: the current order is
    /// information, not a narrowing, and the one gold in this bar stays the filter
    /// count's alone.
    private var sortMenu: some View {
        Menu {
            Picker("Sort", selection: sortSelection) {
                ForEach(LibrarySort.options, id: \.self) { option in
                    Text(option.label).tag(option)
                }
            }
        } label: {
            barControl("arrow.up.arrow.down", model?.query.sort.label ?? LibrarySort.default.label)
        }
    }

    private var sortSelection: Binding<LibrarySort> {
        Binding(
            get: { model?.query.sort ?? LibrarySort.default },
            set: { chosen in Task { await model?.chooseSort(chosen) } }
        )
    }

    /// The filter control, and **the indicator is the control**: the count beside
    /// the glyph, gold whenever there is one.
    ///
    /// Spelled as an explicit `HStack` for the reason 3.13 records — a toolbar
    /// renders a `Label` icon-only, so a `Label` here would ship a bare glyph and
    /// the app could open narrowed with nothing on screen to say why. That is the
    /// same defect as the sort control's, one control over, and it cost two builds
    /// the first time. The count is the bar's own type size like everything else:
    /// one size in the bar, and the number is a number.
    private var filterButton: some View {
        Button {
            showingFilters = true
        } label: {
            barControl(
                model?.hasActiveFilters == true
                    ? "line.3.horizontal.decrease.circle.fill"
                    : "line.3.horizontal.decrease.circle",
                activeFilterCount,
                narrowed: model?.hasActiveFilters == true
            )
        }
        .accessibilityLabel(activeFilterCount.map { "Filters, \($0) on" } ?? "Filters")
    }

    private var activeFilterCount: String? {
        guard let count = model?.activeFilterCount, count > 0 else { return nil }
        return "\(count)"
    }

    /// The phone's own shelf, as a **door on the screen rather than a control in the
    /// bar** — and the reason is a measurement, not a taste (`docs/evidence/
    /// toolbar-alignment/`): with this ring in the trailing cluster, the widest
    /// order label (`Recently Added`) overflows the bar and iOS takes the sort
    /// control off it into a `•••`, hiding the order 3a's label exists to show. It
    /// is the only one of the bar's four controls that is a *destination* rather
    /// than something done to the list, so it is the one that can leave.
    ///
    /// **It appears exactly when it leads somewhere.** With an empty shelf the
    /// screen it opens is its own empty card, and a permanent strip would cost the
    /// grid 44 pt on every launch to say nothing; a reader who has downloaded
    /// nothing has nothing to browse to, and the first download is what puts the
    /// row, the count and the screen one tap away. That is the same shape as the
    /// two strips beside it — the filter bar and the upload's row are likewise
    /// present when they have something to say, and absent when they do not.
    ///
    /// The words are the destination's own (`DownloadsScreen`'s title is
    /// **Downloaded**), because a door that named the room differently would make
    /// the reader check whether it was the same room.
    @ViewBuilder
    private var downloadsRow: some View {
        if !downloads.shelf.isEmpty {
            NavigationLink {
                DownloadsScreen()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.down.circle")
                    Text("Downloaded").font(.footnote)
                    Spacer(minLength: 8)
                    Text(downloads.shelf.count == 1 ? "1 book" : "\(downloads.shelf.count) books")
                        .font(.footnote)
                        .foregroundStyle(Palette.muted)
                    Image(systemName: "chevron.right").font(.caption2.weight(.semibold))
                }
                .foregroundStyle(Palette.parchment)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Palette.raised)
            }
            // `.plain`, so the row takes this screen's own ink and parchment rather
            // than the system accent — the same reason the filter bar's Clear is
            // `.plain` (a tinted label is a colour the palette does not own).
            .buttonStyle(.plain)
        }
    }

    /// The library screen's own report of an upload — the same view the sheet
    /// draws, so an outcome outlives the sheet and the two surfaces cannot
    /// describe one refusal differently.
    private func uploadRow(_ uploads: UploadModel) -> some View {
        UploadStatusRow(model: uploads) {
            guard let client = makeClient() else { return }
            Task { await uploads.retry(to: client) }
        } reconnect: {
            settings.clear()
        } dismissOutcome: {
            uploads.reset()
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    /// What the library screen says about a narrowing the reader may not remember
    /// asking for, and **the one control that undoes all of it**.
    ///
    /// It clears the filters and not the term: the search field is visible in the
    /// bar above this, so emptying it from here would be a control doing something
    /// the reader did not ask for and can see. The empty card's own control clears
    /// both, because there the two are one cause.
    private func filterBar(_ model: LibraryModel) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "line.3.horizontal.decrease")
            Text(model.activeFilterCount == 1 ? "1 filter on" : "\(model.activeFilterCount) filters on")
                .font(.footnote)
            Spacer(minLength: 8)
            Button {
                Task { await model.clearFilters() }
            } label: {
                Text("Clear").font(.footnote.weight(.semibold))
            }
            // `.plain`, so the label takes this bar's gold rather than the system
            // accent — a text button tints itself, and a blue "Clear" beside a
            // gold "1 filter on" is a colour the palette does not own.
            .buttonStyle(.plain)
        }
        .foregroundStyle(Palette.gold)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Palette.raised)
    }

    private func makeClient() -> MusaeumClient? {
        guard let base = settings.baseURL else { return nil }
        return MusaeumClient(base: base, token: settings.token)
    }

    /// A probe run names a term, a sort and a filter set with no tap, and **every
    /// one goes through the app's own doors**: the sort through `chooseSort`, which
    /// is what makes it remembered, the filters through `setFilters`, which is the
    /// funnel the sheet's own chips call, and the term through the field's own
    /// state as well as the model, so a frame shows what the run asked for rather
    /// than an empty field over filtered results.
    ///
    /// **The order is sort → filters → term**, so the last `library page` line in
    /// the log describes where the screen settled — a run that names more than one
    /// of them logs more than one line, and only the last one is the reading.
    private func applyProbeSeam(_ model: LibraryModel, client: MusaeumClient) async {
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
        if let raw = Probe.filters {
            let parsed = LibraryFilters.probe(raw)
            // A token this build does not know is **said out loud** rather than
            // dropped: a seam silently ignored is a run that looks green and
            // decides nothing, which is the trap the sort seam already names.
            if !parsed.ignored.isEmpty {
                Probe.log("probe: filters '\(raw)' carried \(parsed.ignored.joined(separator: ", ")), which this build does not know")
            }
            await model.setFilters(parsed.filters)
        }
        if let term = Probe.query {
            searchText = term
            await model.search(term)
        }
        // **The upload runs the app's own door.** `UploadModel.send` is what the
        // picker calls, so a run decides the composed request, the copy into the
        // container and the refusal classes with no tap — `simctl` can present
        // nothing and tap nothing, and a `fileImporter` is both. The path is one
        // the app can read without a scope: the script copies the book into the
        // app's own container and passes that path, which is also why the
        // security-scoped half of the picker's flow is a claim for a human frame.
        if let path = Probe.uploadPath, let uploads {
            await uploads.send(file: URL(fileURLWithPath: path), to: client)
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
            VStack(spacing: 0) {
                // **The cause stays on screen, and it stays above the empty card
                // too** — that is exactly where the reader asks "why is this
                // empty?". A filter can narrow the library to nothing without any
                // request being wrong, and without this bar the screen has no way
                // to say so: 3.13's own requirement, and the reason it is a frame's
                // job rather than a source read's.
                if model.hasActiveFilters { filterBar(model) }
                // **The upload's own row, above the grid and above the empty card**
                // — it belongs to the same place as the filter bar for the same
                // reason: it is the one thing on screen that explains what the
                // library is about to look like, and an outcome must not be lost
                // when the sheet closes.
                if let uploads, uploads.isSending || uploads.outcome != nil {
                    uploadRow(uploads)
                }
                // **The shelf's door, in the strips above the grid** — beside the
                // filter bar and the upload's row, because it is the same kind of
                // thing: a sentence about this screen, one tap from the thing it
                // names. It is drawn only when the shelf holds something.
                downloadsRow
                if let empty = model.emptyState {
                    emptyCard(model, empty)
                } else {
                    grid(model)
                }
            }
        }
    }

    /// The three "nothing to show" screens, and they are different sentences
    /// because they are different facts: a library with no books in it, a term that
    /// matched none of them, and a set of filters that excluded all of them. Each
    /// of the last two is something the reader can act on, and each names what to
    /// clear.
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
                message: noMatchesMessage(model, term),
                // **One control, and it clears the whole cause.** With filters on
                // as well as a term, clearing only the term would leave the reader
                // on a library narrowed by something the card no longer names.
                action: model.hasActiveFilters ? "Clear search and filters" : "Clear search"
            ) { Task { await clearNarrowing(model) } }
        case let .noFilterMatches(count):
            MessageCard(
                title: "Nothing matches these filters",
                message: filterMatchesMessage(model, count),
                action: "Clear filters"
            ) { Task { await clearNarrowing(model) } }
        }
    }

    /// The sentence that makes a filtered-to-nothing library *not* an empty one:
    /// the Mac's own book count, which this screen already holds from the
    /// handshake. Without it the card would read "the Mac reports no books yet"
    /// over a library of 7,100 — a lie the reader has no way to catch.
    private func filterMatchesMessage(_ model: LibraryModel, _ count: Int) -> String {
        let books = model.health.map { "The Mac reports \($0.books) books" } ?? "The Mac has books"
        let filters = count == 1 ? "the one filter" : "all \(count) filters"
        return "\(books), and none of them matches \(filters) you have on."
    }

    private func noMatchesMessage(_ model: LibraryModel, _ term: String) -> String {
        guard model.hasActiveFilters else { return "No book in this library matches “\(term)”." }
        let filters = model.activeFilterCount == 1 ? "1 filter is" : "\(model.activeFilterCount) filters are"
        return "No book matches “\(term)” while \(filters) on."
    }

    /// Clears the field's own text as well as the model's, so the search box is
    /// empty over the library it just restored.
    private func clearNarrowing(_ model: LibraryModel) async {
        searchText = ""
        await model.clearNarrowing()
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

/// A cover, bounded **by its cell and never by its own artwork**.
///
/// The box is the Mac's own (`src/components/library/BookCard.tsx`: an
/// `aspect-[2/3] w-full overflow-hidden` frame over an `object-cover` image): a
/// 2:3 box, the artwork filling it and cropped to it. That is a rule rather than a
/// preference — a grid is uniform or it is not a grid — and the first spelling of
/// this view broke it while reading correctly, which is why the reasoning stays
/// here.
///
/// **The seed owns the box.** `.aspectRatio(_:contentMode:)` fits the *proposal*
/// to the ratio; it does not clamp what the child then reports. The ratio used to
/// sit on a `Group` whose child was `Image.resizable().aspectRatio(contentMode:
/// .fill)`, so the child answered with **its own** shape and the box grew to
/// match. Measured on the built app (`CoverBoxTests`, 2026-09-23), a cell proposed
/// 114 pt wide returned 114 × 171 for a 2:3 jacket, **114 × 228** for a 1:2 one and
/// **256.7 × 171** for a 3:2 one: rows of unequal height, landscape covers
/// overlapping the cells beside them, tall ones riding over the title beneath —
/// the owner's report, and now a case no frame has to catch.
///
/// So the geometry comes from a child with **no intrinsic size** — `Palette.raised`,
/// which is the placeholder's colour anyway — and the artwork is an `overlay`,
/// whose reported size cannot move its parent. The clip comes after the overlay,
/// which is what makes `scaledToFill` a crop instead of a bleed.
struct CoverImage: View {
    let data: Data?
    let cornerRadius: CGFloat

    /// 2:3, the Mac's own cover box. Spelled as `CGFloat`s: `2 / 3` in an integer
    /// context is `0`, and a zero ratio is a box of no height.
    static let aspect: CGFloat = 2.0 / 3.0

    var body: some View {
        Palette.raised
            .aspectRatio(Self.aspect, contentMode: .fit)
            .overlay { artwork }
            .clipShape(.rect(cornerRadius: cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(Palette.hairline, lineWidth: 1)
            )
    }

    @ViewBuilder
    private var artwork: some View {
        if let data, let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else {
            Image(systemName: "book.closed")
                .font(.title2)
                .foregroundStyle(Palette.muted.opacity(0.6))
        }
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
