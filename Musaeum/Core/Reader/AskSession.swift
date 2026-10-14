import Foundation
import Observation

/// What the reader's Ask sheet needs from the open book, at the moment it asks.
struct AskReaderContext: Equatable, Sendable {
    /// The book's own contents label for the section — never a chapter number.
    var label: String?
    /// The reader's position in the book, 0–1.
    var fraction: Double?
    /// The highlighted text, verbatim, if any.
    var selection: String?
    var section: SectionText
}

/// The open book, seen by the Ask sheet. `ReaderModel` conforms; a test double can too.
@MainActor
protocol AskContextProviding: AnyObject {
    /// `nil` when the reader is not ready (the engine has not laid out yet).
    func askContext() async -> AskReaderContext?
}

/// The phone's side of a conversation about one book: the probe's verdict, the rung it sets, the
/// transcript, and what the Mac last said it would send.
///
/// **The Mac holds nothing between requests**, so this holds the session (design D3): the verdict
/// is cached here and the rung travels in every request. Everything is in memory and dies with
/// the reader screen — nothing is written to disk (design D8, iOS invariant 7).
///
/// What a prompt contains, and whether a model "knows" this book, are the Mac's decisions. This
/// type decides only *when* to ask for them: one probe per (book, session), a preview whenever
/// the rung changes, and which request carries the section's text.
///
/// **Cancellation ends a stream cleanly** — a cancelled consumer of `AsyncThrowingStream` gets
/// `nil` from `next()`, not a thrown error — so "the loop finished" never means "the answer
/// completed". Every place that would treat the end as a result checks `Task.isCancelled` first.
@MainActor
@Observable
final class AskSession {
    enum Availability: Equatable {
        case checking
        case unavailable(String)
        case ready(AskCapability)
    }

    struct Turn: Identifiable, Equatable {
        enum Role: Equatable { case reader, model }
        let id = UUID()
        let role: Role
        var text: String
        var streaming: Bool
    }

    /// A preview has no question yet; the Mac assembles it as an ask when it sees one. The word is
    /// never sent to a model — a preview calls none.
    static let previewPlaceholder = "your question"

    private(set) var availability: Availability = .checking
    /// `nil` until the book has been probed.
    private(set) var verdict: RecallVerdict?
    private(set) var probing = false
    private(set) var turns: [Turn] = []
    /// The Mac's own line about what the next (or current) send contains and where it goes.
    private(set) var disclosure: AskDisclosure?
    private(set) var failure: String?
    private(set) var passageOverride = false

    // `@Observable` rewrites stored properties as tracked computed ones, which a `weak` reference
    // cannot be; none of these is something a view reads, so none is tracked.
    @ObservationIgnored private let bookId: String
    @ObservationIgnored private let backend: (any AskBackend)?
    @ObservationIgnored private weak var context: (any AskContextProviding)?
    @ObservationIgnored private var current: Task<Void, Never>?
    /// Bumped by every preview and every send. A disclosure is shown only if nothing newer has
    /// started since its request went out: previews finish in any order, and the line says what
    /// leaves the phone, so an older one must not overwrite a newer one.
    @ObservationIgnored private var disclosureGeneration = 0

    init(bookId: String, backend: (any AskBackend)?, context: any AskContextProviding) {
        self.bookId = bookId
        self.backend = backend
        self.context = context
    }

    /// `weak` forces the passage; the override can add it, never remove it (design D6).
    var rung: AskRung { verdict == .weak || passageOverride ? .passage : .pointer }

    var isAnswering: Bool { turns.last?.streaming == true }

    // MARK: opening

    func open() async {
        guard let backend else {
            availability = .unavailable("This app is not connected to a Mac.")
            return
        }
        // Ready and probed — or ready with a probe already in flight, which this open must neither
        // repeat nor knock back to `.checking`.
        if case .ready = availability, verdict != nil || probing {
            await refreshPreview()
            return
        }
        availability = .checking
        do {
            let capability = try await backend.capability()
            // Dismissed while asking: not an answer about the Mac, so neither "unavailable" nor "ready".
            if Task.isCancelled { return }
            guard capability.available else {
                availability = .unavailable(capability.reason ?? "The Mac cannot answer questions right now.")
                return
            }
            availability = .ready(capability)
        } catch {
            if Task.isCancelled { return }
            availability = .unavailable(Self.sentence(error))
            return
        }
        await probeIfNeeded()
        if Task.isCancelled { return }
        await refreshPreview()
    }

    /// One probe per (book, session). A probe that cannot run — the reader is not ready, or the
    /// section has yielded no text to score against — leaves the verdict `nil`, so the next open
    /// tries again. So does one that is **cancelled** (the sheet was dismissed mid-probe): it
    /// learned nothing, and locking `unknown` would deny the whole session a real verdict. One
    /// that runs and fails lands `unknown`, which is what is actually known, and is not repeated.
    /// `aiUnavailable` is not a verdict either: a Mac that later gains a model should be probed.
    ///
    /// `probing` is claimed **before** the first suspension, so two overlapping opens cannot both
    /// pass the guard while one waits for the reader's context.
    private func probeIfNeeded() async {
        guard verdict == nil, !probing, let backend else { return }
        probing = true
        defer { probing = false }
        guard let reader = await context?.askContext(), reader.section.text != nil, !Task.isCancelled
        else { return }

        let generation = disclosureGeneration
        var landed = RecallVerdict.unknown
        do {
            for try await event in backend.ask(makeRequest(.probe, reader, question: nil)) {
                switch event {
                case let .disclosure(line): if generation == disclosureGeneration { disclosure = line }
                case let .verdict(value): landed = value
                case .delta, .done, .error: break
                }
            }
        } catch let error as ClientError {
            if Task.isCancelled { return }
            if case let .aiUnavailable(reason) = error {
                availability = .unavailable(reason)
                return
            }
        } catch {
            // Dropped: unverified, and the sheet stays usable. (A cancel is handled below.)
        }
        // A cancelled consumer ends the stream cleanly, so reaching here proves nothing.
        if Task.isCancelled { return }
        verdict = landed
        Probe.log("ask verdict=\(landed)")
    }

    // MARK: the disclosure line

    func setPassageOverride(_ on: Bool) async {
        passageOverride = on
        await refreshPreview()
    }

    /// Ask the Mac what the next send would contain. A preview calls no model; a failed one is not
    /// something the reader can act on, and the send reports its own.
    func refreshPreview() async {
        guard !Task.isCancelled, case .ready = availability, let backend else { return }
        disclosureGeneration += 1
        let generation = disclosureGeneration
        guard let reader = await context?.askContext(), !Task.isCancelled else { return }
        do {
            for try await event in backend.ask(makeRequest(.preview, reader, question: Self.previewPlaceholder)) {
                if case let .disclosure(line) = event, generation == disclosureGeneration { disclosure = line }
            }
        } catch {
            if !Task.isCancelled { Probe.log("ask preview failed: \(Self.sentence(error))") }
        }
    }

    // MARK: asking

    /// **The entry point the sheet uses** (with `cancel()`): starts an answer and remembers its
    /// task, cancelling any answer still in flight.
    func ask(_ question: String) {
        cancel()
        current = Task { [weak self] in await self?.send(question) }
    }

    /// Stop the answer in flight. What arrived is kept as text and marked finished at once — the
    /// transcript does not wait for the cancelled task to notice. It owns only the task `ask(_:)`
    /// started: a `send(_:)` awaited directly is cancelled by cancelling its caller, not by this.
    func cancel() {
        current?.cancel()
        current = nil
        for turn in turns where turn.streaming { finish(turn.id) }
    }

    /// The body of an answer. The sheet calls `ask(_:)`, not this: `ask(_:)` is what `cancel()` can
    /// stop. This is internal so a test can await a whole answer.
    func send(_ question: String) async {
        let text = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, case .ready = availability, let backend, !Task.isCancelled else { return }
        let read = await context?.askContext()
        // Replaced or dismissed while the reader's context was being read: nothing was shown,
        // nothing is sent, and no sentence is written for an answer nobody is waiting on.
        if Task.isCancelled { return }
        guard let reader = read else {
            failure = "The book is still opening — try again in a moment."
            return
        }
        failure = nil
        disclosureGeneration += 1
        turns.append(Turn(role: .reader, text: text, streaming: false))
        let answer = Turn(role: .model, text: "", streaming: true)
        turns.append(answer)
        defer { finish(answer.id) }

        // This answer's own figures, for its own log line — `turns` and `failure` may be another's by then.
        var chars = 0
        var ownFailure: String?
        do {
            for try await event in backend.ask(makeRequest(.ask, reader, question: text)) {
                if Task.isCancelled { break }
                switch event {
                case let .disclosure(line): disclosure = line
                case let .delta(piece):
                    chars += piece.count
                    append(piece, to: answer.id)
                case let .error(message):
                    ownFailure = message
                    failure = message
                case let .done(reason):
                    if reason == .timeout {
                        ownFailure = "The model stopped answering."
                        failure = ownFailure
                    }
                case .verdict: break
                }
            }
        } catch is CancellationError {
        } catch let error as ClientError {
            if !Task.isCancelled {
                ownFailure = Self.sentence(error)
                failure = ownFailure
                if case let .aiUnavailable(reason) = error { availability = .unavailable(reason) }
            }
        } catch {
            if !Task.isCancelled {
                ownFailure = Self.sentence(error)
                failure = ownFailure
            }
        }
        Probe.log(
            Task.isCancelled
                ? "ask cancelled chars=\(chars)" : "ask answered chars=\(chars) failure=\(ownFailure ?? "none")")
    }

    // MARK: building a request

    /// **What leaves the phone.** The section's text goes to the Mac for a probe (to be scored) and
    /// for an ask at the passage rung (to be windowed and sent on); an ask at the pointer rung
    /// carries none of it — the Mac would ignore it, and there is no reason for it to travel.
    private func makeRequest(_ mode: AskMode, _ reader: AskReaderContext, question: String?) -> AskRequest {
        let effective: AskRung = mode == .probe ? .pointer : rung
        let carriesText = mode == .probe || effective == .passage
        if carriesText, mode != .preview {
            // The offset the phone sent, for the probe's own record — numbers only, never the text.
            Probe.log(
                "ask offset=\(reader.section.offset.map(String.init) ?? "nil") units=\(reader.section.text?.utf16.count ?? 0) truncated=\(reader.section.truncated)"
            )
        }
        return AskRequest(
            bookId: bookId,
            mode: mode,
            rung: effective,
            section: AskSection(
                label: reader.label,
                text: carriesText ? reader.section.text : nil,
                offset: carriesText ? reader.section.offset : nil,
                truncated: carriesText && reader.section.truncated),
            fraction: reader.fraction,
            selection: mode == .probe ? nil : reader.selection,
            question: question)
    }

    // MARK: turns

    private func append(_ piece: String, to id: UUID) {
        guard let index = turns.firstIndex(where: { $0.id == id }) else { return }
        turns[index].text += piece
    }

    /// Settle an answer. An empty one is dropped, so a failure before the first token reads as a
    /// sentence rather than a blank box.
    private func finish(_ id: UUID) {
        guard let index = turns.firstIndex(where: { $0.id == id }) else { return }
        if turns[index].text.isEmpty {
            turns.remove(at: index)
        } else {
            turns[index].streaming = false
        }
    }

    static func sentence(_ error: Error) -> String {
        (error as? ClientError)?.description ?? error.localizedDescription
    }
}
