import ReadiumNavigator
import SwiftUI

/// The reader. It opens at a **fraction** and, once a page is turned, keeps the
/// engine's precise coordinate locally so the phone's own resume is exact. On the
/// way out it reports the fraction it is at — the upward half of the workstream.
struct ReaderScreen: View {
    let request: ReadingRequest

    @Environment(LocalPositions.self) private var positions
    @Environment(SettingsStore.self) private var settings
    @Environment(ReadingReporter.self) private var reporter
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismiss) private var dismiss

    @State private var model: ReaderModel
    @State private var showingContents = false
    @State private var showingTypography = false

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
                        .ignoresSafeArea()
                        .simultaneousGesture(
                            DragGesture(minimumDistance: 24, coordinateSpace: .global)
                                .onEnded { value in
                                    let closes = ReaderGestures.closes(
                                        startY: value.startLocation.y,
                                        dx: value.translation.width,
                                        dy: value.translation.height
                                    )
                                    if closes {
                                        Probe.log("reader closed by swipe")
                                        dismiss()
                                    }
                                }
                        )
                }
            case let .failed(message):
                MessageCard(
                    title: "This book did not open",
                    message: message,
                    action: "Close"
                ) { dismiss() }
            }
        }
        .overlay {
            if model.phase == .ready {
                ReaderChrome(
                    title: request.book.title,
                    chapter: model.chapterTitle,
                    percent: ReaderFooterLabel.percent(model.landingFraction),
                    shown: model.chromeShown,
                    hasContents: !model.toc.isEmpty,
                    onClose: { dismiss() },
                    onContents: { showingContents = true },
                    onTypography: { showingTypography = true }
                )
            }
        }
        .statusBarHidden(!model.chromeShown)
        .sheet(isPresented: $showingContents) {
            ContentsSheet(entries: model.toc, currentID: model.currentEntryID) { entry in
                showingContents = false
                Task { await model.jump(to: entry) }
            }
        }
        .sheet(isPresented: $showingTypography) {
            TypographySheet(
                prefs: Binding(get: { model.prefs }, set: { model.apply($0) })
            )
        }
        .task {
            await model.load(
                fileURL: request.fileURL,
                serverPercent: request.serverPercent,
                positions: positions
            )
            if Probe.action == "write" { await runWriteProbe() }
            await applyReaderProbe()
        }
        // **The two doors out of a read**, and both lead to the same place. A
        // reader who closes the book and a reader who puts the phone in a pocket
        // mid-page have both read that far, and the Mac is told either way —
        // otherwise a reader who never closes a book reports nothing at all.
        .onChange(of: scenePhase) { _, phase in
            guard phase != .active else { return }
            Task { await reportProgress(door: "backgrounded") }
        }
        .onDisappear {
            Task { await reportProgress(door: "closed") }
        }
    }

    /// The upward path's single exit. The fraction is what the **engine** says it
    /// is at, never what we asked it for — reporting the request would hand the Mac
    /// its own number back and make the write look like it worked.
    ///
    /// A report of nothing is not a report: a reader whose engine never laid out
    /// says so in the log rather than reporting `0` (CD5's `nil`-is-not-`0`).
    private func reportProgress(door: String) async {
        guard let fraction = await model.settledFraction() else {
            Probe.log("report: nothing to report (door=\(door)) — the engine never said where it was")
            return
        }
        Probe.log("reader exit door=\(door) at=\(ReaderModel.text(fraction))")
        await reporter.report(bookId: request.book.id, percent: fraction, to: makeClient())
    }

    /// The live instrument for the write. `MUSAEUM_PROBE_ACTION=write` with
    /// `MUSAEUM_PROBE_OPEN=<id>` opens the book, reports where it landed **through
    /// the app's own door**, and then reads the row back with an independent `GET`
    /// — so the frame is the Mac's own number rather than the phone's opinion of it.
    private func runWriteProbe() async {
        guard let client = makeClient() else {
            Probe.log("probe write: no server configured")
            return
        }
        guard let fraction = await model.settledFraction(timeout: .seconds(8)) else {
            Probe.log("probe write: nothing to report — the engine never said where it was")
            return
        }
        Probe.log("probe write book=\(request.book.id) percent=\(fraction)")
        await reporter.report(bookId: request.book.id, percent: fraction, to: client)
        Probe.log("probe write pending=\(reporter.pending.count)")
        do {
            let book = try await client.book(id: request.book.id)
            let updatedAt = book.reading.updatedAt.map { ISO8601.string($0) } ?? "nil"
            Probe.log(
                "probe write the Mac now holds percent=\(ReaderModel.text(book.reading.percent))"
                    + " status=\(book.reading.status.rawValue) updatedAt=\(updatedAt)"
            )
        } catch {
            Probe.log("probe write readback failed \(String(describing: error))")
        }
    }

    /// The frames `simctl` cannot tap its way to (AC1/AC2/AC7): `MUSAEUM_PROBE_READER`
    /// raises the chrome or opens the contents once the engine has laid out.
    private func applyReaderProbe() async {
        guard let reader = Probe.reader else { return }
        _ = await model.settledFraction(timeout: .seconds(8))
        try? await Task.sleep(for: .seconds(1))
        switch reader {
        case "chrome": model.chromeShown = true
        case "contents": showingContents = true
        case "typography": showingTypography = true
        case "ink", "paper":
            var prefs = model.prefs
            prefs.theme = reader == "ink" ? .ink : .paper
            model.apply(prefs)
        default: break
        }
        Probe.log("probe reader=\(reader) chapter=\(model.chapterTitle ?? "nil") toc=\(model.toc.count)")
    }

    private func makeClient() -> MusaeumClient? {
        guard let base = settings.baseURL else { return nil }
        return MusaeumClient(base: base, token: settings.token)
    }
}
