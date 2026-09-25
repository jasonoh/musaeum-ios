import Foundation

/// What the footer says (RP7): the chapter, and how far through the book.
enum ReaderFooterLabel {
    static func percent(_ progression: Double?) -> String? {
        guard let progression else { return nil }
        let clamped = min(max(progression, 0), 1)
        return "\(Int((clamped * 100).rounded()))%"
    }

    /// The locator's own title, else the contents entry for its file, else none.
    static func chapter(locatorTitle: String?, href: String?, toc: [ReaderTocEntry]) -> String? {
        if let title = locatorTitle?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
            return title
        }
        return ReaderTocEntry.current(href: href, in: toc)?.title
    }
}
