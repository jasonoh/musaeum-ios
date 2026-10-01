import XCTest

@testable import Musaeum

private let uploadBase = URL(string: "http://100.64.0.1:8788")!

/// The upload: what the phone sends, what it does with each answer, and **what it
/// refuses to claim**.
///
/// **No stub closure is written inside a test method, and every helper that builds
/// one is `nonisolated` — and not by taste.** This class is `@MainActor`, so a
/// closure formed in one of its methods *inherits* that isolation, and
/// `StubURLProtocol` invokes its handler from a background thread, where the
/// inherited isolation is an assertion that fails as `dispatch_assert_queue_fail`
/// / SIGTRAP and takes the test host with it. It reads as "the app quit" rather
/// than as a failed case; slice 1 paid for it, and `ReadingReporterTests` records
/// it.
@MainActor
final class UploadTests: XCTestCase {
    // MARK: helpers

    private nonisolated func fixture(_ name: String) throws -> Data {
        let bundle = Bundle(for: UploadTests.self)
        guard let url = bundle.url(forResource: name, withExtension: "json") else {
            throw XCTSkip("no \(name).json in the test bundle — run scripts/vendor-contract-fixtures.sh")
        }
        return try Data(contentsOf: url)
    }

    /// A client that answers every request the same way.
    private nonisolated func stub(_ response: StubURLProtocol.Response) -> MusaeumClient {
        StubURLProtocol.configure { _ in response }
        return MusaeumClient(base: uploadBase, token: "test-token", session: StubURLProtocol.session())
    }

    /// A client that answers one per request, in order — so a case decides what a
    /// *retry* does. `startLoading` logs the request before asking the handler, so
    /// the last entry in the log is the request being answered.
    private nonisolated func stubAnswering(_ responses: [StubURLProtocol.Response]) -> MusaeumClient {
        StubURLProtocol.configure { _ in
            let index = StubURLProtocol.requests.count - 1
            guard responses.indices.contains(index) else {
                return StubURLProtocol.Response(status: 500, body: Data(#"{"error":"internal"}"#.utf8))
            }
            return responses[index]
        }
        return MusaeumClient(base: uploadBase, token: "test-token", session: StubURLProtocol.session())
    }

    /// A client that must not be reached at all: a request that arrives is the
    /// failure this case is about.
    private nonisolated func stubNeverReached() -> MusaeumClient {
        StubURLProtocol.configure { _ in
            XCTFail("nothing should have been sent — the format is not one the contract names")
            return StubURLProtocol.Response(status: 500)
        }
        return MusaeumClient(base: uploadBase, token: "test-token", session: StubURLProtocol.session())
    }

    private nonisolated func created() throws -> StubURLProtocol.Response {
        StubURLProtocol.Response(status: 201, body: try fixture("import"))
    }

    private nonisolated func tooLarge() -> StubURLProtocol.Response {
        StubURLProtocol.Response(status: 413, body: Data(#"{"error":"content too large"}"#.utf8))
    }

    private nonisolated func busy() -> StubURLProtocol.Response {
        StubURLProtocol.Response(
            status: 503,
            headers: ["Retry-After": "1"],
            body: Data(#"{"error":"busy"}"#.utf8)
        )
    }

    /// A picked book, as a path the app can read directly — the shape the probe
    /// uses too, since a `simctl` launch cannot open a security scope. The file
    /// keeps its **own** name (a unique directory holds it), because the name is
    /// what the wire carries as `filename` and what the Mac titles an import by.
    private nonisolated func pickedFile(named name: String, bytes: Int = 4096) throws -> URL {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("musaeum-upload-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(name)
        try Data(repeating: 0x45, count: bytes).write(to: url)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return url
    }

    /// What the app is holding in its own outbox — the staged copies, which is how
    /// R4's shape ("copy into the container, send from there, delete when the send
    /// settles") is decidable without a human.
    private nonisolated func outbox() -> [URL] {
        (try? FileManager.default.contentsOfDirectory(
            at: UploadFile.stagingDirectory(),
            includingPropertiesForKeys: nil
        )) ?? []
    }

    /// The query the wire actually carries.
    private nonisolated func queryItems(_ request: URLRequest) -> [String: String] {
        let items = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
        return Dictionary(items.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { a, _ in a })
    }

    /// The bytes the session read for this request. A file upload reaches a
    /// `URLProtocol` as a **stream**, not as `httpBody` — so a case that read
    /// `httpBody` alone would assert nothing at all, which is exactly the
    /// distinction AC1 is about.
    private nonisolated func sentBytes(_ request: URLRequest) -> Data? {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var collected = Data()
        var buffer = [UInt8](repeating: 0, count: 8192)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: buffer.count)
            if read <= 0 { break }
            collected.append(buffer, count: read)
        }
        return collected
    }

    // MARK: AC1 — the composed request, and the body being the file itself

    /// **Nothing here is an in-memory body.** `httpBody` is `nil` precisely because
    /// the bytes travel as the session's *file*: the alternative — `httpBody` with a
    /// `Data` — reads correctly and dies on the phone with the library's own worst
    /// case (the Mac's census measured a 528 MiB EPUB), which is R1.
    func testTheUploadBodyIsAFileTheSessionReadsRatherThanBytesInMemory() async throws {
        let file = try pickedFile(named: "The Expanse.epub", bytes: 2048)
        let client = stub(try created())

        _ = try await client.uploadBook(file: file, format: "epub", filename: "The Expanse.epub")

        let request = try XCTUnwrap(StubURLProtocol.requests.first)
        XCTAssertNil(request.httpBody, "an in-memory body is the shape that cannot carry a real book")
        XCTAssertNotNil(request.httpBodyStream, "the session reads the file")
        XCTAssertEqual(sentBytes(request)?.count, 2048, "and the bytes it reads are the file's own")
    }

    // MARK: AC5 — the format is the file's own name's answer

    /// The picker's content types are a **filter**; the extension is the answer.
    /// The route trusts `format` and forces the stored extension with it, so a
    /// wrong guess is a row for a book that will not open — and nothing asks the
    /// reader which format their file is.
    func testTheFormatComesFromTheFilesOwnExtension() {
        XCTAssertEqual(UploadFile.format(forFileNamed: "The Expanse.epub"), "epub")
        XCTAssertEqual(UploadFile.format(forFileNamed: "Dune.pdf"), "pdf")
        XCTAssertEqual(UploadFile.format(forFileNamed: "A.mobi"), "mobi")
        XCTAssertEqual(UploadFile.format(forFileNamed: "A.AZW3"), "azw3", "a phone's keyboard is not a contract")

        XCTAssertNil(UploadFile.format(forFileNamed: "notes.txt"))
        XCTAssertNil(UploadFile.format(forFileNamed: "no-extension"))
        XCTAssertNil(UploadFile.format(forFileNamed: "archive.tar.gz"), "`.gz` is not one of the four")
    }

    // MARK: AC3 — the reply, decoded from the document's own block

    func testTheImportPayloadDecodesFromTheVendoredFixture() throws {
        let result = try JSONDecoder().decode(ImportResult.self, from: try fixture("import"))
        XCTAssertEqual(result.book.id, "6f1a1f2e-3c4d-4e5f-8a9b-0c1d2e3f4a5b")
        XCTAssertEqual(result.book.title, "Leviathan Wakes")
        let duplicate = try XCTUnwrap(result.duplicate)
        XCTAssertEqual(duplicate.existingBookId, "a1b2c3d4-0000-4000-8000-000000000001")
        XCTAssertEqual(duplicate.existingTitle, "Leviathan Wakes")
        XCTAssertEqual(duplicate.existingAuthor, "James S. A. Corey")
        XCTAssertEqual(duplicate.matchType, .isbn)
    }

    /// The document's own table: `duplicate` is `null` for the ordinary case, and
    /// `existingAuthor` is `null` when the matched book holds no author — both
    /// **present keys holding `null`**, not absent ones (invariant 4).
    func testTheOrdinaryCaseAndAnAuthorlessMatchBothDecode() throws {
        var ordinary = try JSONSerialization.jsonObject(with: try fixture("import")) as! [String: Any]
        ordinary["duplicate"] = NSNull()
        let noMatch = try JSONDecoder().decode(
            ImportResult.self,
            from: try JSONSerialization.data(withJSONObject: ordinary)
        )
        XCTAssertNil(noMatch.duplicate, "an upload that matched nothing is the ordinary case")
        XCTAssertEqual(noMatch.book.title, "Leviathan Wakes")

        var authorless = try JSONSerialization.jsonObject(with: try fixture("import")) as! [String: Any]
        var match = authorless["duplicate"] as! [String: Any]
        match["existingAuthor"] = NSNull()
        authorless["duplicate"] = match
        let decoded = try JSONDecoder().decode(
            ImportResult.self,
            from: try JSONSerialization.data(withJSONObject: authorless)
        )
        XCTAssertNil(decoded.duplicate?.existingAuthor)
        XCTAssertEqual(
            decoded.duplicate?.matchType,
            .isbn,
            "an authorless match still names what it matched — the whole 201 must not be lost over it"
        )
    }

    /// The strictness that makes the two cases above worth having: a member the
    /// contract calls always-present must **throw** when it goes missing rather
    /// than decode to `nil`.
    ///
    /// The refusal arrives **wrapped in the member that holds it** — a nested
    /// `StrictObject` answers *"import.book is not the shape the contract names"*
    /// and its message still names the member that is absent. That is how this
    /// model's nesting has always reported a nested breach (`ContractDecodeTests`
    /// decodes a book bare, so it sees the bare case), and it is recorded here
    /// rather than changed in this slice: the decidable half is that it *throws*,
    /// because the alternative — a silent `nil` title — is the drift invariant 4
    /// exists to catch.
    func testAMissingMemberInTheImportPayloadIsRefused() throws {
        var object = try JSONSerialization.jsonObject(with: try fixture("import")) as! [String: Any]
        var book = object["book"] as! [String: Any]
        book.removeValue(forKey: "title")
        object["book"] = book

        XCTAssertThrowsError(
            try JSONDecoder().decode(ImportResult.self, from: try JSONSerialization.data(withJSONObject: object))
        ) { error in
            guard let breach = error as? ContractError else {
                return XCTFail("expected a contract refusal, got \(error)")
            }
            XCTAssertTrue(breach.description.contains("book.title"), breach.description)
            XCTAssertTrue(breach.description.contains("absent"), breach.description)
        }
    }

    // MARK: AC2/AC4 — the refusal classes, derived rather than asserted

    /// **The 413's client-side half, and the reason the mapping exists.** Before
    /// `mapStatus` had a `413` case the status fell to `default` → `unreachable`,
    /// which is *retryable*: an oversized book was reported as *the Mac is not
    /// answering* and then sent again, indefinitely, on a file that can never fit.
    func testTooLargeIsTheBooksOwnProblemAndNeverAWorthWaitingOne() {
        XCTAssertEqual(Refusal.from(.tooLarge).kind, .thisBook)
        XCTAssertEqual(Refusal.from(.badRequest("no filename")).kind, .thisBook)

        XCTAssertEqual(Refusal.from(.busy(retryAfter: 1)).kind, .waitAndTry)
        XCTAssertEqual(Refusal.from(.libraryOffline(retryAfter: 5)).kind, .waitAndTry)
        XCTAssertEqual(Refusal.from(.unreachable("the Mac is not answering")).kind, .waitAndTry)
        XCTAssertEqual(Refusal.from(.unauthorized).kind, .credential)
        XCTAssertEqual(Refusal.from(.server).kind, .other)

        XCTAssertTrue(
            Refusal.from(.tooLarge).message.contains("content too large"),
            "the row's words are the contract's own (the document's 413 word)"
        )
    }

    // MARK: AC6 — the claim, and the row, decided at the model

    /// **Nothing may call the book present before the `201`.** A request that was
    /// sent is not a book that arrived, and a 413 is the case where the difference
    /// is a lie the reader would act on.
    func testAnOversizedBookIsRefusedAndNeverClaimedAndNotSentAgain() async throws {
        let file = try pickedFile(named: "huge.epub")
        let model = UploadModel()
        let client = stub(tooLarge())

        await model.send(file: file, to: client)

        XCTAssertFalse(model.claimsBookIsInLibrary, "the Mac refused it — nothing arrived")
        XCTAssertFalse(model.offersRetry, "the same bytes cannot fit on a second attempt")
        XCTAssertFalse(model.offersReconnect)
        XCTAssertEqual(StubURLProtocol.requests.count, 1, "a 413 is not retried")
        XCTAssertEqual(model.message, ClientError.tooLarge.description)
        XCTAssertEqual(outbox().count, 0, "a refused upload leaves no copy of the book behind")
    }

    func testABookTheMacCreatedIsTheOnlyThingThatClaimsTheLibrary() async throws {
        let file = try pickedFile(named: "Leviathan Wakes.epub")
        let model = UploadModel()
        let client = stub(try created())

        XCTAssertFalse(model.claimsBookIsInLibrary, "nothing is claimed before a send")

        await model.send(file: file, to: client)

        XCTAssertTrue(model.claimsBookIsInLibrary)
        XCTAssertFalse(model.offersRetry)
        XCTAssertEqual(model.title, "Sent — and you already had it", "the payload's duplicate is what the Mac answered")
        XCTAssertTrue(model.message.contains("Leviathan Wakes"))
        XCTAssertEqual(outbox().count, 0, "the copy goes when its send settles")
    }

    /// A book that matched nothing says so differently from one that collided, and
    /// both are the Mac's answer rather than the app's guess.
    func testAnUploadThatMatchedNothingSaysSoWithoutNamingAMatch() async throws {
        var object = try JSONSerialization.jsonObject(with: try fixture("import")) as! [String: Any]
        object["duplicate"] = NSNull()
        let payload = try JSONSerialization.data(withJSONObject: object)

        let file = try pickedFile(named: "Fresh.epub")
        let model = UploadModel()
        let client = stub(StubURLProtocol.Response(status: 201, body: payload))

        await model.send(file: file, to: client)

        XCTAssertTrue(model.claimsBookIsInLibrary)
        XCTAssertEqual(model.title, "Sent to the library")
        XCTAssertFalse(model.message.contains("already"), "no collision, no collision sentence")
    }

    /// A Mac that is busy is worth waiting out, and the **copy is kept** so that
    /// *Try again* can send the same bytes: by the time a reader taps it, the
    /// picked file's security scope is long closed.
    func testABusyMacIsOfferedARetryAndTheCopyIsKeptForIt() async throws {
        let file = try pickedFile(named: "Leviathan Wakes.epub")
        let model = UploadModel()
        let client = stubAnswering([busy(), try created()])

        await model.send(file: file, to: client)
        XCTAssertFalse(model.claimsBookIsInLibrary)
        XCTAssertTrue(model.offersRetry, "503 busy is retried by the contract's own rule")
        XCTAssertEqual(outbox().count, 1, "the bytes stay, because trying again is the right thing to offer")

        await model.retry(to: client)
        XCTAssertTrue(model.claimsBookIsInLibrary, "the retry sent the kept copy")
        XCTAssertEqual(StubURLProtocol.requests.count, 2)
        XCTAssertEqual(queryItems(StubURLProtocol.requests[1])["filename"], "Leviathan Wakes.epub")
        XCTAssertEqual(outbox().count, 0, "and the copy goes with it")
    }

    /// A credential problem is its own class, and its control is the way back to
    /// the surface that edits the token — this app has no Settings screen of its
    /// own, and a 401 arrives while it *is* configured.
    func testARefusedTokenIsItsOwnClassAndOffersTheWayBackToTheConnectScreen() async throws {
        let file = try pickedFile(named: "Leviathan Wakes.epub")
        let model = UploadModel()
        let client = stub(StubURLProtocol.Response(
            status: 401,
            headers: ["WWW-Authenticate": "Bearer"],
            body: Data(#"{"error":"unauthorized"}"#.utf8)
        ))

        await model.send(file: file, to: client)

        XCTAssertFalse(model.claimsBookIsInLibrary)
        XCTAssertTrue(model.offersReconnect)
        XCTAssertFalse(model.offersRetry, "a retry with the same token is the same 401")
        XCTAssertEqual(outbox().count, 0)
    }

    /// A file the contract has no format for never reaches the wire: this route has
    /// no book to look up yet, so the answer would be a `400` — and a row for a book
    /// that cannot open.
    func testAFileWithNoFormatTheContractNamesIsRefusedWithoutAskingTheMac() async throws {
        let file = try pickedFile(named: "notes.txt")
        let model = UploadModel()
        let client = stubNeverReached()

        await model.send(file: file, to: client)

        XCTAssertFalse(model.claimsBookIsInLibrary)
        XCTAssertTrue(StubURLProtocol.requests.isEmpty)
        XCTAssertEqual(model.refusal?.kind, .thisBook)
        XCTAssertFalse(model.offersRetry)
        XCTAssertEqual(outbox().count, 0)
    }

    /// A picker that was dismissed is a reader changing their mind, not a failure —
    /// and a state machine that reported it would put an error over a screen the
    /// reader has just closed.
    func testACancelledPickerIsNotARefusal() {
        let model = UploadModel()
        model.pickingFailed(NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError))
        XCTAssertNil(model.outcome)
        XCTAssertEqual(model.phase, .idle)
    }
}
