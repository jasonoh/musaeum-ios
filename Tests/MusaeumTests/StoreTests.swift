import XCTest

@testable import Musaeum

/// The local half of the app: what it keeps when the Mac is not there. Each of
/// these runs against a temporary directory, so a case never touches the real
/// container.
@MainActor
final class StoreTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("musaeum-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func book(id: String = "6f1a1f2e-3c4d-4e5f-8a9b-0c1d2e3f4a5b") throws -> (ContractBook, Data) {
        let bundle = Bundle(for: StoreTests.self)
        let url = try XCTUnwrap(bundle.url(forResource: "book", withExtension: "json"))
        let payload = try Data(contentsOf: url)
        return (try JSONDecoder().decode(ContractBook.self, from: payload), payload)
    }

    // MARK: DownloadStore — the shelf that works with the Mac asleep (AC8)

    func testADownloadLandsOnDiskAndIsListed() throws {
        let store = DownloadStore(root: root)
        let (book, payload) = try book()
        let temporary = root.appendingPathComponent("incoming.epub")
        try Data(repeating: 0x41, count: 2_048).write(to: temporary)

        let record = try store.adopt(
            temporaryFile: temporary,
            payload: payload,
            book: book,
            format: "epub",
            cover: Data([0xFF, 0xD8, 0xFF])
        )

        XCTAssertTrue(store.isDownloaded(book.id))
        XCTAssertEqual(record.bytes, 2_048)
        XCTAssertEqual(record.fileName, "\(book.id).epub", "the local name is the id and the served format — the wire carries no path")
        let file = try XCTUnwrap(store.fileURL(for: book.id))
        XCTAssertEqual(try Data(contentsOf: file).count, 2_048)
        XCTAssertEqual(store.coverData(for: book.id), Data([0xFF, 0xD8, 0xFF]))
        XCTAssertFalse(FileManager.default.fileExists(atPath: temporary.path), "the temporary file was moved, not copied")
    }

    /// The payload is stored exactly as the server sent it and read back through
    /// the strict decoder, so a record that no longer matches the contract is
    /// visible rather than silently half-mapped.
    func testTheStoredPayloadDecodesBackThroughTheContract() throws {
        let store = DownloadStore(root: root)
        let (book, payload) = try book()
        let temporary = root.appendingPathComponent("incoming.epub")
        try Data([0x41]).write(to: temporary)
        try store.adopt(temporaryFile: temporary, payload: payload, book: book, format: "epub")

        let record = try XCTUnwrap(store.downloaded(book.id))
        XCTAssertEqual(try record.book(), book)
    }

    func testARecordSurvivesARestartAndRemovalTakesEverything() throws {
        let store = DownloadStore(root: root)
        let (book, payload) = try book()
        let temporary = root.appendingPathComponent("incoming.epub")
        try Data([0x41]).write(to: temporary)
        try store.adopt(temporaryFile: temporary, payload: payload, book: book, format: "epub", cover: Data([0xFF]))

        // A second store over the same root is what a relaunch looks like.
        let reopened = DownloadStore(root: root)
        XCTAssertTrue(reopened.isDownloaded(book.id))
        let file = try XCTUnwrap(reopened.fileURL(for: book.id))

        try reopened.remove(id: book.id)
        XCTAssertFalse(reopened.isDownloaded(book.id))
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        XCTAssertNil(reopened.coverData(for: book.id))
        XCTAssertFalse(DownloadStore(root: root).isDownloaded(book.id))
    }

    // MARK: LocalPositions — the phone's own precise place (CD5)

    func testAPositionIsRecordedAndReadBackAcrossARestart() {
        let positions = LocalPositions(root: root)
        positions.record(bookId: "abc", fraction: 0.42, locatorJSON: #"{"href":"x"}"#)
        XCTAssertEqual(positions.fraction(for: "abc"), 0.42)

        let reopened = LocalPositions(root: root)
        XCTAssertEqual(reopened.position(for: "abc")?.fraction, 0.42)
        XCTAssertEqual(reopened.position(for: "abc")?.locatorJSON, #"{"href":"x"}"#)
        XCTAssertNil(reopened.position(for: "never-opened"))
    }

    // MARK: the base URL a human types (a phone keyboard is not a URL parser)

    func testBaseURLNormalisation() {
        XCTAssertEqual(SettingsStore.normalizeBase("100.64.0.1:8788"), "http://100.64.0.1:8788")
        XCTAssertEqual(SettingsStore.normalizeBase("  http://100.64.0.1:8788/  "), "http://100.64.0.1:8788")
        XCTAssertEqual(SettingsStore.normalizeBase("http://localhost:8788///"), "http://localhost:8788")
        XCTAssertEqual(SettingsStore.normalizeBase("http://[fd7a::1]:8788"), "http://[fd7a::1]:8788")
        XCTAssertNil(SettingsStore.normalizeBase(""))
        XCTAssertNil(SettingsStore.normalizeBase("   "))
        XCTAssertNil(SettingsStore.normalizeBase("not a url"))
    }

    func testSettingsRoundTripThroughTheStore() {
        let defaults = UserDefaults(suiteName: "musaeum-tests-\(UUID().uuidString)")!
        let settings = SettingsStore(defaults: defaults, keychain: KeychainStore(service: "dev.jasonoh.Musaeum.tests"))
        settings.save(base: "100.64.0.1:8788", token: "secret-token")
        XCTAssertTrue(settings.isConfigured)
        XCTAssertEqual(settings.baseURL?.absoluteString, "http://100.64.0.1:8788")
        settings.clear()
        XCTAssertFalse(settings.isConfigured)
        XCTAssertEqual(settings.token, "")
    }
}
