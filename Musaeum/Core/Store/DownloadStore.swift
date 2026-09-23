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

    private(set) var downloads: [DownloadedBook] = []

    /// `root` is injectable so a case runs against a temporary directory.
    init(root: URL? = nil) {
        let base = root ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Musaeum", isDirectory: true)
        self.root = base
        indexFile = base.appendingPathComponent("downloads.json")
        booksDirectory = base.appendingPathComponent("Books", isDirectory: true)
        try? FileManager.default.createDirectory(at: booksDirectory, withIntermediateDirectories: true)
        // The books are a cache of files that live on the Mac; backing up half a
        // gigabyte of EPUBs to iCloud buys no reader anything (CD6).
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutable = booksDirectory
        try? mutable.setResourceValues(values)
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
