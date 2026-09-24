import Foundation

/// A launch seam, and nothing else.
///
/// The app's own evidence is a **live probe** — a simulator run against a real
/// Musaeum, with a number or a frame to show for it — and a probe that needs a
/// human to paste a token and tap a cover is a probe nobody re-runs. These
/// variables let a probe run non-interactively:
///
/// ```bash
/// SIMCTL_CHILD_MUSAEUM_PROBE_BASE=http://127.0.0.1:8797 \
/// SIMCTL_CHILD_MUSAEUM_PROBE_TOKEN=<token> \
/// SIMCTL_CHILD_MUSAEUM_PROBE_OPEN=<book id> \
/// SIMCTL_CHILD_MUSAEUM_PROBE_LOG=/tmp/probe.log \
///   xcrun simctl launch <device> dev.jasonoh.Musaeum
/// ```
///
/// Nothing here is read unless the corresponding variable is set, the value is
/// never written to the Keychain or to disk, and `MUSAEUM_PROBE_LOG` is where a
/// probe reads results from (default: `Documents/probe.log` in the app container).
enum Probe {
    static var base: String? { value("MUSAEUM_PROBE_BASE") }
    static var token: String? { value("MUSAEUM_PROBE_TOKEN") }

    /// A book to fetch, download and open without a tap.
    static var openBookID: String? { value("MUSAEUM_PROBE_OPEN") }

    /// A library search term, so a search can be driven with no tap — the library
    /// grid's decider for slice 3a, which `simctl` could otherwise not reach: it
    /// can launch an app and take a frame, never type in it.
    static var query: String? { value("MUSAEUM_PROBE_QUERY") }

    /// A library sort, as `field:direction` (`author:desc`), parsed by the app's
    /// own `LibrarySort.stored`. Applied through the same path a tap takes, so a
    /// run that sets one **remembers** it — which is what makes "the sort you
    /// picked is still there next launch" decidable by two probe runs instead of
    /// by a human looking at a menu.
    static var sort: String? { value("MUSAEUM_PROBE_SORT") }

    /// A filter set, in the app's own encoding for it — parsed by
    /// `LibraryFilters.probe` and applied through the same door the sheet uses:
    ///
    /// ```bash
    /// FILTERS='status=reading'        FILTERS='format=epub;status=unread'
    /// FILTERS='author=Steven Kotler'  FILTERS='rating=4'      FILTERS='tag=running'
    /// ```
    ///
    /// The sheet is a tap-only surface (`simctl` can present nothing, let alone
    /// tick a box in it), so this is the only way a filter run is decidable at
    /// all — and a token this build does not know is **logged** rather than
    /// dropped, because a seam silently ignored reads as a run that found
    /// nothing.
    static var filters: String? { value("MUSAEUM_PROBE_FILTERS") }

    /// Whether the run presents the **filter sheet** on launch. `simctl` can
    /// present nothing and tap nothing, so without this the sheet's own contents
    /// would be a claim for a human frame — and 3.10's decider is a frame. The
    /// sheet is opened through the same state the toolbar button sets.
    static var openSheet: Bool { value("MUSAEUM_PROBE_SHEET") == "1" }

    /// **A book for the run to send**, as a path the app can already read. The
    /// script copies the file into the app's own container first, because a
    /// `simctl` launch cannot open a security scope and a `fileImporter` cannot be
    /// driven at all — so this is how the upload's own call, the copy into the
    /// outbox, the composed request and the refusal classes are decidable without
    /// a human. The *picker* stays a claim for a human frame.
    static var uploadPath: String? { value("MUSAEUM_PROBE_UPLOAD") }

    /// Whether the run presents the **upload sheet**, so the surface that only a
    /// tap otherwise reaches has a frame of its own.
    static var openUploadSheet: Bool { value("MUSAEUM_PROBE_UPLOAD_SHEET") == "1" }

    /// What the probe is exercising, so `library` and `read` runs are distinct.
    /// `write` additionally reports the fraction the reader landed at **through
    /// the app's own door** and reads the row back — the upward path's live
    /// instrument (`ReaderScreen.runWriteProbe`).
    static var action: String? { value("MUSAEUM_PROBE_ACTION") }

    static var isActive: Bool { base != nil || token != nil || openBookID != nil }

    /// A line a probe can read back, also echoed to the console.
    static func log(_ message: String) {
        print("MUSAEUM_PROBE|\(message)")
        guard let url = logURL else { return }
        let line = "MUSAEUM_PROBE|\(message)\n"
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: Data(line.utf8))
        } else {
            try? Data(line.utf8).write(to: url)
        }
    }

    private static var logURL: URL? {
        if let path = value("MUSAEUM_PROBE_LOG") { return URL(fileURLWithPath: path) }
        guard let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return nil }
        return documents.appendingPathComponent("probe.log")
    }

    private static func value(_ key: String) -> String? {
        guard let raw = ProcessInfo.processInfo.environment[key] else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
