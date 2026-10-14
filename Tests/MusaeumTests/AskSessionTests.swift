import XCTest

@testable import Musaeum

/// A free function, not a method: the fake backend's script is `@Sendable`, and a `@MainActor`
/// test method cannot be called from it.
private func makeDisclosure(_ text: String = "Sends: title, author") -> AskDisclosure {
    AskDisclosure(
        text: text, members: ["title"], rung: .pointer, windowed: false, truncated: [],
        host: "localhost:11434", isLocal: true, model: "m")
}

@MainActor
final class AskSessionTests: XCTestCase {
    // MARK: doubles

    /// A backend that records what it was asked and answers from a script.
    final class FakeBackend: AskBackend, @unchecked Sendable {
        private let lock = NSLock()
        private var _requests: [AskRequest] = []
        private var _terminated: [AskMode] = []
        var capabilityResult: Result<AskCapability, Error> = .success(
            AskCapability(available: true, reason: nil, isLocal: true, host: "localhost:11434", model: "m"))
        var script: @Sendable (AskRequest) -> [AskEvent] = { _ in [.done(.stop)] }
        var thrown: Error?
        /// When set, an `ask` stream yields its script and then never finishes.
        var hangs = false
        /// When set, a probe stream yields its script and then never finishes (a dismissed sheet).
        var probeHangs = false

        var requests: [AskRequest] { lock.lock(); defer { lock.unlock() }; return _requests }
        func requests(_ mode: AskMode) -> [AskRequest] { requests.filter { $0.mode == mode } }
        /// How many streams of this mode have ended (finished, failed, or been abandoned by their
        /// consumer). A hanging stream only ends when its reader lets go — which is what a cancel does.
        func terminated(_ mode: AskMode) -> Int { lock.lock(); defer { lock.unlock() }; return _terminated.filter { $0 == mode }.count }
        private func noteTermination(_ mode: AskMode) { lock.lock(); _terminated.append(mode); lock.unlock() }

        func capability() async throws -> AskCapability { try capabilityResult.get() }

        func ask(_ request: AskRequest) -> AsyncThrowingStream<AskEvent, Error> {
            lock.lock()
            _requests.append(request)
            lock.unlock()
            let events = script(request)
            let thrown = thrown
            // Only an answer or a probe hangs: a preview that never finished would stall `open()`
            let hangs = (hangs && request.mode == .ask) || (probeHangs && request.mode == .probe)
            let mode = request.mode
            return AsyncThrowingStream { continuation in
                continuation.onTermination = { [weak self] _ in self?.noteTermination(mode) }
                for event in events { continuation.yield(event) }
                if let thrown { continuation.finish(throwing: thrown) } else if !hangs { continuation.finish() }
            }
        }
    }

    final class FakeContext: AskContextProviding {
        var context: AskReaderContext? = AskReaderContext(
            label: "Chapter 4", fraction: 0.4, selection: nil,
            section: SectionText(text: "It was the best of times.", offset: 3, truncated: false))
        func askContext() async -> AskReaderContext? { context }
    }

    /// The session holds its context `weak` (the reader owns the session, not the reverse), so a
    /// test that destructures `make()` with `_` would free the context on the spot and every
    /// request would find the reader "not ready". The test keeps what it made.
    private var contexts: [FakeContext] = []

    private func make(
        _ backend: FakeBackend = FakeBackend(), context: FakeContext = FakeContext()
    ) -> (AskSession, FakeBackend, FakeContext) {
        contexts.append(context)
        return (AskSession(bookId: "b1", backend: backend, context: context), backend, context)
    }

    private func waitUntil(_ what: String, timeout: Duration = .seconds(2), _ condition: () -> Bool) async {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while !condition(), ContinuousClock.now < deadline { try? await Task.sleep(for: .milliseconds(10)) }
        XCTAssertTrue(condition(), "timed out waiting for \(what)")
    }

    // MARK: availability

    func testAnUnavailableMacSendsNothing() async {
        let (session, backend, _) = make()
        backend.capabilityResult = .success(
            AskCapability(available: false, reason: "No model set", isLocal: true, host: "h", model: nil))
        await session.open()
        XCTAssertEqual(session.availability, .unavailable("No model set"))
        XCTAssertTrue(backend.requests.isEmpty, "no probe, no preview")
    }

    func testAnUnreachableMacIsAnOrdinaryUnavailableState() async {
        let (session, backend, _) = make()
        backend.capabilityResult = .failure(ClientError.unreachable("timed out"))
        await session.open()
        guard case let .unavailable(reason) = session.availability else { return XCTFail("not unavailable") }
        XCTAssertTrue(reason.contains("not answering"))
    }

    func testNoBackendMeansNotConnected() async {
        let session = AskSession(bookId: "b", backend: nil, context: FakeContext())
        await session.open()
        guard case .unavailable = session.availability else { return XCTFail("not unavailable") }
    }

    // MARK: the probe

    func testOpeningProbesOnceAndSendsTheSectionTextButNothingElse() async {
        let (session, backend, context) = make()
        context.context?.selection = "a highlight"
        backend.script = { request in
            request.mode == .probe ? [.disclosure(makeDisclosure()), .verdict(.strong), .done(.stop)] : [.done(.stop)]
        }
        await session.open()

        let probes = backend.requests(.probe)
        XCTAssertEqual(probes.count, 1)
        XCTAssertEqual(probes[0].rung, .pointer)
        XCTAssertEqual(probes[0].section.text, "It was the best of times.")
        XCTAssertEqual(probes[0].section.offset, 3)
        XCTAssertNil(probes[0].question)
        XCTAssertNil(probes[0].selection, "a probe is pointer-only: the highlight is the referent of a question")
        XCTAssertEqual(session.verdict, .strong)
        XCTAssertFalse(session.probing)
    }

    func testASecondOpenDoesNotProbeAgain() async {
        let (session, backend, _) = make()
        backend.script = { $0.mode == .probe ? [.verdict(.strong), .done(.stop)] : [.done(.stop)] }
        await session.open()
        await session.open()
        XCTAssertEqual(backend.requests(.probe).count, 1)
    }

    func testAProbeErrorLeavesTheVerdictUnknownAndTheSheetUsable() async throws {
        let (session, backend, _) = make()
        backend.script = { $0.mode == .probe ? [.error("Nothing is listening")] : [.done(.stop)] }
        await session.open()
        XCTAssertEqual(session.verdict, .unknown)
        XCTAssertEqual(session.availability, .ready(try backend.capabilityResult.get()))
    }

    func testAProbeErrorIsNotRepeatedOnTheNextOpen() async {
        let (session, backend, _) = make()
        backend.script = { $0.mode == .probe ? [.error("Nothing is listening")] : [.done(.stop)] }
        await session.open()
        await session.open()
        XCTAssertEqual(backend.requests(.probe).count, 1, "unknown is what is known; it is not asked again")
    }

    func testAThrownProbeFailureIsAlsoNonFatal() async {
        let (session, backend, _) = make()
        backend.thrown = ClientError.unreachable("dropped")
        await session.open()
        XCTAssertEqual(session.verdict, .unknown)
        guard case .ready = session.availability else { return XCTFail("the sheet should stay usable") }
    }

    func testAnAIUnavailableDuringTheProbeEndsAvailability() async {
        let (session, backend, _) = make()
        backend.thrown = ClientError.aiUnavailable("No model set")
        await session.open()
        XCTAssertEqual(session.availability, .unavailable("No model set"))
    }

    /// The Mac panel waits for the section before it probes (`!section` returns early), and for the
    /// same reason: a probe is scored against the section's opening, so one sent without text can
    /// only come back `unknown` — a model call and an egress spent on nothing.
    func testNoSectionTextMeansNoProbeYetAndTheSheetStillOpens() async {
        let (session, backend, context) = make()
        context.context?.section = SectionText(text: nil, offset: nil, truncated: false)
        await session.open()

        XCTAssertTrue(backend.requests(.probe).isEmpty)
        XCTAssertNil(session.verdict, "not probed — the next open tries again")
        guard case .ready = session.availability else { return XCTFail("the sheet should still be usable") }
    }

    func testAReaderThatIsNotReadyDoesNotProbeAndDoesNotCrash() async {
        let (session, backend, context) = make()
        context.context = nil
        await session.open()
        XCTAssertNil(session.verdict, "not probed — it will be on the next open")
        XCTAssertTrue(backend.requests(.probe).isEmpty)
    }

    /// The sheet's `.task { await session.open() }` is cancelled when the sheet goes. A cancelled
    /// consumer ends the stream *cleanly* (no thrown error), so without an explicit check the probe
    /// would land `unknown` and lock it for the whole session — the next open would never ask.
    func testADismissedProbeLeavesTheVerdictNilSoTheNextOpenProbesAgain() async {
        let (session, backend, _) = make()
        backend.probeHangs = true
        backend.script = { $0.mode == .probe ? [.disclosure(makeDisclosure())] : [.done(.stop)] }

        let opening = Task { await session.open() }
        await waitUntil("the probe to be in flight") { session.probing }
        opening.cancel()
        await opening.value

        XCTAssertNil(session.verdict, "a cancelled probe is not a verdict")
        XCTAssertFalse(session.probing)
        XCTAssertEqual(backend.requests(.probe).count, 1)
        XCTAssertTrue(backend.requests(.preview).isEmpty, "a dismissed open() sends nothing further")

        backend.probeHangs = false
        backend.script = { $0.mode == .probe ? [.verdict(.weak), .done(.stop)] : [.done(.stop)] }
        await session.open()
        XCTAssertEqual(backend.requests(.probe).count, 2, "the next open probes again")
        XCTAssertEqual(session.verdict, .weak)
    }

    // MARK: the rung

    func testWeakSendsThePassageAndTheOverrideCannotLowerIt() async {
        let (session, backend, _) = make()
        backend.script = { $0.mode == .probe ? [.verdict(.weak), .done(.stop)] : [.done(.stop)] }
        await session.open()

        XCTAssertEqual(session.rung, .passage)
        await session.setPassageOverride(false)
        XCTAssertEqual(session.rung, .passage)

        await session.send("what is this?")
        let ask = backend.requests(.ask).last
        XCTAssertEqual(ask?.rung, .passage)
        XCTAssertEqual(ask?.section.text, "It was the best of times.")
    }

    func testStrongSendsNoSectionTextAtTheAskAndTheOverrideAddsItOnDemand() async {
        let (session, backend, _) = make()
        backend.script = { $0.mode == .probe ? [.verdict(.strong), .done(.stop)] : [.done(.stop)] }
        await session.open()

        await session.send("q1")
        XCTAssertEqual(backend.requests(.ask).last?.rung, .pointer)
        XCTAssertNil(backend.requests(.ask).last?.section.text, "L0 carries none of the section's text")
        XCTAssertNil(backend.requests(.ask).last?.section.offset)

        await session.setPassageOverride(true)
        await session.send("q2")
        XCTAssertEqual(backend.requests(.ask).last?.rung, .passage)
        XCTAssertNotNil(backend.requests(.ask).last?.section.text)
    }

    func testTheHighlightTravelsWithAQuestion() async {
        let (session, backend, context) = make()
        context.context?.selection = "the age of wisdom"
        await session.open()
        await session.send("what does this mean?")
        XCTAssertEqual(backend.requests(.ask).last?.selection, "the age of wisdom")
    }

    // MARK: the preview

    func testThePreviewCarriesThePlaceholderQuestionAndStoresTheDisclosure() async {
        let (session, backend, _) = make()
        backend.script = { request in
            request.mode == .preview ? [.disclosure(makeDisclosure("Sends: title, your question")), .done(.stop)] : [.done(.stop)]
        }
        await session.open()

        let preview = backend.requests(.preview).last
        XCTAssertEqual(preview?.question, AskSession.previewPlaceholder)
        XCTAssertEqual(session.disclosure?.text, "Sends: title, your question")
    }

    // MARK: the answer

    func testAnAnswerStreamsIntoOneModelTurn() async {
        let (session, backend, _) = make()
        backend.script = { request in
            request.mode == .ask ? [.delta("A grand"), .delta(" contrast."), .done(.stop)] : [.done(.stop)]
        }
        await session.open()
        await session.send("what is the tone?")

        XCTAssertEqual(session.turns.map(\.text), ["what is the tone?", "A grand contrast."])
        XCTAssertEqual(session.turns.map(\.role), [.reader, .model])
        XCTAssertFalse(session.turns.last?.streaming ?? true)
        XCTAssertNil(session.failure)
    }

    func testAFailureBeforeTheFirstTokenDropsTheEmptyTurnAndSaysSo() async {
        let (session, backend, _) = make()
        backend.script = { request in
            request.mode == .ask ? [.error("the endpoint rejected the key")] : [.done(.stop)]
        }
        await session.open()
        await session.send("hello?")

        XCTAssertEqual(session.turns.map(\.role), [.reader], "no blank bubble")
        XCTAssertEqual(session.failure, "the endpoint rejected the key")
    }

    func testAnAnswerThatTimedOutKeepsWhatArrivedAndReportsIt() async {
        let (session, backend, _) = make()
        backend.script = { request in request.mode == .ask ? [.delta("Part"), .done(.timeout)] : [.done(.stop)] }
        await session.open()
        await session.send("q")
        XCTAssertEqual(session.turns.last?.text, "Part")
        XCTAssertNotNil(session.failure)
    }

    func testABlankQuestionSendsNothing() async {
        let (session, backend, _) = make()
        await session.open()
        await session.send("   \n ")
        XCTAssertTrue(backend.requests(.ask).isEmpty)
        XCTAssertTrue(session.turns.isEmpty)
    }

    // MARK: cancellation

    func testCancellingKeepsThePartialAnswerAndStopsStreaming() async {
        let (session, backend, _) = make()
        backend.script = { request in request.mode == .ask ? [.delta("partial")] : [.done(.stop)] }
        backend.hangs = true
        await session.open()

        session.ask("a long question")
        await waitUntil("the first token") { session.turns.last?.text == "partial" }
        XCTAssertTrue(session.isAnswering)

        session.cancel()
        await waitUntil("the stream to stop") { !session.isAnswering }
        XCTAssertEqual(session.turns.last?.text, "partial")
        XCTAssertEqual(session.turns.last?.role, .model)
        XCTAssertNil(session.failure, "a cancel the reader asked for is not a failure")
        await waitUntil("the stream to be let go") { backend.terminated(.ask) == 1 }
    }

    func testAskingAgainCancelsTheAnswerInFlight() async {
        let (session, backend, _) = make()
        backend.script = { request in request.mode == .ask ? [.delta("first")] : [.done(.stop)] }
        backend.hangs = true
        await session.open()

        session.ask("one")
        await waitUntil("the first answer to start") { session.turns.last?.text == "first" }
        let firstAnswer = session.turns.last!.id
        session.ask("two")
        await waitUntil("the second question to appear") { session.turns.filter { $0.role == .reader }.count == 2 }
        await waitUntil("the first answer to settle") {
            session.turns.first { $0.id == firstAnswer }?.streaming == false
        }

        XCTAssertEqual(session.turns.first { $0.id == firstAnswer }?.text, "first", "the partial answer is kept")
        await waitUntil("the first stream to be let go") { backend.terminated(.ask) == 1 }
        await waitUntil("the second answer to start") {
            session.turns.filter { $0.role == .model && $0.streaming }.count == 1
        }
        XCTAssertEqual(
            session.turns.filter { $0.role == .model && $0.streaming }.count, 1,
            "at most one answer is ever in flight")
        session.cancel()
        await waitUntil("both streams to be let go") { backend.terminated(.ask) == 2 }
    }
}
