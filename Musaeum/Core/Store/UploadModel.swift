import Foundation
import UniformTypeIdentifiers

/// What this app will send, and the two rules that decide it.
///
/// **The declared `format` is derived from the file's own name** (F4). The
/// contract refuses a body whose name disagrees with the declared format, and the
/// picker is exactly where the two can disagree — a `.epub` the system labels
/// something else, a name edited after the fact. So the picker's content types
/// are a *filter* and the extension is the answer: one list of formats serves
/// both, and nothing asks the reader which format their file is.
///
/// **Nothing is uploaded from a security-scoped URL.** A `fileImporter` hands
/// back a URL whose access lasts as long as its scope is open, and an upload is
/// seconds to minutes over a tailnet — so the file is copied into this app's own
/// container while the callback is still running, sent from there, and deleted
/// when the send settles (R4). It is also what makes `fromFile:` possible at all,
/// since the session reads a path rather than a scope.
enum UploadFile {
    /// The formats the route accepts — `format=`'s vocabulary, which is
    /// `GET /api/books/{id}/file`'s too, in the order the picker offers them.
    static let formats = ["epub", "mobi", "azw3", "pdf"]

    /// The format for a file's own name, or `nil` for one this app will not send.
    /// A name with no extension, or one the contract does not name, is `nil`
    /// rather than a guess: the Mac has no book to look up yet, so a wrong guess
    /// is a `400` and a row that cannot open.
    static func format(forFileNamed name: String) -> String? {
        let ext = (name as NSString).pathExtension.lowercased()
        return formats.contains(ext) ? ext : nil
    }

    static func format(for url: URL) -> String? { format(forFileNamed: url.lastPathComponent) }

    /// What the picker may offer: the four formats as content types, resolved by
    /// the same identifiers this app declares as document types, so the picker
    /// and the share sheet agree about what the app can open. A type the system
    /// does not resolve is left out rather than replaced by `public.data`, which
    /// would offer the reader every file on the phone.
    static var contentTypes: [UTType] {
        formats.compactMap { UTType(filenameExtension: $0) }
    }

    /// Where an in-flight copy lives. Inside this app's own container, beside the
    /// downloads — a *scratch* directory, not a store: nothing here outlives the
    /// send that made it.
    static func stagingDirectory() -> URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Musaeum", isDirectory: true)
            .appendingPathComponent("Outbox", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    /// A copy of a picked file that this app owns outright.
    ///
    /// `startAccessingSecurityScopedResource` is asked for and its answer is
    /// honoured rather than assumed: a picker's URL needs the scope, and a probe's
    /// path — a file the app already holds — answers `false` and needs nothing.
    /// The copy is what the upload sends, so a reader who switches apps, or a
    /// scope that closes, cannot take the bytes away mid-send.
    static func stage(_ source: URL) throws -> URL {
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }
        let destination = stagingDirectory()
            .appendingPathComponent("\(UUID().uuidString).\(source.pathExtension.lowercased())")
        try FileManager.default.copyItem(at: source, to: destination)
        return destination
    }

    static func byteCount(of file: URL) -> Int {
        ((try? FileManager.default.attributesOfItem(atPath: file.path)[.size]) as? Int) ?? 0
    }

    /// **Anything still in the outbox belongs to no send.** A copy is deleted as
    /// the send that made it settles, so what is left is a send that was killed in
    /// flight — and it is the *phone's* copy of a file that lives somewhere else
    /// entirely. Swept at launch so it cannot accumulate.
    static func sweepOutbox() {
        let manager = FileManager.default
        let contents = (try? manager.contentsOfDirectory(at: stagingDirectory(), includingPropertiesForKeys: nil)) ?? []
        for file in contents {
            try? manager.removeItem(at: file)
        }
    }
}

/// One upload's own state, and the whole of the phone's half of the contract's
/// upload rules. **No view is in here** (AC6): which refusal class an answer was,
/// whether the book may be called present, and whether offering a retry is honest
/// are all decided by the model, so a case can decide them without a screen.
@MainActor
@Observable
final class UploadModel {
    enum Phase: Equatable {
        case idle
        /// The picked file is being copied into the app's own container.
        case copying(name: String)
        case sending(name: String, bytes: Int)
        case settled(Outcome)
    }

    enum Outcome: Equatable {
        /// The Mac answered `201` — and only then may anything claim the book is
        /// in the library. `duplicate` names the book it collided with.
        case added(book: ContractBook, duplicate: DuplicateMatch?)
        case refused(Refusal)
    }

    private(set) var phase: Phase = .idle

    init() {
        // A copy in the outbox belongs to no send — see `UploadFile.sweepOutbox`.
        UploadFile.sweepOutbox()
    }

    var outcome: Outcome? {
        if case let .settled(outcome) = phase { return outcome }
        return nil
    }

    var isSending: Bool {
        switch phase {
        case .copying, .sending: true
        case .idle, .settled: false
        }
    }

    /// **The claim, in one place.** `false` for everything except the `201`, so no
    /// row can say a book arrived because a request was sent.
    var claimsBookIsInLibrary: Bool {
        if case .added = outcome { return true }
        return false
    }

    /// Whether the row offers a retry. `.waitAndTry` only: a 400 or a 413 is the
    /// book's own problem (and a 413 is exactly the case that used to be retried),
    /// a 500's own note is that a retry uploads a second copy, and a 401 has
    /// somewhere better to go.
    var offersRetry: Bool { refusal?.kind == .waitAndTry }

    /// Whether the row offers the credential's own control.
    ///
    /// **Not "Settings" — this app has no Settings screen, and a 401 arrives when
    /// it is configured.** The only surface that edits the token is the connect
    /// screen, which is shown exactly when the app is *not* configured. So what
    /// `RootView` can offer is the way back there: clearing the credential, which
    /// is the control this property names. The annex assumed a place to go; this is
    /// that place, and the deviation is recorded rather than hidden behind a
    /// button that opens nothing.
    var offersReconnect: Bool { refusal?.kind == .credential }

    var refusal: Refusal? { if case let .refused(refusal) = outcome { return refusal } else { return nil } }

    /// What the row says, and what it advises — the model's copy, not the view's.
    var title: String {
        switch phase {
        case .idle: "Send a book to the Mac"
        case .copying: "Reading the file…"
        case .sending: "Sending…"
        case let .settled(outcome):
            switch outcome {
            case let .added(_, duplicate): duplicate == nil ? "Sent to the library" : "Sent — and you already had it"
            case .refused: "The Mac refused it"
            }
        }
    }

    var message: String {
        switch phase {
        case .idle: "Pick an EPUB, MOBI, AZW3 or PDF, and it goes to the Mac's own importer."
        case let .copying(name): name
        case let .sending(name, bytes): "\(name) — \(Self.size(bytes))"
        case let .settled(outcome):
            switch outcome {
            case let .added(book, duplicate):
                if let duplicate {
                    "“\(book.title)” is in the library now. The Mac matched it against your existing “\(duplicate.existingTitle)” (\(duplicate.matchType.rawValue)), and added it as its own book."
                } else {
                    "“\(book.title)” is in the library now, as the row stood the moment it was imported — the Mac's metadata pass is still running, so its series and cover may fill in after this."
                }
            case let .refused(refusal): refusal.message
            }
        }
    }

    var advice: String? {
        refusal?.advice
    }

    // MARK: Sending

    /// A copy held back for a retry.
    ///
    /// Only a **retryable** refusal keeps one, because only then is sending the
    /// same bytes again the right thing to offer — and by the time a reader taps
    /// *Try again*, the picked file's own security scope is long closed, so the
    /// bytes have to be the app's own copy rather than the URL the picker gave. It
    /// is deleted as its send settles, and swept at the next launch if the app goes
    /// away before it is sent.
    private var held: (file: URL, name: String, format: String)?

    /// **The one door an upload goes through**, for the picker and for a probe
    /// run: the file it is handed is a URL either way, and every rule above is
    /// applied to it here rather than in a view.
    func send(file: URL, to client: MusaeumClient) async {
        clearHeld()
        let name = file.lastPathComponent
        guard let format = UploadFile.format(for: file) else {
            settle(.refused(.unsendable(name)), line: "upload refused name=\(name) — no format the contract names")
            return
        }

        phase = .copying(name: name)
        let staged: URL
        do {
            staged = try UploadFile.stage(file)
        } catch {
            settle(.refused(.unreadable(error.localizedDescription)), line: "upload refused name=\(name) — could not be read: \(error)")
            return
        }
        await deliver(staged: staged, name: name, format: format, to: client)
    }

    /// The same bytes again, from the copy a retryable refusal kept. With nothing
    /// held there is nothing to send, and the row goes back to idle rather than
    /// pretending otherwise.
    func retry(to client: MusaeumClient) async {
        guard let held else {
            phase = .idle
            return
        }
        await deliver(staged: held.file, name: held.name, format: held.format, to: client)
    }

    /// The picker's own failure — a file the app could not even reach. Nothing was
    /// asked of the Mac, so it is not a refusal by it; a cancelled picker is a
    /// reader changing their mind, which is not a state at all.
    func pickingFailed(_ error: any Error) {
        let ns = error as NSError
        guard ns.code != NSUserCancelledError else { return }
        refuse(.unreadable(ns.localizedDescription))
    }

    /// **A refusal the app produced itself** — a file the share sheet handed over
    /// that is not a book, a picker that failed for a reason of its own. Nothing
    /// was asked of the Mac, and the row says so in the same three classes
    /// everything else does.
    func refuse(_ refusal: Refusal) {
        settle(.refused(refusal), line: "upload refused kind=\(refusal.kind.name) \(refusal.message)")
    }

    /// Back to idle, so the row can be dismissed and a second book sent. Anything
    /// held for a retry goes with it: the reader has moved on.
    func reset() {
        clearHeld()
        phase = .idle
    }

    private func deliver(staged: URL, name: String, format: String, to client: MusaeumClient) async {
        let bytes = UploadFile.byteCount(of: staged)
        phase = .sending(name: name, bytes: bytes)
        Probe.log("upload sending name=\(name) format=\(format) bytes=\(bytes)")
        // **The run's own clock**, so R2's question ("what does an upload cost, and
        // is the foreground window enough?") has a number in the evidence rather
        // than an impression — the same reason every other probe line carries its
        // own measurement. It times the *app's* send (staging included), which is
        // what the reading is about; the wire's own cost is the same run's
        // bytes/second.
        let started = ContinuousClock.now
        let elapsedMs = { Int(((ContinuousClock.now - started) / .milliseconds(1))) }

        do {
            let result = try await client.uploadBook(file: staged, format: format, filename: name)
            discard(staged)
            let duplicate = result.duplicate.map { "\($0.matchType.rawValue):\($0.existingBookId)" } ?? "-"
            settle(
                .added(book: result.book, duplicate: result.duplicate),
                line: "upload added id=\(result.book.id) title=\(result.book.title) bytes=\(bytes) ms=\(elapsedMs()) duplicate=\(duplicate)"
            )
        } catch is CancellationError {
            discard(staged)
            phase = .idle
            Probe.log("upload cancelled name=\(name) ms=\(elapsedMs())")
        } catch let error as ClientError {
            finish(Refusal.from(error), staged: staged, name: name, format: format, ms: elapsedMs(), detail: "\(error)")
        } catch {
            let refusal = Refusal.from(.unreachable((error as NSError).localizedDescription))
            finish(refusal, staged: staged, name: name, format: format, ms: elapsedMs(), detail: "\(error)")
        }
    }

    /// What a settled send leaves behind: the refusal's class is the model's
    /// answer, and **whether the bytes stay is decided by that class rather than by
    /// the view that drew it**.
    ///
    /// A send that settled — created, refused for its own sake, cancelled — takes
    /// its copy with it: a phone that kept a copy per refused book would fill its
    /// own container with books nobody asked it to hold. The one exception is a
    /// refusal worth waiting out, because *Try again* can only be honest if the
    /// bytes are still there.
    private func finish(_ refusal: Refusal, staged: URL, name: String, format: String, ms: Int, detail: String) {
        if refusal.kind == .waitAndTry {
            clearHeld()
            held = (staged, name, format)
        } else {
            discard(staged)
        }
        settle(.refused(refusal), line: "upload refused kind=\(refusal.kind.name) ms=\(ms) error=\(detail)")
    }

    private func discard(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    private func clearHeld() {
        if let held { discard(held.file) }
        held = nil
    }

    private func settle(_ outcome: Outcome, line: String) {
        phase = .settled(outcome)
        Probe.log(line)
    }

    private static func size(_ bytes: Int) -> String {
        let mb = Double(bytes) / 1_048_576
        return mb >= 1 ? String(format: "%.1f MB", mb) : "\(bytes / 1024) KB"
    }
}

/// What the Mac's answer means for the reader, in the contract's own three
/// classes rather than as one failure (4a's fourth item: "the three refusal
/// classes treated differently, because they are different").
///
/// It is an `Error` as well as a value: the hand-off's rule (`UploadInbox`) answers
/// `Result<URL, Refusal>`, because a file the share sheet handed over that is not a
/// book is a refusal in exactly this vocabulary and not a second one.
struct Refusal: Equatable, Error {
    enum Kind: Equatable, Sendable {
        /// A 400 or a **413** — this book's own problem. Nothing to retry: the
        /// same bytes are refused the same way.
        case thisBook
        /// A 503, or a Mac that is not answering: `isRetryable`'s own set, which
        /// is the contract's answer and not a second opinion.
        case waitAndTry
        /// A 401 — a credential problem with one place to go and fix it.
        case credential
        /// A 500, a payload that did not match the contract, a version this app
        /// does not speak. Nothing here is offered, and the 500 has its own
        /// reason: the Mac's own note is that *a retry after a 500 uploads a
        /// second copy*.
        case other

        var name: String {
            switch self {
            case .thisBook: "thisBook"
            case .waitAndTry: "waitAndTry"
            case .credential: "credential"
            case .other: "other"
            }
        }
    }

    let kind: Kind
    let message: String

    var advice: String {
        switch kind {
        case .thisBook: "Sending it again would be refused the same way."
        case .waitAndTry: "The Mac is busy or asleep — waiting a moment and sending it again is worth it."
        case .credential: "The Mac refused the token. Reconnect with the one it is showing now — Musaeum → Settings → Phone access."
        case .other: "Nothing is retried from here: the Mac's own note is that a retry after a failed import uploads a second copy."
        }
    }

    /// **The class is derived, never asserted beside the error** — one funnel, so a
    /// status mapped correctly and then treated as retryable anyway is impossible.
    /// The 413 is the case that matters: `isRetryable` is false for it, and this
    /// arm is what keeps it out of `waitAndTry` even if that ever moved.
    static func from(_ error: ClientError) -> Refusal {
        switch error {
        case .tooLarge, .badRequest:
            Refusal(kind: .thisBook, message: error.description)
        case .unauthorized:
            Refusal(kind: .credential, message: error.description)
        default:
            Refusal(kind: error.isRetryable ? .waitAndTry : .other, message: error.description)
        }
    }

    static func unsendable(_ name: String) -> Refusal {
        Refusal(
            kind: .thisBook,
            message: "“\(name)” is not a book this app can send — the Mac takes \(UploadFile.formats.joined(separator: ", "))."
        )
    }

    static func unreadable(_ detail: String) -> Refusal {
        Refusal(kind: .thisBook, message: "The chosen file could not be read: \(detail)")
    }
}
