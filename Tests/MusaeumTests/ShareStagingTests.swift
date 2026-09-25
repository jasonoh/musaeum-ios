import XCTest

@testable import Musaeum

/// **What leaves the phone when a book is shared, under what name.**
///
/// The rule is `ShareStaging`; the composition is the store's. Each case runs
/// against a temporary directory, so none of them touches the real container.
@MainActor
final class ShareStagingTests: XCTestCase {
    private var root: URL!
    private var staging: URL!

    override func setUpWithError() throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("musaeum-share-tests-\(UUID().uuidString)", isDirectory: true)
        staging = ShareStaging.directory(in: root)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func book() throws -> (ContractBook, Data) {
        let bundle = Bundle(for: ShareStagingTests.self)
        let url = try XCTUnwrap(bundle.url(forResource: "book", withExtension: "json"))
        let payload = try Data(contentsOf: url)
        return (try JSONDecoder().decode(ContractBook.self, from: payload), payload)
    }

    /// A store holding one download, with `bytes` in its file.
    private func store(holding book: ContractBook, payload: Data, format: String = "epub") throws -> DownloadStore {
        let store = DownloadStore(root: root)
        let incoming = root.appendingPathComponent("incoming.\(format)")
        try Data(repeating: 0x41, count: 2_048).write(to: incoming)
        try store.adopt(temporaryFile: incoming, payload: payload, book: book, format: format)
        return store
    }

    // MARK: The name (AC1, AC2)

    func testTheNameIsTheTitleTheAuthorAndTheStoredExtension() throws {
        let (book, _) = try book()
        let name = ShareStaging.fileName(
            title: book.title,
            author: book.author,
            format: "epub",
            fallback: book.id
        )

        XCTAssertEqual(name, "Leviathan Wakes - James S. A. Corey.epub")
    }

    /// A book with no author is named by its title alone — never `Title - .epub`.
    func testABookWithNoAuthorLosesTheBylineRatherThanTheSeparator() throws {
        let (book, _) = try book()
        XCTAssertEqual(
            ShareStaging.fileName(title: book.title, author: nil, format: "epub", fallback: book.id),
            "Leviathan Wakes.epub"
        )
        XCTAssertEqual(
            ShareStaging.fileName(title: book.title, author: "   ", format: "epub", fallback: book.id),
            "Leviathan Wakes.epub",
            "an author that is only whitespace is no byline at all"
        )
    }

    /// `/` reads as a path separator and macOS shows `:` as a slash, so neither
    /// belongs in a name handed to another machine.
    func testAPathSeparatorAndAColonAreRemovedRatherThanSplitIntoFolders() {
        XCTAssertEqual(
            ShareStaging.fileName(title: "Notes/2020: a year", author: nil, format: "pdf", fallback: "id"),
            "Notes 2020 a year.pdf"
        )
    }

    /// A newline or a control character survives a share and comes out as
    /// something else on the other side, in whichever list the recipient sees.
    func testANewlineOrAControlCharacterNeverReachesTheName() {
        XCTAssertEqual(
            ShareStaging.fileName(title: "Two\nLines\u{0007}Now", author: nil, format: "epub", fallback: "id"),
            "Two Lines Now.epub"
        )
    }

    /// A name that begins with a dot is a hidden file wherever it lands.
    func testANameThatWouldBeHiddenIsMadeVisible() {
        XCTAssertEqual(
            ShareStaging.fileName(title: ".NET Internals", author: nil, format: "epub", fallback: "id"),
            "_NET Internals.epub"
        )
    }

    /// A share called `.epub` is a share the recipient cannot do anything with,
    /// so a title with nothing in it falls back to the book's own id.
    func testATitleWithNothingInItFallsBackToTheId() throws {
        let (book, _) = try book()
        let name = ShareStaging.fileName(title: "  \n\t ", author: nil, format: "epub", fallback: book.id)

        XCTAssertEqual(name, "\(book.id).epub")
        XCTAssertNotEqual(name, ".epub")
    }

    /// An id that sanitises away is still not a name, and a name is required: a
    /// fixed word is the last resort, and the extension is what the *file* is.
    func testAnIdThatSanitisesToNothingStillMakesAName() {
        XCTAssertEqual(
            ShareStaging.fileName(title: "///", author: nil, format: "epub", fallback: "///"),
            "book.epub"
        )
    }

    /// **Clipped by bytes, not characters.** A filesystem name is capped at 255
    /// bytes; 100 emoji is 100 characters and 400 bytes, so clipping by character
    /// count would produce a name the filesystem refuses — for exactly the titles
    /// most likely to carry emoji.
    func testALongTitleIsClippedByBytesAndNotByCharacters() {
        let title = String(repeating: "📚", count: 100)
        let name = ShareStaging.fileName(title: title, author: nil, format: "epub", fallback: "id")
        let stem = String(name.dropLast(".epub".count))

        XCTAssertLessThanOrEqual(name.utf8.count, ShareStaging.stemByteLimit + 5)
        XCTAssertEqual(stem.count, ShareStaging.stemByteLimit / 4, "45 four-byte characters is exactly the limit")
        XCTAssertEqual(stem, String(repeating: "📚", count: stem.count), "clipped on a character boundary, never mid-scalar")
        XCTAssertTrue(name.hasSuffix(".epub"), "the extension is not what gets clipped")
    }

    func testATitleInsideTheLimitIsLeftExactlyAsItIs() throws {
        let (book, _) = try book()
        let stem = String(book.title.prefix(ShareStaging.stemByteLimit))
        XCTAssertEqual(ShareStaging.safeStem(stem), stem)
    }

    // MARK: The copy (AC3, AC4)

    /// Both files are in the app's own container, so a link is the common case —
    /// and it is what makes sharing a 528 MiB book free rather than a second
    /// 528 MiB write. The claim is checked by identity, not by the rule's own
    /// word: one file, two names.
    func testTheStagedFileIsTheSameFileWhenTheFilesystemTakesALink() throws {
        let source = root.appendingPathComponent("download.epub")
        try Data(repeating: 0x42, count: 4_096).write(to: source)

        let staged = try ShareStaging.stage(source: source, named: "Book.epub", into: staging)

        XCTAssertTrue(staged.linked)
        XCTAssertEqual(try Data(contentsOf: staged.url), try Data(contentsOf: source))
        XCTAssertEqual(try identifier(of: staged.url), try identifier(of: source))
    }

    /// **The fallback is a rule, not a branch only a full disk reaches.** The
    /// linker is a seam precisely so this is decidable: `stage` sweeps its own
    /// directory, so a second real refusal cannot be produced from here.
    func testALinkTheFilesystemRefusesFallsBackToACopy() throws {
        struct Refused: Error {}
        let source = root.appendingPathComponent("download.epub")
        try Data(repeating: 0x43, count: 4_096).write(to: source)

        let staged = try ShareStaging.stage(
            source: source,
            named: "Book.epub",
            into: staging,
            linker: { _, _ in throw Refused() }
        )

        XCTAssertFalse(staged.linked)
        XCTAssertEqual(try Data(contentsOf: staged.url), try Data(contentsOf: source))
        XCTAssertNotEqual(
            try identifier(of: staged.url),
            try identifier(of: source),
            "a copy is a second file, which is the one thing a link is not"
        )
    }

    /// At most one staged share exists at a time, so a name can never collide
    /// with a book that has already been sent.
    func testAStageSweepsWhatTheLastOneLeft() throws {
        let first = root.appendingPathComponent("first.epub")
        let second = root.appendingPathComponent("second.epub")
        try Data([0x01]).write(to: first)
        try Data([0x02]).write(to: second)

        let one = try ShareStaging.stage(source: first, named: "One.epub", into: staging)
        let two = try ShareStaging.stage(source: second, named: "Two.epub", into: staging)

        XCTAssertFalse(FileManager.default.fileExists(atPath: one.url.path))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: staging.path), ["Two.epub"])
        XCTAssertEqual(try Data(contentsOf: two.url), Data([0x02]))
    }

    func testASweepLeavesNothingBehind() throws {
        let source = root.appendingPathComponent("download.epub")
        try Data([0x01]).write(to: source)
        _ = try ShareStaging.stage(source: source, named: "Book.epub", into: staging)

        ShareStaging.sweep(staging)

        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: staging.path), [])
    }

    // MARK: The store's composition (AC5, AC6)

    /// The extension is the **stored file's** own, not the contract's first
    /// preference: the share carries the file the phone holds.
    func testTheShareCarriesTheExtensionOfTheFileThePhoneHolds() throws {
        let (book, payload) = try book()
        let store = try store(holding: book, payload: payload, format: "mobi")

        let staged = try XCTUnwrap(try store.stagedForSharing(book))

        XCTAssertEqual(staged.url.lastPathComponent, "Leviathan Wakes - James S. A. Corey.mobi")
        XCTAssertTrue(staged.url.path.hasPrefix(staging.path), "a staged share lives beside the books it is copied from")
    }

    /// The download keeps its own name — the staged copy is a *second* name in a
    /// scratch directory, never a rename of the stored file.
    func testStagingRenamesNothing() throws {
        let (book, payload) = try book()
        let store = try store(holding: book, payload: payload)

        _ = try store.stagedForSharing(book)

        XCTAssertEqual(try store.fileURL(for: book.id)?.lastPathComponent, "\(book.id).epub")
    }

    /// The door does not exist for a book this phone holds no file for — and the
    /// shelf it is decided against is **not empty**, so what this decides is the
    /// book's own identity rather than an empty store. (The other half of the same
    /// condition — a record whose file has gone — is the case below.)
    func testABookThePhoneHoldsNoCopyOfStagesNothing() throws {
        let (book, payload) = try book()
        let store = try store(holding: book, payload: payload)
        let text = try XCTUnwrap(String(data: payload, encoding: .utf8))
        let other = try JSONDecoder().decode(
            ContractBook.self,
            from: try XCTUnwrap(
                text.replacingOccurrences(of: book.id, with: "00000000-0000-0000-0000-000000000000")
                    .data(using: .utf8)
            )
        )

        XCTAssertNotEqual(other.id, book.id)
        XCTAssertNil(try store.stagedForSharing(other), "the door does not exist for a book with no file")
    }

    /// A record whose file was deleted from under it stages nothing rather than
    /// throwing a path that is not there.
    func testARecordWhoseFileIsGoneStagesNothing() throws {
        let (book, payload) = try book()
        let store = try store(holding: book, payload: payload)
        try FileManager.default.removeItem(at: try XCTUnwrap(store.fileURL(for: book.id)))

        XCTAssertNil(try store.stagedForSharing(book))
    }

    func testNothingIsStagedUntilAShareAsksForIt() throws {
        let (book, payload) = try book()
        let store = try store(holding: book, payload: payload)

        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(atPath: staging.path),
            [],
            "the shelf and the detail are on screen with nothing staged"
        )

        _ = try store.stagedForSharing(book)
        store.sweepStaging()

        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: staging.path), [])
    }

    /// **A share the OS killed mid-flight leaves its copy behind** — the dismissal
    /// never ran, so nothing swept it. The next launch is the only place that can
    /// notice, which is why the store sweeps at init rather than only on dismissal.
    func testAShareLeftByAKilledAppIsSweptAtTheNextLaunch() throws {
        let (book, payload) = try book()
        let store = try store(holding: book, payload: payload)
        _ = try store.stagedForSharing(book)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: staging.path).count, 1)

        _ = DownloadStore(root: root) // the next launch, over the same container

        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: staging.path), [])
        XCTAssertNotNil(store.fileURL(for: book.id), "the sweep takes the staged copy, never the download")
    }

    private func identifier(of url: URL) throws -> NSObject {
        let values = try url.resourceValues(forKeys: [.fileResourceIdentifierKey])
        return try XCTUnwrap(values.fileResourceIdentifier as? NSObject, "the filesystem gave no identifier for \(url.path)")
    }
}
