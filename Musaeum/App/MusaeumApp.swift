import SwiftUI

@main
struct MusaeumApp: App {
    @State private var settings = SettingsStore()
    @State private var downloads = DownloadStore()
    @State private var positions = LocalPositions()
    @State private var reporter = ReadingReporter()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(settings)
                .environment(downloads)
                .environment(positions)
                .environment(reporter)
                .preferredColorScheme(.dark)
                .tint(Palette.gold)
        }
    }
}

/// Configured and unconfigured are different apps, and the empty case is the
/// on-ramp: with no URL and token there is nothing to show and nothing to
/// pretend about.
struct RootView: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(DownloadStore.self) private var downloads
    @Environment(ReadingReporter.self) private var reporter
    @Environment(\.scenePhase) private var scenePhase

    @State private var probeReading: ReadingRequest?

    var body: some View {
        Group {
            if settings.isConfigured {
                LibraryScreen()
            } else {
                ConnectScreen()
            }
        }
        .librarySurface()
        .fullScreenCover(item: $probeReading) { request in
            ReaderScreen(request: request)
        }
        // **When the Mac answers again.** A report queued while it was asleep is
        // flushed on launch and on every return to the foreground — the client's
        // whole half of the workstream's D6 convergence, and the reason the queue
        // is not just a place reports go to die.
        .task {
            await runProbeIfAsked()
            await reporter.flush(to: makeClient())
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await reporter.flush(to: makeClient()) }
        }
    }

    private func makeClient() -> MusaeumClient? {
        guard let base = settings.baseURL else { return nil }
        return MusaeumClient(base: base, token: settings.token)
    }

    /// A probe run fetches, downloads and opens one named book with no taps, so
    /// the same run can be repeated later and its numbers compared. Nothing here
    /// happens unless `MUSAEUM_PROBE_OPEN` is set (`Core/Support/Probe.swift`).
    ///
    /// **The Mac is asked first and the phone's own copy second** — the same
    /// order the app itself uses, which is what makes an offline probe the same
    /// run as an online one with the Mac switched off.
    private func runProbeIfAsked() async {
        guard let id = Probe.openBookID, let base = settings.baseURL else { return }
        let client = MusaeumClient(base: base, token: settings.token)

        var opened: ReadingRequest?

        do {
            let payload = try await client.bookData(id: id)
            let book = try JSONDecoder().decode(ContractBook.self, from: payload)
            if let format = book.preferredFormat {
                let (file, _) = try await client.download(id: id, format: format)
                let cover = try? await client.cover(id: id, size: "thumb", version: book.cover.version)
                try downloads.adopt(
                    temporaryFile: file,
                    payload: payload,
                    book: book,
                    format: format,
                    cover: cover
                )
                let percentText: String = book.reading.percent.map { String($0) } ?? "nil"
                Probe.log("probe downloaded id=\(id) format=\(format) serverPercent=\(percentText)")
                if let localFile = downloads.fileURL(for: id) {
                    opened = ReadingRequest(book: book, fileURL: localFile, serverPercent: book.reading.percent)
                }
            } else {
                Probe.log("probe: the Mac holds no readable format for \(id)")
            }
        } catch {
            Probe.log("probe: the Mac did not answer (\(String(describing: error))) — falling back to the phone's own copy")
        }

        if opened == nil, let stored = downloads.downloaded(id), let book = try? stored.book() {
            let bytes = stored.bytes
            Probe.log("probe offline id=\(id) bytes=\(bytes)")
            if let localFile = downloads.fileURL(for: id) {
                opened = ReadingRequest(book: book, fileURL: localFile, serverPercent: book.reading.percent)
            }
        }

        // Before the "nothing to open" return: a share run's reading is the
        // staged file, not the reader, and it is decidable even when the Mac
        // answered nothing and the phone holds the book from an earlier run.
        if Probe.action == "share" {
            shareForProbe(id: id)
        }

        guard let opened else {
            Probe.log("probe: nothing to open for \(id)")
            return
        }
        probeReading = opened
    }

    /// **What a share would hand out, without a tap.** The store's own call — the
    /// same one both share doors make — followed by the reading only this path
    /// takes: whether the staged file *is* the download (byte for byte), and where
    /// it landed.
    ///
    /// It needs no Mac to answer, which is the point: the file comes off the
    /// phone's own disk, so the run with nothing listening on the port is a
    /// decider rather than a degraded case.
    private func shareForProbe(id: String) {
        guard let stored = downloads.downloaded(id), let book = try? stored.book() else {
            Probe.log("share: nothing to stage for \(id) — the phone holds no download")
            return
        }
        do {
            guard let request = try ShareRequest.staged(for: book, in: downloads) else {
                Probe.log("share: nothing to stage for \(id) — its file is gone")
                return
            }
            let source = downloads.fileURL(for: id)
            let staged = request.fileURL
            let same = source.map {
                FileManager.default.contentsEqual(atPath: $0.path, andPath: staged.path)
            } ?? false
            Probe.log(
                "share reading name=\(staged.lastPathComponent) bytes=\(bytes(of: staged)) "
                    + "source=\(bytes(of: source)) same=\(same ? 1 : 0) "
                    + "dir=\(staged.deletingLastPathComponent().path)"
            )
        } catch {
            Probe.log("share failed id=\(id) error=\(String(describing: error))")
        }
    }

    private func bytes(of url: URL?) -> Int {
        guard let url, let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize else {
            return 0
        }
        return size
    }
}
