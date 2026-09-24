import XCTest

@testable import Musaeum

/// The hand-off — "Copy to Musaeum" from Files, Safari or Mail.
///
/// Four states a share can arrive in, and the one safety property that keeps this
/// app inside its own container. `UploadInbox`'s rules are pure over a URL and a
/// directory, so all of it is decidable here rather than by sharing something and
/// watching.
final class UploadInboxTests: XCTestCase {
    private var container: URL!

    override func setUpWithError() throws {
        container = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("musaeum-inbox-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: UploadInbox.directory(container: container),
            withIntermediateDirectories: true
        )
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: container)
    }

    private func handOver(_ name: String, bytes: Int = 1024) throws -> URL {
        let url = UploadInbox.directory(container: container).appendingPathComponent(name)
        try Data(repeating: 0x45, count: bytes).write(to: url)
        return url
    }

    // MARK: what the system left

    func testABookTheSystemHandedOverIsTaken() throws {
        let url = try handOver("Leviathan Wakes.epub")
        guard case let .success(file) = UploadInbox.incoming(url) else {
            return XCTFail("a book in the app's own Inbox is what a share delivers")
        }
        XCTAssertEqual(file, url)
        XCTAssertEqual(UploadFile.format(for: file), "epub", "the extension is still what decides the format")
    }

    /// The system's directory holds whatever a share ever handed over, including
    /// things that are not books — and a sweep that announced a refusal for those
    /// would be refusing something the reader never chose.
    func testAFileThisAppWillNotSendIsRefusedByNameAndNotPutInTheSweep() throws {
        let notes = try handOver("notes.txt")
        guard case let .failure(refusal) = UploadInbox.incoming(notes) else {
            return XCTFail("a .txt is not a book this app sends")
        }
        XCTAssertEqual(refusal.kind, .thisBook)
        XCTAssertTrue(refusal.message.contains("notes.txt"))

        XCTAssertEqual(UploadInbox.pending(container: container), [], "the sweep only takes books")
    }

    func testAFileThatIsAlreadyGoneIsRefusedWithoutCrashing() {
        let gone = UploadInbox.directory(container: container).appendingPathComponent("Gone.epub")
        guard case let .failure(refusal) = UploadInbox.incoming(gone) else {
            return XCTFail("a share whose file is gone is a state to report, not to work around")
        }
        XCTAssertEqual(refusal.kind, .thisBook)
    }

    /// A directory named like a book is not a book, and the rule that reads it says
    /// so rather than handing the copy a path that cannot be read.
    func testADirectoryNamedLikeABookIsRefused() throws {
        let directory = UploadInbox.directory(container: container).appendingPathComponent("NotABook.epub")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        guard case let .failure(refusal) = UploadInbox.incoming(directory) else {
            return XCTFail("a directory is not a book, whatever it is called")
        }
        XCTAssertEqual(refusal.kind, .thisBook)
        XCTAssertEqual(UploadInbox.pending(container: container), [], "and the sweep leaves it alone")
    }

    // MARK: and what the sweep finds

    /// **A share that arrives while the app is not configured — or is not running
    /// at all — is not lost.** The file is in this app's own container, so the next
    /// time the library screen appears the sweep takes it; nothing has to be
    /// remembered between launches, and nothing is sent before the app knows where
    /// to send it.
    func testAShareThatArrivesBeforeTheAppCanSendItIsStillThereAfterARelaunch() throws {
        let book = try handOver("Arrived Early.epub")
        _ = try handOver("notes.txt")
        try FileManager.default.createDirectory(
            at: UploadInbox.directory(container: container).appendingPathComponent("A Directory.epub"),
            withIntermediateDirectories: true
        )

        // A relaunch is nothing but asking again.
        XCTAssertEqual(
            UploadInbox.pending(container: container),
            [book],
            "one book, in name order, and the things that are not books are left where they are"
        )
    }

    func testTheSweepIsInNameOrderSoAMultiBookRunIsRepeatable() throws {
        let second = try handOver("b.epub")
        let first = try handOver("a.pdf")
        let third = try handOver("c.mobi")
        _ = second
        _ = third
        XCTAssertEqual(
            UploadInbox.pending(container: container).map(\.lastPathComponent),
            ["a.pdf", "b.epub", "c.mobi"]
        )
        _ = first
    }

    // MARK: the boundary

    /// **This app deletes only from its own Inbox.** The URL comes from the system
    /// and is normally ours, but a URL that is not in the Inbox belongs to
    /// something else — and a hand-off that reached outside this app's container
    /// would be the one place in this client that could delete another app's file.
    func testTheSystemsCopyGoesOnlyFromThisAppsOwnInbox() throws {
        let inboxFile = try handOver("Taken.epub")
        let outside = container.appendingPathComponent("Somewhere Else.epub")
        try Data(repeating: 0x45, count: 16).write(to: outside)

        UploadInbox.discard(inboxFile, container: container)
        UploadInbox.discard(outside, container: container)

        XCTAssertFalse(FileManager.default.fileExists(atPath: inboxFile.path), "the copy taken is deleted")
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: outside.path),
            "a file that is not this app's Inbox copy is not this app's to delete"
        )
    }
}
