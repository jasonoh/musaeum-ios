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
            if Probe.action == "write" { await runWriteProbe() }
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

    private func makeClient() -> MusaeumClient? {
        guard let base = settings.baseURL else { return nil }
        return MusaeumClient(base: base, token: settings.token)
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
