import Foundation

/// The reports the Mac has not taken yet.
///
/// This is the third kind of local state and there is no fourth (CD3): settings,
/// the download index, and this. It exists because the Mac being asleep is the
/// ordinary case rather than the exceptional one (the workstream's D14) — a phone
/// that reported progress only while the server answered would report almost
/// nothing, and carrying the position across machines is the whole point of the
/// workstream.
///
/// **One flat list, oldest first.** A flush walks it in that order, so the last
/// write to reach the Mac carries the newest position. No coalescing, no per-book
/// document, no schema — the shape `DownloadStore` already sets: one JSON index,
/// an injectable root, `@MainActor @Observable`.
@MainActor
@Observable
final class ReportQueue {
    private let file: URL

    /// Oldest first: the order a flush walks, and therefore the order the Mac
    /// converges in.
    private(set) var reports: [ReadingReport] = []

    /// `root` is injectable so a case runs against a temporary directory.
    init(root: URL? = nil) {
        let base = root ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Musaeum", isDirectory: true)
        file = base.appendingPathComponent("reports.json")
        if let data = try? Data(contentsOf: file),
           let decoded = try? JSONDecoder().decode([ReadingReport].self, from: data)
        {
            reports = decoded
        }
    }

    var isEmpty: Bool { reports.isEmpty }

    func enqueue(_ report: ReadingReport) {
        reports.append(report)
        persist()
    }

    func remove(_ id: UUID) {
        reports.removeAll { $0.id == id }
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(reports) else { return }
        try? FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: file, options: .atomic)
    }
}
