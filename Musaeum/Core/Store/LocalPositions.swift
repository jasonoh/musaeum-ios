import Foundation

/// Where the phone itself is in a book: a precise Readium locator plus the
/// fraction it corresponds to.
///
/// The fraction is the *only* coordinate that travels (the wire carries
/// `reading.percent`, and a locator is an engine coordinate no other engine can
/// use). Keeping a locator locally costs nothing and buys back the precision the
/// fraction loses, for the one reader that can use it — this one.
struct LocalPosition: Codable, Equatable, Sendable {
    var fraction: Double
    var locatorJSON: String
    var updatedAt: Date
}

@MainActor
@Observable
final class LocalPositions {
    private let file: URL
    private var map: [String: LocalPosition] = [:]

    init(root: URL? = nil) {
        let base = root ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Musaeum", isDirectory: true)
        file = base.appendingPathComponent("positions.json")
        if let data = try? Data(contentsOf: file),
           let decoded = try? JSONDecoder().decode([String: LocalPosition].self, from: data)
        {
            map = decoded
        }
    }

    func position(for bookId: String) -> LocalPosition? { map[bookId] }

    func fraction(for bookId: String) -> Double? { map[bookId]?.fraction }

    func record(bookId: String, fraction: Double, locatorJSON: String, at date: Date = Date()) {
        map[bookId] = LocalPosition(fraction: fraction, locatorJSON: locatorJSON, updatedAt: date)
        persist()
    }

    func forget(bookId: String) {
        map.removeValue(forKey: bookId)
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(map) else { return }
        try? FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: file, options: .atomic)
    }
}
