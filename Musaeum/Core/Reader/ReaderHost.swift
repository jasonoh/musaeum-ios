import Foundation
import ReadiumNavigator
import ReadiumShared
import ReadiumStreamer
import SwiftUI
import UIKit

/// Readium's navigator, hosted in SwiftUI. It is handed a `Locator` to open at —
/// built from a *fraction*, which is the only coordinate the wire carries — and
/// it reports where it is as one.
struct ReaderHost: UIViewControllerRepresentable {
    let navigator: EPUBNavigatorViewController

    func makeUIViewController(context: Context) -> EPUBNavigatorViewController { navigator }

    func updateUIViewController(_ controller: EPUBNavigatorViewController, context: Context) {}
}

/// Where the reader is, kept locally as the engine's own precise coordinate.
/// Nothing here crosses the wire: the fraction is what travels (invariant 3).
@MainActor
final class PositionRecorder: NSObject, EPUBNavigatorDelegate {
    var onLocation: ((Locator) -> Void)?
    var onTap: ((CGPoint) -> Void)?

    func navigator(_ navigator: Navigator, locationDidChange locator: Locator) {
        onLocation?(locator)
    }

    /// Readium's taps that were not on a link (`VisualNavigatorDelegate`).
    func navigator(_ navigator: any VisualNavigator, didTapAt point: CGPoint) {
        onTap?(point)
    }

    /// The one `NavigatorDelegate` requirement Readium does not default. Without
    /// it the conformance fails to compile rather than at runtime, which is how
    /// this was found.
    func navigator(_ navigator: any Navigator, presentError error: NavigatorError) {
        Probe.log("reader reported \(error)")
    }
}

/// Opens a downloaded book and holds the engine. The whole reason this app can
/// cross devices is the one line that turns the contract's fraction into a
/// `Locator` — `publication.locate(progression:)` — and the one that reads it
/// back off the engine.
@MainActor
@Observable
final class ReaderModel {
    enum Phase: Equatable {
        case loading
        case ready
        case failed(String)
    }

    let book: ContractBook
    private(set) var phase: Phase = .loading
    private(set) var navigator: EPUBNavigatorViewController?

    /// The fraction the engine actually landed at, read off `currentLocation`
    /// rather than assumed from what we handed it. The live probe quotes this
    /// number; it is the phone-side twin of the Mac's own measurement.
    private(set) var landingFraction: Double?
    /// The fraction we asked for, and where it came from — the two halves of
    /// `InitialFraction`'s rule, recorded so a probe can tell which one won.
    private(set) var requestedFraction: Double?

    /// Whether the top bar and bottom strip are up (RP1). Every open starts hidden.
    var chromeShown = false
    /// The book's contents, flattened (RP6); empty when the book has none.
    private(set) var toc: [ReaderTocEntry] = []
    /// The footer's chapter (RP7), `nil` when neither the locator nor the contents name one.
    private(set) var chapterTitle: String?
    /// The contents entry holding the current location, drawn in gold.
    private(set) var currentEntryID: Int?

    private var recorder: PositionRecorder?
    private var positions: LocalPositions?

    init(book: ContractBook) {
        self.book = book
    }

    func load(fileURL: URL, serverPercent: Double?, positions: LocalPositions) async {
        self.positions = positions
        do {
            let httpClient = DefaultHTTPClient()
            let assetRetriever = AssetRetriever(httpClient: httpClient)
            let opener = PublicationOpener(
                parser: DefaultPublicationParser(
                    httpClient: httpClient,
                    assetRetriever: assetRetriever,
                    pdfFactory: DefaultPDFDocumentFactory()
                ),
                contentProtections: []
            )

            guard let fileURL = FileURL(url: fileURL) else {
                throw ClientError.unreachable("the downloaded file is not a URL Readium can read")
            }
            let asset = try await assetRetriever.retrieve(url: fileURL).get()
            let publication = try await opener.open(asset: asset, allowUserInteraction: false).get()
            if case let .success(links) = await publication.tableOfContents() {
                toc = ReaderTocEntry.flatten(links)
            }

            let localFraction = positions.fraction(for: book.id)
            let server = serverPercent ?? book.reading.percent
            let fraction = InitialFraction.initial(local: localFraction, server: server)
            requestedFraction = fraction

            var initial: Locator?
            if let fraction {
                initial = await publication.locate(progression: fraction)
            }

            let navigator = try EPUBNavigatorViewController(
                publication: publication,
                initialLocation: initial,
                config: EPUBNavigatorViewController.Configuration(preferences: readingPreferences)
            )
            let recorder = PositionRecorder()
            recorder.onLocation = { [weak self] locator in
                self?.record(locator)
            }
            recorder.onTap = { [weak self] point in
                self?.handleTap(at: point)
            }
            navigator.delegate = recorder
            self.recorder = recorder
            self.navigator = navigator
            phase = .ready

            let asked = Self.text(fraction)
            let local = Self.text(localFraction)
            let fromServer = Self.text(server)
            Probe.log("reader opened book=\(book.id) requested=\(asked) local=\(local) server=\(fromServer)")

            Task { [weak self] in
                // The engine needs a moment to lay out before it will say where
                // it is; the harness measured the same wait landing at 0.41983
                // for a requested 0.42.
                try? await Task.sleep(for: .seconds(2))
                guard let self, let navigator = self.navigator else { return }
                let location = navigator.currentLocation
                let fraction = location?.locations.totalProgression
                self.landingFraction = fraction
                Probe.log("reader landed=\(Self.text(fraction)) atHref=\(location?.href.string ?? "nil")")
            }
        } catch {
            phase = .failed(String(describing: error))
            Probe.log("reader failed book=\(book.id) error=\(String(describing: error))")
        }
    }

    /// The fraction to report **right now**: what the engine says it is at, or a
    /// brief wait for the engine when it has not said anything yet.
    ///
    /// `nil` means the engine never laid out, and a report of nothing is not a
    /// report — `nil` is not `0`, which is CD5's own distinction and what keeps a
    /// book closed before it opened from being dragged back to its first page.
    /// The wait is bounded because one of this method's two callers is the app
    /// being put in a pocket, where there is no time to spare: the fast path is
    /// `landingFraction`, which `record(_:)` keeps current on every page turn.
    func settledFraction(timeout: Duration = .seconds(3)) async -> Double? {
        if let landingFraction { return landingFraction }
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while landingFraction == nil, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(200))
            if Task.isCancelled { break }
        }
        return landingFraction
    }

    /// RP8: edges turn the page (and put the chrome away), the middle toggles it.
    /// `goLeft`/`goRight` rather than backward/forward so a right-to-left book
    /// turns the way the finger expects.
    func handleTap(at point: CGPoint) {
        guard let navigator else { return }
        switch ReaderGestures.zone(x: point.x, width: navigator.view.bounds.width) {
        case .toggle:
            chromeShown.toggle()
        case .previous:
            chromeShown = false
            Task { _ = await navigator.goLeft(options: NavigatorGoOptions(animated: true)) }
        case .next:
            chromeShown = false
            Task { _ = await navigator.goRight(options: NavigatorGoOptions(animated: true)) }
        }
    }

    /// RP6: a contents jump. The next `locationDidChange` records it exactly as a
    /// page turn would, so the jump is reading progress. A dangling href leaves
    /// the page where it was and says so in the log (CD7 — no alert).
    func jump(to entry: ReaderTocEntry) async {
        chromeShown = false
        guard let navigator else { return }
        let landed = await navigator.go(to: entry.link, options: NavigatorGoOptions(animated: false))
        if !landed {
            Probe.log("reader contents jump failed href=\(entry.link.href)")
        }
    }

    /// The dark page. Readium ships its own CSS, so this is the one place the
    /// app's palette can reach the text: the reading system's own dark theme,
    /// chosen for a reader who reads a library the app paints near-black. Tuned
    /// further only against a frame — typography is judged by looking.
    private var readingPreferences: EPUBPreferences {
        EPUBPreferences(theme: .dark)
    }

    /// A fraction said out loud for a probe line. Kept as its own function so no
    /// single expression in this file has to carry three nested `map`s — the type
    /// checker gives up on those, and its error reads as a conformance failure in
    /// a nearby type.
    static func text(_ value: Double?) -> String {
        guard let value else { return "nil" }
        return String(value)
    }

    private func record(_ locator: Locator) {
        guard let positions else { return }
        let fraction = locator.locations.totalProgression
            ?? locator.locations.progression
            ?? 0
        let json = (try? locator.jsonString()) ?? "{}"
        positions.record(bookId: book.id, fraction: fraction.clampedToUnit(), locatorJSON: json)
        // A page turn after the first layout puts the chrome away (RP1). The
        // first location is the book opening, which must not hide a chrome the
        // probe or the reader has just raised.
        if landingFraction != nil { chromeShown = false }
        let href = locator.href.string
        chapterTitle = ReaderFooterLabel.chapter(locatorTitle: locator.title, href: href, toc: toc)
        currentEntryID = ReaderTocEntry.current(href: href, in: toc)?.id
        landingFraction = fraction
    }
}
