import Foundation

/// One progress report: where the phone got to in a book, and when it read that far.
///
/// This is the whole of the upward path's payload. What is deliberately **not**
/// here is the Readium `Locator`: a locator is an engine coordinate no other
/// engine can use, so it stays on the phone (invariant 3) and the fraction is the
/// member that travels (the workstream's D5).
struct ReadingReport: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let bookId: String
    /// A fraction, `0…1`. The contract refuses `60` rather than reading it as
    /// `0.6`, and an engine that reported `1.0000001` is a rounding artefact
    /// rather than a reason to lose the report.
    let percent: Double
    /// **When the phone read that far** — stamped at the reading, never at the
    /// sending.
    ///
    /// A *queued* report puts this on the wire so the Mac's comparison (its D6)
    /// is against when the reading happened rather than against whenever the flush
    /// eventually ran; a *live* report leaves it out, because the contract says
    /// exactly that — "send it for a report that was queued; omit it for a live
    /// read, when the server's clock is the truth". Keeping the stamp either way
    /// is what stops a report that waited a week from claiming the Mac's clock as
    /// its own and winning an argument it should lose.
    let readAt: Date

    init(id: UUID = UUID(), bookId: String, percent: Double, readAt: Date) {
        self.id = id
        self.bookId = bookId
        self.percent = percent.clampedToUnit()
        self.readAt = readAt
    }
}

/// What became of one report.
enum ReportDisposition: Equatable {
    /// The Mac has it — or refused it as stale, which is a `200 { applied: false }`
    /// and means nothing failed (the Mac's D6). Either way the phone is done with it.
    case accepted
    /// The Mac cannot take it now. It stays on the phone and waits.
    case queued
    /// The Mac will never take it. Dropped, and announced in the log.
    case dropped
}

/// Which of the three a failed attempt becomes.
///
/// A pure rule, so a case decides it rather than a live server. The annex's own
/// reading is that a report for a book the Mac no longer holds is dropped rather
/// than retried for ever; the rest of the contract's refusals are states a later
/// attempt can resolve.
enum ReportPolicy {
    static func disposition(_ error: ClientError) -> ReportDisposition {
        switch error {
        case .notFound:
            // The contract's 404 is uniformly reason-free, so there is nothing
            // else to try and nobody to ask which reason applied.
            .dropped
        case .badRequest:
            // The body this client composed is malformed. Sent again unchanged it
            // would be malformed for ever — and it is a bug here, not a state.
            .dropped
        case .unsupportedAPIVersion:
            // A Mac speaking a contract version this app does not: not transient.
            .dropped
        default:
            // unreachable, busy, library offline, 401, 500, a reply that did not
            // decode. Each is a state a later attempt can resolve — including a
            // rotated token, which the queue outlives rather than loses a reading to.
            .queued
        }
    }
}
