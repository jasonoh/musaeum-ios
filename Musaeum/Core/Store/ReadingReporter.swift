import Foundation

/// The upward path: one report, sent if the Mac will take it and kept if it will not.
///
/// Two rules do all the work, and both live here rather than in a view:
///
/// 1. **A report is written to the phone before the Mac is asked.** Leaving the
///    foreground is exactly when this is called, and a suspension mid-send must
///    not lose the reading — so the queue write is the first thing that happens
///    and the removal is the last.
/// 2. **A flush walks the queue oldest first and stops at the first "not now".**
///    A Mac that is asleep must not be asked once per queued report, and the last
///    write to arrive is the one carrying the newest position.
@MainActor
@Observable
final class ReadingReporter {
    private let queue: ReportQueue
    private var isFlushing = false

    init(queue: ReportQueue = ReportQueue()) {
        self.queue = queue
    }

    /// What is still waiting to be taken.
    var pending: [ReadingReport] { queue.reports }

    /// **The one door.** The reader closing and the app leaving the foreground
    /// both come through here, so there is one rule to get right rather than two.
    ///
    /// `client` is `nil` when the app has no server configured — the report is
    /// kept rather than dropped, because the reading happened either way.
    func report(bookId: String, percent: Double, at readAt: Date = Date(), to client: MusaeumClient?) async {
        let report = ReadingReport(bookId: bookId, percent: percent, readAt: readAt)
        queue.enqueue(report)

        guard let client else {
            Probe.log("report queued (no server configured) book=\(bookId) percent=\(report.percent)")
            return
        }

        // A live report carries **no** clock: the contract says to send `at` for a
        // report that was queued and to omit it for a live read, so while the Mac
        // is answering, the Mac's own clock is the truth.
        let disposition = await attempt(report, includingClock: false, to: client)
        if disposition != .queued {
            queue.remove(report.id)
        }
        Probe.log("report \(name(disposition)) book=\(bookId) percent=\(report.percent)")

        if disposition == .accepted {
            // The Mac is answering, so whatever piled up behind this one goes too.
            await flush(to: client)
        }
    }

    /// Oldest first, stopping at the first answer that says "not now". A report
    /// the Mac can never take is dropped and announced rather than retried for ever.
    func flush(to client: MusaeumClient?) async {
        guard let client, !isFlushing, !queue.isEmpty else { return }
        isFlushing = true
        defer { isFlushing = false }

        // The array is read once, so removing during the walk is safe — and a
        // report enqueued mid-flush is simply left for the next one.
        for report in queue.reports {
            let disposition = await attempt(report, includingClock: true, to: client)
            switch disposition {
            case .accepted:
                queue.remove(report.id)
            case .dropped:
                queue.remove(report.id)
                Probe.log("report dropped book=\(report.bookId) — the Mac does not have that book")
            case .queued:
                Probe.log("report flush stopped at book=\(report.bookId) — the Mac is not taking reports")
                return
            }
        }
        Probe.log("report queue drained")
    }

    private func attempt(
        _ report: ReadingReport,
        includingClock: Bool,
        to client: MusaeumClient
    ) async -> ReportDisposition {
        do {
            let result = try await client.reportReading(
                id: report.bookId,
                percent: report.percent,
                at: includingClock ? report.readAt : nil
            )
            if !result.applied {
                // A `200 { applied: false }`: the Mac already holds a later
                // position, so this report lost the argument D6 exists to arbitrate.
                // Nothing failed and nothing is retried — its clock will not become
                // newer than the Mac's row.
                Probe.log("report refused as stale book=\(report.bookId) percent=\(report.percent)")
            }
            return .accepted
        } catch let error as ClientError {
            return ReportPolicy.disposition(error)
        } catch {
            return .queued
        }
    }

    private func name(_ disposition: ReportDisposition) -> String {
        switch disposition {
        case .accepted: "accepted"
        case .queued: "queued"
        case .dropped: "dropped"
        }
    }
}
