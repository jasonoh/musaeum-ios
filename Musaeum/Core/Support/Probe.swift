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

    /// What the probe is exercising, so `library` and `read` runs are distinct.
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
