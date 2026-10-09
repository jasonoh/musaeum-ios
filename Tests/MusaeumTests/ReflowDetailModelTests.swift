import XCTest

@testable import Musaeum

/// The detail screen's reflow path: a PDF-only book downloads as the EPUB the Mac
/// lays out, shows the pass's progress, and adopts nothing unless the 200's file
/// arrived. `pause` is injected, so no case waits on a clock.
@MainActor
final class ReflowDetailModelTests: XCTestCase {
    private let base = URL(string: "http://100.64.0.1:8788")!
    private let epub = Data([0x50, 0x4B, 0x03, 0x04, 0xCA, 0xFE, 0xBA, 0xBE])
    private var roots: [URL] = []

    override func tearDown() {
        for root in roots { try? FileManager.default.removeItem(at: root) }
        roots = []
        super.tearDown()
    }

    private final class Recorder<T: Sendable>: @unchecked Sendable {
        private let lock = NSLock()
        private var items: [T] = []
        func add(_ item: T) { lock.lock(); items.append(item); lock.unlock() }
        var all: [T] { lock.lock(); defer { lock.unlock() }; return items }
    }

    private final class Switch: @unchecked Sendable {
        private let lock = NSLock()
        private var on = false
        func flip() { lock.lock(); on = true; lock.unlock() }
        var isOn: Bool { lock.lock(); defer { lock.unlock() }; return on }
    }

    private final class Box: @unchecked Sendable {
        @MainActor var model: BookDetailModel?
    }

    private func bookJSON(formats: String, available: Bool) throws -> Data {
        let bundle = Bundle(for: ReflowDetailModelTests.self)
        let url = try XCTUnwrap(bundle.url(forResource: "book", withExtension: "json"))
        var text = try String(contentsOf: url, encoding: .utf8)
        text = text.replacingOccurrences(of: #""formats": ["epub", "mobi"]"#, with: #""formats": \#(formats)"#)
        text = text.replacingOccurrences(of: #""available": false"#, with: #""available": \#(available)"#)
        return Data(text.utf8)
    }

    private func decode(_ data: Data) throws -> ContractBook {
        try JSONDecoder().decode(ContractBook.self, from: data)
    }

    private func store() -> DownloadStore {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("reflow-detail-\(UUID().uuidString)")
        roots.append(root)
        return DownloadStore(root: root)
    }

    private func model(
        _ downloads: DownloadStore,
        pause: @escaping @Sendable (Duration) async throws -> Void = { _ in },
        _ handler: @escaping (URLRequest) -> StubURLProtocol.Response
    ) -> BookDetailModel {
        StubURLProtocol.configure(handler)
        let client = MusaeumClient(base: base, token: "test-token", session: StubURLProtocol.session())
        return BookDetailModel(client: client, downloads: downloads, pause: pause)
    }

    private func progress(_ phase: String, _ completed: Int, _ total: Int) -> StubURLProtocol.Response {
        .init(status: 202, headers: ["Retry-After": "2"],
              body: Data(#"{"phase":"\#(phase)","completed":\#(completed),"total":\#(total)}"#.utf8))
    }

    private func isReflow(_ request: URLRequest) -> Bool { request.url?.query == "format=reflow" }

    func testAReflowDownloadIsAdoptedAsAnEpub() async throws {
        let body = try bookJSON(formats: #"["pdf"]"#, available: true)
        let book = try decode(body)
        let downloads = store()
        let sent = Recorder<Int>()
        let model = model(downloads) { request in
            if request.url?.path.hasSuffix("/file") == true {
                sent.add(1)
                return sent.all.count == 1 ? self.progress("layout", 1, 24) : .init(status: 200, body: self.epub)
            }
            if request.url?.path.hasSuffix("/cover") == true { return .init(status: 404) }
            return .init(status: 200, body: body)
        }

        await model.download(book)

        XCTAssertEqual(model.transfer, .done)
        let url = try XCTUnwrap(downloads.fileURL(for: book.id))
        XCTAssertEqual(url.lastPathComponent, "\(book.id).epub")
        XCTAssertEqual(try Data(contentsOf: url), epub)
        XCTAssertTrue(try XCTUnwrap(downloads.downloaded(book.id)).fileName.hasSuffix(".epub"))
        let stored = try decode(try XCTUnwrap(downloads.downloaded(book.id)).payload)
        XCTAssertTrue(stored.reflow.available)
    }

    func testProgressIsVisibleWhileThePassRuns() async throws {
        let body = try bookJSON(formats: #"["pdf"]"#, available: true)
        let book = try decode(body)
        let box = Box()
        let observed = Recorder<BookDetailModel.Transfer>()
        let count = Recorder<Int>()
        let model = model(
            store(),
            pause: { _ in await MainActor.run { if let t = box.model?.transfer { observed.add(t) } } }
        ) { request in
            if request.url?.path.hasSuffix("/file") == true {
                count.add(1)
                return count.all.count == 1 ? self.progress("layout", 12, 24) : .init(status: 200, body: self.epub)
            }
            return request.url?.path.hasSuffix("/cover") == true ? .init(status: 404) : .init(status: 200, body: body)
        }
        box.model = model

        await model.download(book)

        XCTAssertTrue(observed.all.contains(.preparing(ReflowProgress(phase: "layout", completed: 12, total: 24))))
        XCTAssertEqual(model.transfer, .done)
    }

    func testARefusedBookIsNotAdoptedAndSaysWhy() async throws {
        let body = try bookJSON(formats: #"["pdf"]"#, available: true)
        let book = try decode(body)
        let downloads = store()
        let model = model(downloads) { request in
            if request.url?.path.hasSuffix("/file") == true {
                return .init(status: 422, body: Data(#"{"error":"cannot reflow","reason":"scanned pages with no text"}"#.utf8))
            }
            return request.url?.path.hasSuffix("/cover") == true ? .init(status: 404) : .init(status: 200, body: body)
        }

        await model.download(book)

        guard case let .failed(message) = model.transfer else { return XCTFail("expected failed, got \(model.transfer)") }
        XCTAssertTrue(message.contains("scanned pages with no text"), message)
        XCTAssertFalse(downloads.isDownloaded(book.id))
        let books = downloads.fileURL(for: book.id)
        XCTAssertNil(books)
        let staged = try FileManager.default.contentsOfDirectory(
            at: roots[0].appendingPathComponent("Books"), includingPropertiesForKeys: nil)
        XCTAssertEqual(staged, [])
    }

    func testAnOrdinaryBookStillDownloadsItsFirstFormat() async throws {
        let body = try bookJSON(formats: #"["epub", "pdf"]"#, available: false)
        let book = try decode(body)
        let downloads = store()
        let model = model(downloads) { request in
            if request.url?.path.hasSuffix("/file") == true { return .init(status: 200, body: self.epub) }
            return request.url?.path.hasSuffix("/cover") == true ? .init(status: 404) : .init(status: 200, body: body)
        }

        await model.download(book)

        XCTAssertEqual(model.transfer, .done)
        let files = StubURLProtocol.requests.filter { $0.url?.path.hasSuffix("/file") == true }
        XCTAssertEqual(files.count, 1)
        XCTAssertEqual(files.first?.url?.query, "format=epub")
        XCTAssertFalse(StubURLProtocol.requests.contains(where: isReflow))
        XCTAssertEqual(downloads.fileURL(for: book.id)?.lastPathComponent, "\(book.id).epub")
    }

    func testTheMacDroppingMidPassAdoptsNothing() async throws {
        let body = try bookJSON(formats: #"["pdf"]"#, available: true)
        let book = try decode(body)
        let downloads = store()
        let count = Recorder<Int>()
        let recovered = Switch()
        let model = model(downloads) { request in
            if request.url?.path.hasSuffix("/file") == true {
                if recovered.isOn { return .init(status: 200, body: self.epub) }
                count.add(1)
                return count.all.count == 1
                    ? self.progress("layout", 3, 24)
                    : .init(status: 503, headers: ["Retry-After": "1"], body: Data(#"{"error":"library offline"}"#.utf8))
            }
            return request.url?.path.hasSuffix("/cover") == true ? .init(status: 404) : .init(status: 200, body: body)
        }

        await model.download(book)

        guard case .failed = model.transfer else { return XCTFail("expected failed, got \(model.transfer)") }
        XCTAssertFalse(downloads.isDownloaded(book.id))

        recovered.flip()
        await model.download(book)

        XCTAssertEqual(model.transfer, .done)
        XCTAssertEqual(downloads.fileURL(for: book.id)?.lastPathComponent, "\(book.id).epub")
    }

    func testLeavingTheScreenMidPassCancelsThePoll() async throws {
        let body = try bookJSON(formats: #"["pdf"]"#, available: true)
        let book = try decode(body)
        let downloads = store()
        let model = model(
            downloads,
            pause: { duration in _ = duration; try await Task.sleep(for: .seconds(60)) }
        ) { request in
            if request.url?.path.hasSuffix("/file") == true { return self.progress("layout", 1, 24) }
            return request.url?.path.hasSuffix("/cover") == true ? .init(status: 404) : .init(status: 200, body: body)
        }

        model.startDownload(book)
        let deadline = Date().addingTimeInterval(10)
        while !StubURLProtocol.requests.contains(where: isReflow), Date() < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        try await Task.sleep(for: .milliseconds(100))
        let before = StubURLProtocol.requests.count
        model.cancelDownload()
        await model.downloadTask?.value
        try await Task.sleep(for: .milliseconds(150))

        XCTAssertEqual(model.transfer, .idle)
        XCTAssertFalse(downloads.isDownloaded(book.id))
        XCTAssertEqual(StubURLProtocol.requests.count, before)
    }
}
