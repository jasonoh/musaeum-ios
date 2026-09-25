import Foundation

/// One book the phone has pulled, and **the payload exactly as the server sent
/// it**. The payload is stored verbatim rather than re-encoded from a struct so
/// that reading it back goes through the same strict contract decoder as a live
/// response: if the wire's shape moved, a downloaded book fails loudly on the way
/// in rather than half-mapping.
struct DownloadedBook: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let payload: Data
    let fileName: String
    /// A thumb-sized cover, kept beside the book so the shelf has faces with the
    /// Mac asleep — the covers are served by the Mac, and a shelf of grey
    /// rectangles is the whole offline story failing in the one place it shows.
    let coverFileName: String?
    let bytes: Int
    let downloadedAt: Date

    func book() throws -> ContractBook {
        do {
            return try JSONDecoder().decode(ContractBook.self, from: payload)
        } catch let error as ContractError {
            throw ClientError.decoding(error)
        } catch let error as DecodingError {
            throw ClientError.decoding(MusaeumClient.contractError(from: error))
        }
    }
}

/// The shelf that works when the Mac does not: this is the only local record of
/// books, and it exists because D14's promise — reading does not need the Mac —
/// has to survive the Mac being asleep.
@MainActor
@Observable
final class DownloadStore {
    private let root: URL
    private let indexFile: URL
    private let booksDirectory: URL
    /// Where a share's staged copy is put, and swept from. Not a store: it holds
    /// at most the file one share is in the middle of handing out.
    private let stagingDirectory: URL

    private(set) var downloads: [DownloadedBook] = []

    /// `root` is injectable so a case runs against a temporary directory.
    init(root: URL? = nil) {
        let base = root ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Musaeum", isDirectory: true)
        self.root = base
        indexFile = base.appendingPathComponent("downloads.json")
        booksDirectory = base.appendingPathComponent("Books", isDirectory: true)
        stagingDirectory = ShareStaging.directory(in: base)
        for directory in [booksDirectory, stagingDirectory] {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            // The books are a cache of files that live on the Mac, and a staged
            // share is on its way out; backing up either buys no reader anything
            // (CD6).
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            var mutable = directory
            try? mutable.setResourceValues(values)
        }
        // **What a share that was killed left behind, gone.** A sheet dismissal
        // sweeps the staged copy, but an app the OS or the user ends mid-share never
        // reaches it — and a staged 528 MiB book would then sit in the container
        // until the next share replaced it. Sweeping at launch is what makes the
        // directory mean what it says: it holds nothing unless a share is in flight
        // *right now*.
        ShareStaging.sweep(stagingDirectory)
        refresh()
    }

    var shelf: [DownloadedBook] { downloads.sorted { $0.downloadedAt > $1.downloadedAt } }

    func isDownloaded(_ id: String) -> Bool { downloads.contains { $0.id == id } }

    func downloaded(_ id: String) -> DownloadedBook? { downloads.first { $0.id == id } }

    func fileURL(for id: String) -> URL? {
        guard let record = downloaded(id) else { return nil }
        let url = booksDirectory.appendingPathComponent(record.fileName)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// Takes a temporary file (what `URLSession.download(for:)` produced) and the
    /// payload the server sent for that book. The local name is built from the
    /// **id and the format the server served** — the wire carries no path, and a
    /// canonical file name would be this client inventing one (invariant 2).
    @discardableResult
    func adopt(
        temporaryFile: URL,
        payload: Data,
        book: ContractBook,
        format: String,
        cover: Data? = nil
    ) throws -> DownloadedBook {
        let fileName = "\(book.id).\(format)"
        let destination = booksDirectory.appendingPathComponent(fileName)
        let manager = FileManager.default
        if manager.fileExists(atPath: destination.path) {
            try manager.removeItem(at: destination)
        }
        try manager.moveItem(at: temporaryFile, to: destination)
        let bytes = (try? manager.attributesOfItem(atPath: destination.path)[.size] as? Int) ?? nil

        var coverName: String?
        if let cover {
            let name = "\(book.id).cover.jpg"
            let coverURL = booksDirectory.appendingPathComponent(name)
            if manager.fileExists(atPath: coverURL.path) { try manager.removeItem(at: coverURL) }
            try cover.write(to: coverURL, options: .atomic)
            coverName = name
        }

        let record = DownloadedBook(
            id: book.id,
            payload: payload,
            fileName: fileName,
            coverFileName: coverName,
            bytes: bytes ?? 0,
            downloadedAt: Date()
        )
        downloads.removeAll { $0.id == book.id }
        downloads.append(record)
        try persist()
        return record
    }

    /// The thumb kept beside the book, so the shelf has faces with the Mac asleep.
    func coverData(for id: String) -> Data? {
        guard let record = downloaded(id), let name = record.coverFileName else { return nil }
        return try? Data(contentsOf: booksDirectory.appendingPathComponent(name))
    }

    /// **The file a share would hand out:** the stored download, staged under the
    /// name a recipient can read (`ShareStaging`).
    ///
    /// `nil` means the phone holds no file for this book — the condition both
    /// share doors use to decide whether they exist. Note what is *not* here: no
    /// request, no format question, no client. A share is the phone's own copy
    /// leaving, which is why it works with the Mac asleep.
    func stagedForSharing(_ book: ContractBook) throws -> ShareStaging.Staged? {
        guard let record = downloaded(book.id), let source = fileURL(for: book.id) else { return nil }
        let format = (record.fileName as NSString).pathExtension
        let name = ShareStaging.fileName(
            title: book.title,
            author: book.author,
            format: format,
            fallback: book.id
        )
        return try ShareStaging.stage(source: source, named: name, into: stagingDirectory)
    }

    /// What a share left, gone — called when the sheet is dismissed.
    func sweepStaging() {
        ShareStaging.sweep(stagingDirectory)
    }

    func remove(id: String) throws {
        guard let record = downloaded(id) else { return }
        let manager = FileManager.default
        let url = booksDirectory.appendingPathComponent(record.fileName)
        if manager.fileExists(atPath: url.path) {
            try manager.removeItem(at: url)
        }
        if let name = record.coverFileName {
            let coverURL = booksDirectory.appendingPathComponent(name)
            if manager.fileExists(atPath: coverURL.path) {
                try manager.removeItem(at: coverURL)
            }
        }
        downloads.removeAll { $0.id == id }
        try persist()
    }

    private func refresh() {
        guard let data = try? Data(contentsOf: indexFile) else {
            downloads = []
            return
        }
        downloads = (try? JSONDecoder().decode([DownloadedBook].self, from: data)) ?? []
    }

    private func persist() throws {
        let data = try JSONEncoder().encode(downloads)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try data.write(to: indexFile, options: .atomic)
    }
}
